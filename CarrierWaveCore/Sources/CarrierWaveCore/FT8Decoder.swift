//
//  FT8Decoder.swift
//  CarrierWaveCore
//

import CFT8
import Foundation

// MARK: - FT8Decoder

/// Decodes FT8 signals from audio samples using ft8_lib.
public enum FT8Decoder: Sendable {
    // MARK: Public

    /// Decode FT8 messages from a buffer of audio samples.
    ///
    /// - Parameters:
    ///   - samples: Audio samples at 12,000 Hz sample rate, mono, Float.
    ///   - minFrequency: Minimum audio frequency to search (Hz). Default 100.
    ///   - maxFrequency: Maximum audio frequency to search (Hz). Default 3000.
    /// - Returns: Array of decoded FT8 messages with metadata.
    public static func decode(
        samples: [Float],
        minFrequency: Float = 100,
        maxFrequency: Float = 3_000
    ) -> [FT8DecodeResult] {
        guard samples.count >= FT8Constants.sampleRate else {
            return []
        }

        var monitor = configureMonitor(
            minFrequency: minFrequency,
            maxFrequency: maxFrequency
        )
        defer { monitor_free(&monitor) }

        feedSamples(samples, to: &monitor)

        let candidates = findCandidates(in: &monitor.wf)
        print(
            "[FT8Decoder] Candidates found: \(candidates.count), scores: \(candidates.prefix(5).map { Int($0.score) })"
        )
        return decodeCandidates(
            candidates,
            waterfall: &monitor.wf,
            minFrequency: minFrequency
        )
    }

    // MARK: - WAV Loading

    /// Load a 12 kHz mono 16-bit PCM WAV file into Float samples.
    public static func loadWAV(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else {
            throw FT8Error.invalidWAV("File too small for WAV header")
        }

        let header = try parseWAVHeader(data)
        try validateWAVHeader(header)

        return extractSamples(from: data, dataOffset: header.dataOffset)
    }

    // MARK: Private

    // MARK: - WAV Parsing

    private struct WAVHeader {
        let sampleRate: UInt32
        let bitsPerSample: UInt16
        let numChannels: UInt16
        let audioFormat: UInt16
        let dataOffset: Int
    }

    /// Maximum number of candidate signals to search for.
    private static let maxCandidates: Int32 = 140

    /// Minimum sync score threshold for candidate detection.
    private static let minScore: Int32 = 10

    /// Maximum LDPC decoder iterations.
    private static let maxLDPCIterations: Int32 = 25

    /// Time oversampling rate (subdivisions per symbol period).
    private static let timeOSR = 2

    /// Frequency oversampling rate (subdivisions per tone spacing).
    private static let freqOSR = 2

    /// "RIFF" as a little-endian UInt32 (0x46464952).
    private static let riffMarker: UInt32 = 0x4646_4952

    /// "WAVE" as a little-endian UInt32 (0x45564157).
    private static let waveMarker: UInt32 = 0x4556_4157

    /// "data" as a little-endian UInt32 (0x61746164).
    private static let dataMarker: UInt32 = 0x6174_6164

    // MARK: - Monitor Setup

    private static func configureMonitor(
        minFrequency: Float,
        maxFrequency: Float
    ) -> monitor_t {
        var config = monitor_config_t(
            f_min: minFrequency,
            f_max: maxFrequency,
            sample_rate: Int32(FT8Constants.sampleRate),
            time_osr: Int32(timeOSR),
            freq_osr: Int32(freqOSR),
            protocol: FTX_PROTOCOL_FT8
        )

        var monitor = monitor_t()
        monitor_init(&monitor, &config)
        return monitor
    }

