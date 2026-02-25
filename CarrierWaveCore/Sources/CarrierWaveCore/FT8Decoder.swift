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
        return decodeCandidates(
            candidates,
            waterfall: &monitor.wf,
            minFrequency: minFrequency
        )
    }

    // MARK: - WAV Loading

    /// Load a 12 kHz mono WAV file into Float samples.
    public static func loadWAV(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else {
            throw FT8Error.invalidWAV("File too small for WAV header")
        }

        let header = parseWAVHeader(data)
        try validateWAVHeader(header)

        return extractSamples(from: data)
    }

    // MARK: Private

    // MARK: - WAV Parsing

    private struct WAVHeader {
        let sampleRate: UInt32
        let bitsPerSample: UInt16
        let numChannels: UInt16
    }

    /// Maximum number of candidate signals to search for.
    private static let maxCandidates: Int32 = 140

    /// Minimum sync score threshold for candidate detection.
    private static let minScore: Int32 = 10

    /// Maximum LDPC decoder iterations.
    private static let maxLDPCIterations: Int32 = 25

    // MARK: - Monitor Setup

    private static func configureMonitor(
        minFrequency: Float,
        maxFrequency: Float
    ) -> monitor_t {
        var config = monitor_config_t(
            f_min: minFrequency,
            f_max: maxFrequency,
            sample_rate: Int32(FT8Constants.sampleRate),
            time_osr: 2,
            freq_osr: 2,
            protocol: FTX_PROTOCOL_FT8
        )

        var monitor = monitor_t()
        monitor_init(&monitor, &config)
        return monitor
    }

    private static func feedSamples(_ samples: [Float], to monitor: inout monitor_t) {
        let blockSize = Int(monitor.block_size)
        var offset = 0
        while offset + blockSize <= samples.count {
            samples.withUnsafeBufferPointer { buffer in
                monitor_process(&monitor, buffer.baseAddress! + offset)
            }
            offset += blockSize
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
        var mutableCandidates = candidates

        for idx in mutableCandidates.indices {
            guard let result = decodeCandidate(
                &mutableCandidates[idx],
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
        _ candidate: inout ftx_candidate_t,
        waterfall: inout ftx_waterfall_t,
        hashInterface: inout ftx_callsign_hash_interface_t,
        minFrequency: Float,
        seenMessages: inout Set<String>
    ) -> FT8DecodeResult? {
        var message = ftx_message_t()
        var status = ftx_decode_status_t()

        let decoded = ftx_decode_candidate(
            &waterfall,
            &candidate,
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

        // Approximate SNR from candidate sync score (matches ft8_lib demo approach)
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
        // Fallback: compute from candidate offset
        return Double(candidate.freq_offset) * FT8Constants.toneSpacing / 2.0
            + Double(minFrequency)
    }

    private static func statusTime(
        _ status: ftx_decode_status_t,
        candidate: ftx_candidate_t
    ) -> Double {
        if status.time != 0 {
            return Double(status.time)
        }
        // Fallback: compute from candidate offset
        return Double(candidate.time_offset) * FT8Constants.symbolPeriod / 2.0
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

    private static func parseWAVHeader(_ data: Data) -> WAVHeader {
        data.withUnsafeBytes { ptr in
            WAVHeader(
                sampleRate: ptr.load(fromByteOffset: 24, as: UInt32.self),
                bitsPerSample: ptr.load(fromByteOffset: 34, as: UInt16.self),
                numChannels: ptr.load(fromByteOffset: 22, as: UInt16.self)
            )
        }
    }

    private static func validateWAVHeader(_ header: WAVHeader) throws {
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

    private static func extractSamples(from data: Data) -> [Float] {
        let audioData = data.dropFirst(44) // Standard WAV header size
        let sampleCount = audioData.count / 2 // 16-bit = 2 bytes per sample

        var samples = [Float](repeating: 0, count: sampleCount)
        audioData.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for idx in 0 ..< sampleCount {
                samples[idx] = Float(int16Ptr[idx]) / 32_768.0
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
