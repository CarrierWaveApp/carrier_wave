import Foundation

// MARK: - SCULAN10Transport+Diagnostic

//
// Audio-frame inspection helpers. Lifted out of `SCULAN10Transport` so the
// main file stays inside SwiftLint's `file_length` cap. The instance state
// these methods touch (`captureRawBodies` etc.) lives on the actor itself
// — extensions can't add stored properties but can read/write them.
//
// On the first 8 frames (plus snapshots at 100 and 200) `dumpAudioFrame`
// writes a hex dump of bytes 0-31 + 32-63 plus byte-distribution stats to
// the radio command log. `appendCapture` buffers the first 200 decrypted
// bodies and writes two files to `~/Downloads/` once the buffer fills:
//
//   - cw-sweep-audio-raw.bin: each record is `[u32-le length][body]`, so an
//     analyzer (Python, hex viewer) can iterate full decrypted bodies.
//   - cw-sweep-audio-pcm16-16k-mono.raw: concatenated post-inner-header
//     regions. If the format hypothesis is right, this plays back cleanly
//     with `sox -t raw -r 16000 -e signed -b 16 -c 1 file.raw out.wav`.
//
// The capture is one-shot per transport instance; reconnecting the radio
// creates a new transport and a fresh file.
//

extension SCULAN10Transport {
    /// Bytes skipped from each decrypted audio body before the PCM region.
    static let audioInnerHeaderBytes = 24

    /// Take Ch0 from a 4-byte interleaved stereo Int16 LE buffer.
    static func extractLeftChannel(fromStereo stereo: Data) -> Data {
        let bytesPerSample = MemoryLayout<Int16>.size
        let bytesPerStereoFrame = bytesPerSample * 2
        let frames = stereo.count / bytesPerStereoFrame
        guard frames > 0 else {
            return Data()
        }
        var mono = Data(count: frames * bytesPerSample)
        stereo.withUnsafeBytes { srcRaw in
            mono.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.bindMemory(to: Int16.self).baseAddress,
                      let dst = dstRaw.bindMemory(to: Int16.self).baseAddress
                else {
                    return
                }
                for idx in 0 ..< frames {
                    dst[idx] = src[idx * 2]
                }
            }
        }
        return mono
    }

    /// How many frames to capture into the on-disk diagnostic files. Enough
    /// to give an offline analyzer ~4 seconds of audio at 50 fps to work
    /// with, while keeping the file under ~150 KB.
    static var captureFrameTarget: Int {
        200
    }

    func appendCapture(
        decrypted: Data,
        status: (@Sendable (String) -> Void)?
    ) {
        guard !captureWritten else {
            return
        }
        var lengthLE = UInt32(decrypted.count).littleEndian
        captureRawBodies.append(
            Data(bytes: &lengthLE, count: MemoryLayout<UInt32>.size)
        )
        captureRawBodies.append(decrypted)
        if decrypted.count > Self.audioInnerHeaderBytes {
            capturePCMAfterHeader.append(
                decrypted.dropFirst(Self.audioInnerHeaderBytes)
            )
        }
        captureFrameCount += 1
        if captureFrameCount >= Self.captureFrameTarget {
            writeCaptureFiles(status: status)
        }
    }

    func writeCaptureFiles(
        status: (@Sendable (String) -> Void)?
    ) {
        captureWritten = true
        let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let rawURL = downloads.appendingPathComponent("cw-sweep-audio-raw.bin")
        let pcmURL = downloads.appendingPathComponent(
            "cw-sweep-audio-pcm16-16k-mono.raw"
        )
        do {
            try captureRawBodies.write(to: rawURL, options: .atomic)
            try capturePCMAfterHeader.write(to: pcmURL, options: .atomic)
            status?(
                "AUDIO capture saved: \(rawURL.lastPathComponent) " +
                    "(\(captureRawBodies.count)B), " +
                    "\(pcmURL.lastPathComponent) (\(capturePCMAfterHeader.count)B) " +
                    "in ~/Downloads"
            )
        } catch {
            status?("AUDIO capture write failed: \(error.localizedDescription)")
        }
    }

    /// Emit a multi-line dump of one decrypted audio body to the connection
    /// log. We log enough bytes to identify the codec by eye:
    ///   - first 32 bytes (header region: frame_seq, codec config, RSSI etc.)
    ///   - next 32 bytes from the sample region (so we can tell PCM vs μ-law)
    ///   - per-byte stats over the *sample region* (min/max/avg/zero-crossings)
    ///     which let us distinguish PCM16 (small unsigned values clustered
    ///     near the middle of the byte range, frequent near-zero pairs) from
    ///     μ-law (full-byte-range values, no near-zero clustering, alternating
    ///     high/low patterns) from PCM8 (signed bytes around 0x80) etc.
    static func dumpAudioFrame(
        index: Int,
        decrypted: Data,
        status: (@Sendable (String) -> Void)?
    ) {
        guard let status else {
            return
        }
        let total = decrypted.count
        let head = decrypted.prefix(32)
        let headHex = head.map { String(format: "%02X", $0) }.joined(separator: " ")
        status("AUDIO[\(index)] body=\(total)B head32=\(headHex)")

        if total > 32 {
            let mid = decrypted.subdata(in: 32 ..< min(total, 64))
            let midHex = mid.map { String(format: "%02X", $0) }.joined(separator: " ")
            status("AUDIO[\(index)] mid32=\(midHex)")
        }

        if total > audioInnerHeaderBytes {
            dumpSampleStats(
                index: index,
                samples: decrypted.dropFirst(audioInnerHeaderBytes),
                status: status
            )
        }
    }

    private static func dumpSampleStats(
        index: Int,
        samples: Data,
        status: @Sendable (String) -> Void
    ) {
        var minByte: UInt8 = 0xFF
        var maxByte: UInt8 = 0x00
        var sum: UInt64 = 0
        var nearZeroPairs = 0
        var bytes = [UInt8](repeating: 0, count: samples.count)
        samples.copyBytes(to: &bytes, count: samples.count)
        for byte in bytes {
            if byte < minByte {
                minByte = byte
            }
            if byte > maxByte {
                maxByte = byte
            }
            sum &+= UInt64(byte)
        }
        let avg = bytes.isEmpty ? 0 : Double(sum) / Double(bytes.count)
        // Count "near zero" Int16 LE pairs (low byte any, high byte 0x00 or 0xFF).
        var idx = 0
        while idx + 1 < bytes.count {
            let hi = bytes[idx + 1]
            if hi == 0x00 || hi == 0xFF {
                nearZeroPairs += 1
            }
            idx += 2
        }
        let pairCount = bytes.count / 2
        let nearZeroPct = pairCount > 0 ? (nearZeroPairs * 100 / pairCount) : 0
        status(
            "AUDIO[\(index)] samples min=\(minByte) max=\(maxByte) " +
                "avg=\(String(format: "%.1f", avg)) pcm16NearZero=\(nearZeroPct)%"
        )
    }
}