    private static func feedSamples(_ samples: [Float], to monitor: inout monitor_t) {
        let blockSize = Int(monitor.block_size)
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            var offset = 0
            while offset + blockSize <= samples.count {
                monitor_process(&monitor, base + offset)
                offset += blockSize
            }
        }
    }

    // MARK: - Candidate Detection

    private static func findCandidates(
        in waterfall: inout ftx_waterfall_t
    ) -> [ftx_candidate_t] {
        var candidates = [ftx_candidate_t](
            repeating: ftx_candidate_t(),
            count: Int(maxCandidates)
        )
        let numFound = ftx_find_candidates(
            &waterfall,
            maxCandidates,
            &candidates,
            minScore
        )
        return Array(candidates.prefix(Int(numFound)))
    }

    // MARK: - Message Decoding

    private static func decodeCandidates(
        _ candidates: [ftx_candidate_t],
        waterfall: inout ftx_waterfall_t,
        minFrequency: Float
    ) -> [FT8DecodeResult] {
        var hashIF = makeHashInterface()
        var results: [FT8DecodeResult] = []
        var seenMessages = Set<String>()

        for candidate in candidates {
            guard let result = decodeCandidate(
                candidate,
                waterfall: &waterfall,
                hashInterface: &hashIF,
                minFrequency: minFrequency,
                seenMessages: &seenMessages
            ) else {
                continue
            }
            results.append(result)
        }

        return results
    }

    private static func decodeCandidate(
        _ candidate: ftx_candidate_t,
        waterfall: inout ftx_waterfall_t,
        hashInterface: inout ftx_callsign_hash_interface_t,
        minFrequency: Float,
        seenMessages: inout Set<String>
    ) -> FT8DecodeResult? {
        var message = ftx_message_t()
        var status = ftx_decode_status_t()
        var mutableCandidate = candidate

        let decoded = ftx_decode_candidate(
            &waterfall,
            &mutableCandidate,
            maxLDPCIterations,
            &message,
            &status
        )
        guard decoded else {
            return nil
        }

        var textBuffer = [CChar](repeating: 0, count: Int(FTX_MAX_MESSAGE_LENGTH) + 1)
        var offsets = ftx_message_offsets_t()
        ftx_message_decode(&message, &hashInterface, &textBuffer, &offsets)

        let messageText = String(cString: textBuffer)
        guard !messageText.isEmpty, !seenMessages.contains(messageText) else {
            return nil
        }
        seenMessages.insert(messageText)

        // Use status fields for frequency/time when available, fall back to candidate offsets
        let freqHz = statusFrequency(status, candidate: candidate, minFrequency: minFrequency)
        let timeSec = statusTime(status, candidate: candidate)

        // Sync score scaled to approximate SNR range. This is NOT a true dB SNR —
        // proper SNR requires noise floor estimation from the waterfall.
        let snr = Int(round(Double(candidate.score) * 0.5))

        let parsed = FT8Message.parse(messageText)
        return FT8DecodeResult(
            message: parsed,
            snr: snr,
            deltaTime: timeSec,
            frequency: freqHz,
            rawText: messageText
        )
    }

    private static func statusFrequency(
        _ status: ftx_decode_status_t,
        candidate: ftx_candidate_t,
        minFrequency: Float
    ) -> Double {
        if status.freq > 0 {
            return Double(status.freq)
        }
        // Fallback: compute from candidate offset (divided by freq oversampling rate)
        return Double(candidate.freq_offset) * FT8Constants.toneSpacing / Double(freqOSR)
            + Double(minFrequency)
    }

    private static func statusTime(
        _ status: ftx_decode_status_t,
        candidate: ftx_candidate_t
    ) -> Double {
        if status.time != 0 {
            return Double(status.time)
        }
        // Fallback: compute from candidate offset (divided by time oversampling rate)
        return Double(candidate.time_offset) * FT8Constants.symbolPeriod / Double(timeOSR)
    }

    // MARK: - Hash Interface

    private static func makeHashInterface() -> ftx_callsign_hash_interface_t {
        ftx_callsign_hash_interface_t(
            lookup_hash: { _, _, _ in
                // For decode-only use, returning false shows <...> for hashed callsigns
                false
            },
            save_hash: { _, _ in
                // No persistence across decode calls in this implementation
            }
        )
    }

    private static func parseWAVHeader(_ data: Data) throws -> WAVHeader {
        try data.withUnsafeBytes { ptr in
            // Validate RIFF container and WAVE format
            let riff = UInt32(littleEndian: ptr.load(fromByteOffset: 0, as: UInt32.self))
            guard riff == riffMarker else {
                throw FT8Error.invalidWAV("Not a RIFF file")
            }
            let wave = UInt32(littleEndian: ptr.load(fromByteOffset: 8, as: UInt32.self))
            guard wave == waveMarker else {
                throw FT8Error.invalidWAV("Not a WAVE file")
            }

            let audioFormat = UInt16(littleEndian: ptr.load(fromByteOffset: 20, as: UInt16.self))
            let numChannels = UInt16(littleEndian: ptr.load(fromByteOffset: 22, as: UInt16.self))
            let sampleRate = UInt32(littleEndian: ptr.load(fromByteOffset: 24, as: UInt32.self))
            let bitsPerSample = UInt16(littleEndian: ptr.load(fromByteOffset: 34, as: UInt16.self))

            // Scan for the "data" chunk (may not be at offset 44 if extra chunks exist)
            let dataOffset = try findDataChunk(in: ptr, fileSize: data.count)

            return WAVHeader(
                sampleRate: sampleRate,
                bitsPerSample: bitsPerSample,
                numChannels: numChannels,
                audioFormat: audioFormat,
                dataOffset: dataOffset
            )
        }
    }

    /// Scan RIFF chunks starting after the WAVE header to find the "data" chunk.
    /// Returns the byte offset where audio sample data begins.
    private static func findDataChunk(
        in ptr: UnsafeRawBufferPointer,
        fileSize: Int
    ) throws -> Int {
        var offset = 12 // Skip "RIFF" (4) + size (4) + "WAVE" (4)
        while offset + 8 <= fileSize {
            let chunkID = UInt32(littleEndian: ptr.load(fromByteOffset: offset, as: UInt32.self))
            let chunkSize = Int(UInt32(littleEndian: ptr.load(
                fromByteOffset: offset + 4,
                as: UInt32.self
            )))
            if chunkID == dataMarker {
                return offset + 8 // Data starts after chunk ID (4) + size (4)
            }
            offset += 8 + chunkSize
        }
        throw FT8Error.invalidWAV("No data chunk found in WAV file")
    }

    private static func validateWAVHeader(_ header: WAVHeader) throws {
        guard header.audioFormat == 1 else {
            throw FT8Error.invalidWAV("Expected PCM format (1), got \(header.audioFormat)")
        }
        guard header.sampleRate == 12_000 else {
            throw FT8Error.invalidWAV("Expected 12000 Hz, got \(header.sampleRate)")
        }
        guard header.bitsPerSample == 16 else {
            throw FT8Error.invalidWAV("Expected 16-bit, got \(header.bitsPerSample)")
        }
        guard header.numChannels == 1 else {
            throw FT8Error.invalidWAV("Expected mono, got \(header.numChannels) channels")
        }
    }

    private static func extractSamples(from data: Data, dataOffset: Int) -> [Float] {
        let audioData = data.dropFirst(dataOffset)
        let sampleCount = audioData.count / 2 // 16-bit = 2 bytes per sample

        var samples = [Float](repeating: 0, count: sampleCount)
        audioData.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for idx in 0 ..< sampleCount {
                samples[idx] = Float(Int16(littleEndian: int16Ptr[idx])) / 32_768.0
            }
        }
        return samples
    }
}

// MARK: - FT8Error

/// Errors from FT8 operations.
public enum FT8Error: Error, Sendable {
    case invalidWAV(String)
    case encodingFailed(String)
}
