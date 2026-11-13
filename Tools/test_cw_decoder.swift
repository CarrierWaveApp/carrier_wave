#!/usr/bin/env swift

// CW Decoder Test Harness
// Usage: swift test_cw_decoder.swift <wav_file> [tone_frequency] [wpm|adaptive]
//
// Reads a WAV file and runs it through the Goertzel CW decoder.
// Prints the decoded text and timing analysis.
//
// Use "adaptive" instead of a WPM number to enable adaptive WPM estimation.

import Accelerate
import Foundation

// MARK: - WAVFile

struct WAVFile {
    // MARK: Internal

    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    let samples: [Float]

    static func read(from url: URL) throws -> WAVFile {
        let data = try Data(contentsOf: url)

        // Parse RIFF header
        guard data.count > 44 else {
            throw WAVError.invalidFormat("File too small")
        }

        let riff = String(data: data[0 ..< 4], encoding: .ascii)
        guard riff == "RIFF" else {
            throw WAVError.invalidFormat("Not a RIFF file")
        }

        let wave = String(data: data[8 ..< 12], encoding: .ascii)
        guard wave == "WAVE" else {
            throw WAVError.invalidFormat("Not a WAVE file")
        }

        // Find fmt chunk
        var offset = 12
        var fmtChunkFound = false
        var audioFormat: UInt16 = 0
        var channels: UInt16 = 0
        var sampleRate: UInt32 = 0
        var bitsPerSample: UInt16 = 0

        while offset < data.count - 8 {
            let chunkID = String(data: data[offset ..< offset + 4], encoding: .ascii) ?? ""
            let chunkSize = data.subdata(in: offset + 4 ..< offset + 8)
                .withUnsafeBytes { $0.load(as: UInt32.self) }

            if chunkID == "fmt " {
                audioFormat = data.subdata(in: offset + 8 ..< offset + 10)
                    .withUnsafeBytes { $0.load(as: UInt16.self) }
                channels = data.subdata(in: offset + 10 ..< offset + 12)
                    .withUnsafeBytes { $0.load(as: UInt16.self) }
                sampleRate = data.subdata(in: offset + 12 ..< offset + 16)
                    .withUnsafeBytes { $0.load(as: UInt32.self) }
                bitsPerSample = data.subdata(in: offset + 22 ..< offset + 24)
                    .withUnsafeBytes { $0.load(as: UInt16.self) }
                fmtChunkFound = true
            }

            if chunkID == "data" {
                guard fmtChunkFound else {
                    throw WAVError.invalidFormat("fmt chunk not found before data")
                }
                guard audioFormat == 1 else {
                    throw WAVError.invalidFormat("Only PCM format supported (got \(audioFormat))")
                }

                let dataStart = offset + 8
                let dataEnd = min(dataStart + Int(chunkSize), data.count)
                let audioData = data.subdata(in: dataStart ..< dataEnd)

                let samples = try parseSamples(
                    audioData,
                    bitsPerSample: Int(bitsPerSample),
                    channels: Int(channels)
                )

                return WAVFile(
                    sampleRate: Int(sampleRate),
                    channels: Int(channels),
                    bitsPerSample: Int(bitsPerSample),
                    samples: samples
                )
            }

            offset += 8 + Int(chunkSize)
        }

        throw WAVError.invalidFormat("data chunk not found")
    }

    // MARK: Private

    private static func parseSamples(_ data: Data, bitsPerSample: Int, channels: Int) throws
        -> [Float]
    {
        var samples: [Float] = []

        switch bitsPerSample {
        case 16:
            let bytesPerSample = 2 * channels
            var offset = 0
            while offset + bytesPerSample <= data.count {
                // Read first channel only for mono processing
                let sample = data.subdata(in: offset ..< offset + 2)
                    .withUnsafeBytes { $0.load(as: Int16.self) }
                samples.append(Float(sample) / Float(Int16.max))
                offset += bytesPerSample
            }
        case 8:
            let bytesPerSample = channels
            var offset = 0
            while offset + bytesPerSample <= data.count {
                let sample = data[offset]
                // 8-bit WAV is unsigned, centered at 128
                samples.append((Float(sample) - 128.0) / 128.0)
                offset += bytesPerSample
            }
        default:
            throw WAVError.invalidFormat("Unsupported bits per sample: \(bitsPerSample)")
        }

        return samples
    }
}

// MARK: - WAVError

enum WAVError: Error {
    case invalidFormat(String)
}

// MARK: - GoertzelFilter

struct GoertzelFilter {
    // MARK: Lifecycle

    init(targetFrequency: Double, sampleRate: Double, blockSize: Int) {
        self.targetFrequency = targetFrequency
        self.sampleRate = sampleRate
        self.blockSize = blockSize

        let k = targetFrequency * Double(blockSize) / sampleRate
        let omega = 2.0 * Double.pi * k / Double(blockSize)
        coefficient = 2.0 * cos(omega)
        cosOmega = cos(omega)
        sinOmega = sin(omega)
    }

    // MARK: Internal

    let targetFrequency: Double
    let sampleRate: Double
    let blockSize: Int
    let coefficient: Double

    func processSamples(_ samples: [Float]) -> Float {
        var s1 = 0.0
        var s2 = 0.0

        for sample in samples {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }

        let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
        let magnitude = sqrt(max(0, power)) / Double(blockSize)
        return Float(magnitude)
    }

    // MARK: Private

    private let cosOmega: Double
    private let sinOmega: Double
}

// MARK: - ThresholdConfig

struct ThresholdConfig {
    static let `default` = ThresholdConfig()

    static let noisy = ThresholdConfig(
        calibrationBlocks: 30,
        confirmationBlocks: 4,
        minimumStateDuration: 0.025,
        onThreshold: 12.0,
        offThreshold: 5.0,
        dropThreshold: 0.30,
        peakDecay: 0.99,
        noiseDecay: 0.998,
        noiseRise: 0.7,
        activeDecay: 0.96
    )

    static let aggressive = ThresholdConfig(
        calibrationBlocks: 40,
        confirmationBlocks: 5,
        minimumStateDuration: 0.030,
        onThreshold: 15.0,
        offThreshold: 6.0,
        dropThreshold: 0.25,
        peakDecay: 0.985,
        noiseDecay: 0.999,
        noiseRise: 0.6,
        activeDecay: 0.95
    )

    var calibrationBlocks: Int = 20 // Blocks to wait before detecting (was 10)
    var confirmationBlocks: Int = 3 // Consecutive blocks needed to confirm state change (was 2)
    var minimumStateDuration: TimeInterval = 0.020 // Min time between state changes (was 0.015)
    var onThreshold: Float = 8.0 // Ratio to trigger key-down (was 6.0)
    var offThreshold: Float = 4.0 // Ratio to trigger key-up (was 3.0)
    var dropThreshold: Float = 0.35 // Relative drop to trigger key-up (was 0.4)
    var peakDecay: Float = 0.995 // How fast peak estimate decays
    var noiseDecay: Float = 0.995 // How fast noise floor decays when signal present (was 0.99)
    var noiseRise: Float = 0.92 // How fast noise floor rises to match actual noise (was 0.8)
    var activeDecay: Float = 0.97 // How fast active signal level decays (was 0.98)
}

// MARK: - GoertzelThreshold

struct GoertzelThreshold {
    // MARK: Lifecycle

    init(config: ThresholdConfig = .default) {
        self.config = config
    }

    // MARK: Internal

    var currentKeyState: Bool {
        isKeyDown
    }

    var isCalibrating: Bool {
        blockCount < config.calibrationBlocks
    }

    var currentNoiseFloor: Float {
        noiseFloor
    }

    var currentSignalPeak: Float {
        signalPeak
    }

    mutating func process(
        magnitude: Float,
        blockDuration: Double,
        blockStartTime: TimeInterval
    ) -> (isDown: Bool, timestamp: TimeInterval)? {
        blockCount += 1
        updateSignalEstimates(magnitude: magnitude)

        guard !isCalibrating else {
            return nil
        }

        let ratio = magnitude / max(noiseFloor, 0.0001)

        if ratio > config.onThreshold {
            blocksAboveThreshold += 1
            blocksBelowThreshold = 0
        } else if ratio < config.offThreshold {
            blocksBelowThreshold += 1
            blocksAboveThreshold = 0
        } else {
            blocksAboveThreshold = max(0, blocksAboveThreshold - 1)
            blocksBelowThreshold = max(0, blocksBelowThreshold - 1)
        }

        let wasKeyDown = isKeyDown
        let timeSinceChange = blockStartTime - lastStateChangeTime

        if !isKeyDown {
            if blocksAboveThreshold >= config.confirmationBlocks,
               timeSinceChange >= config.minimumStateDuration
            {
                isKeyDown = true
                activeSignalLevel = magnitude
                blocksAboveThreshold = 0
            }
        } else {
            if magnitude > activeSignalLevel {
                activeSignalLevel = magnitude
            } else {
                activeSignalLevel *= config.activeDecay
            }

            let relativeDrop = magnitude / max(activeSignalLevel, 0.0001)
            if timeSinceChange >= config.minimumStateDuration {
                if blocksBelowThreshold >= config.confirmationBlocks
                    || relativeDrop < config.dropThreshold
                {
                    isKeyDown = false
                    blocksBelowThreshold = 0
                }
            }
        }

        if isKeyDown != wasKeyDown {
            lastStateChangeTime = blockStartTime
            let eventTime = blockStartTime + blockDuration / 2
            return (isDown: isKeyDown, timestamp: eventTime)
        }

        return nil
    }

    // MARK: Private

    private var signalPeak: Float = 0
    private var noiseFloor: Float = 1.0
    private var isKeyDown = false
    private var blockCount: Int = 0
    private var activeSignalLevel: Float = 0
    private var lastStateChangeTime: TimeInterval = 0
    private var blocksAboveThreshold: Int = 0
    private var blocksBelowThreshold: Int = 0

    private let config: ThresholdConfig

    private mutating func updateSignalEstimates(magnitude: Float) {
        if magnitude > signalPeak {
            signalPeak = magnitude
        } else {
            signalPeak *= config.peakDecay
        }

        if magnitude < noiseFloor {
            // Noise floor drops quickly to track actual noise
            noiseFloor = noiseFloor * config.noiseRise + magnitude * (1.0 - config.noiseRise)
        } else if magnitude < noiseFloor * 2 {
            // When slightly above noise, slowly adapt upward
            noiseFloor = noiseFloor * config.noiseDecay + magnitude * (1.0 - config.noiseDecay)
        }
        // Also slowly raise noise floor if we're seeing consistently higher values
        // This helps track changing noise conditions
        if magnitude > noiseFloor, magnitude < noiseFloor * config.onThreshold {
            noiseFloor = noiseFloor * 0.999 + magnitude * 0.001
        }
        noiseFloor = max(noiseFloor, 0.0001)
    }
}

// MARK: - MorseCode

enum MorseCode {
    enum Timing {
        static let ditUnits: Double = 1.0
        static let dahUnits: Double = 3.0

        static func unitDuration(forWPM wpm: Int) -> TimeInterval {
            // PARIS standard: 50 units per word
            1.2 / Double(wpm)
        }

        static func wpm(fromUnitDuration unit: TimeInterval) -> Int {
            max(5, min(60, Int(round(1.2 / unit))))
        }
    }

    static let decodeTable: [String: String] = [
        ".-": "A", "-...": "B", "-.-.": "C", "-..": "D", ".": "E",
        "..-.": "F", "--.": "G", "....": "H", "..": "I", ".---": "J",
        "-.-": "K", ".-..": "L", "--": "M", "-.": "N", "---": "O",
        ".--.": "P", "--.-": "Q", ".-.": "R", "...": "S", "-": "T",
        "..-": "U", "...-": "V", ".--": "W", "-..-": "X", "-.--": "Y",
        "--..": "Z",
        "-----": "0", ".----": "1", "..---": "2", "...--": "3", "....-": "4",
        ".....": "5", "-....": "6", "--...": "7", "---..": "8", "----.": "9",
        ".-.-.-": ".", "--..--": ",", "..--..": "?", ".----.": "'",
        "-.-.--": "!", "-..-.": "/", "-.--.": "(", "-.--.-": ")",
        ".-...": "&", "---...": ":", "-.-.-.": ";", "-...-": "=",
        ".-.-.": "+", "-....-": "-", "..--.-": "_", ".-..-.": "\"",
        "...-..-": "$", ".--.-.": "@",
    ]

    static func decode(_ pattern: String) -> String? {
        decodeTable[pattern]
    }
}

// MARK: - MorseElement

enum MorseElement: Equatable {
    case dit
    case dah
    case elementGap
    case charGap
    case wordGap

    // MARK: Internal

    var symbol: String {
        switch self {
        case .dit: "."
        case .dah: "-"
        case .elementGap: ""
        case .charGap: " "
        case .wordGap: "  "
        }
    }
}

// MARK: - DecodedOutput

enum DecodedOutput: Equatable {
    case character(String)
    case wordSpace
    case element(MorseElement)
}

// MARK: - MorseDecoder

class MorseDecoder {
    // MARK: Lifecycle

    init(initialWPM: Int = 20, adaptive: Bool = true) {
        estimatedWPM = initialWPM
        unitDuration = MorseCode.Timing.unitDuration(forWPM: initialWPM)
        manualWPMMode = !adaptive
    }

    // MARK: Internal

    func processKeyEvent(isKeyDown: Bool, timestamp: TimeInterval) -> [DecodedOutput] {
        var outputs: [DecodedOutput] = []

        if lastStateChange == 0 {
            lastStateChange = timestamp
            lastKeyDown = isKeyDown
            lastElementTime = timestamp
            return outputs
        }

        let duration = timestamp - lastStateChange

        if lastKeyDown, !isKeyDown {
            if duration < minimumToneDuration {
                lastKeyDown = isKeyDown
                lastStateChange = timestamp
                return outputs
            }

            let element = classifyToneDuration(duration)
            outputs.append(.element(element))
            currentPattern += element.symbol

            let elementName = element == .dit ? "DIT" : "DAH"
            print(
                "  [TONE] \(elementName) \(String(format: "%.0f", duration * 1_000))ms -> pattern: \(currentPattern)"
            )

            updateWPMEstimate(duration: duration, element: element)
            lastElementTime = timestamp
        } else if !lastKeyDown, isKeyDown {
            if duration < minimumGapDuration {
                return outputs
            }

            let gapOutput = processGap(duration: duration)
            outputs.append(contentsOf: gapOutput)
            lastElementTime = timestamp
        }

        lastKeyDown = isKeyDown
        lastStateChange = timestamp

        return outputs
    }

    func checkTimeout(currentTime: TimeInterval) -> [DecodedOutput] {
        guard !currentPattern.isEmpty else {
            return []
        }

        let silenceDuration = currentTime - lastElementTime
        let timeoutDuration = unitDuration * charTimeoutUnits

        if silenceDuration > timeoutDuration {
            return flushCurrentCharacter()
        }

        return []
    }

    func getEstimatedWPM() -> Int {
        estimatedWPM
    }

    // MARK: Private

    private var estimatedWPM: Int
    private var unitDuration: TimeInterval
    private var currentPattern: String = ""
    private var lastKeyDown: Bool = false
    private var lastStateChange: TimeInterval = 0
    private var recentDurations: [TimeInterval] = []
    private var lastElementTime: TimeInterval = 0
    private var manualWPMMode: Bool = false

    private let minWPM: Int = 5
    private let maxWPM: Int = 60
    private let timingTolerance: Double = 0.5
    private let minimumToneDuration: TimeInterval = 0.025
    private let minimumGapDuration: TimeInterval = 0.020
    private let minSamplesForAdaptation: Int = 5
    private let maxDurationSamples: Int = 20
    private let charTimeoutUnits: Double = 5.0

    private func classifyToneDuration(_ duration: TimeInterval) -> MorseElement {
        let threshold = unitDuration * 2.0
        let toleranceRange = unitDuration * timingTolerance

        if duration < threshold - toleranceRange {
            return .dit
        } else if duration > threshold + toleranceRange {
            return .dah
        } else {
            let ditDistance = abs(duration - unitDuration)
            let dahDistance = abs(duration - unitDuration * 3)
            return ditDistance < dahDistance ? .dit : .dah
        }
    }

    private func processGap(duration: TimeInterval) -> [DecodedOutput] {
        var outputs: [DecodedOutput] = []

        let charGapThreshold = unitDuration * 2.5
        let wordGapThreshold = unitDuration * 5.5

        if duration < charGapThreshold {
            outputs.append(.element(.elementGap))
        } else if duration < wordGapThreshold {
            outputs.append(.element(.charGap))
            outputs.append(contentsOf: flushCurrentCharacter())
            print("  [GAP] char gap \(String(format: "%.0f", duration * 1_000))ms")
        } else {
            outputs.append(.element(.wordGap))
            outputs.append(contentsOf: flushCurrentCharacter())
            outputs.append(.wordSpace)
            print("  [GAP] word gap \(String(format: "%.0f", duration * 1_000))ms")
        }

        return outputs
    }

    private func flushCurrentCharacter() -> [DecodedOutput] {
        guard !currentPattern.isEmpty else {
            return []
        }

        var outputs: [DecodedOutput] = []

        if let decoded = MorseCode.decode(currentPattern) {
            print("  [DECODE] '\(currentPattern)' -> '\(decoded)'")
            outputs.append(.character(decoded))
        } else {
            print("  [DECODE] '\(currentPattern)' -> UNKNOWN")
            outputs.append(.character("[\(currentPattern)]"))
        }

        currentPattern = ""
        return outputs
    }

    private func updateWPMEstimate(duration: TimeInterval, element: MorseElement) {
        guard !manualWPMMode else {
            return
        }
        guard element == .dit || element == .dah else {
            return
        }

        let estimatedUnit: TimeInterval =
            if element == .dit {
                duration / MorseCode.Timing.ditUnits
            } else {
                duration / MorseCode.Timing.dahUnits
            }

        let minUnit = MorseCode.Timing.unitDuration(forWPM: maxWPM)
        let maxUnit = MorseCode.Timing.unitDuration(forWPM: minWPM)
        guard estimatedUnit >= minUnit, estimatedUnit <= maxUnit else {
            return
        }

        recentDurations.append(estimatedUnit)
        if recentDurations.count > maxDurationSamples {
            recentDurations.removeFirst()
        }

        guard recentDurations.count >= minSamplesForAdaptation else {
            return
        }

        let sorted = recentDurations.sorted()
        let medianUnit = sorted[sorted.count / 2]

        let smoothingFactor = 0.15
        unitDuration = unitDuration * (1 - smoothingFactor) + medianUnit * smoothingFactor
        unitDuration = max(minUnit, min(maxUnit, unitDuration))
        estimatedWPM = MorseCode.Timing.wpm(fromUnitDuration: unitDuration)
    }
}

// MARK: - Main Test Runner

func runTest(
    wavPath: String, toneFrequency: Double, initialWPM: Int, adaptive: Bool,
    config: ThresholdConfig, configName: String
) {
    print("=".padding(toLength: 60, withPad: "=", startingAt: 0))
    print("CW Decoder Test")
    print("=".padding(toLength: 60, withPad: "=", startingAt: 0))
    print("File: \(wavPath)")
    print("Tone frequency: \(Int(toneFrequency)) Hz")
    print("Initial WPM: \(initialWPM)")
    print("Adaptive WPM: \(adaptive ? "enabled" : "disabled (fixed)")")
    print("Threshold config: \(configName)")
    print("  onThreshold: \(config.onThreshold), offThreshold: \(config.offThreshold)")
    print(
        "  confirmationBlocks: \(config.confirmationBlocks), calibrationBlocks: \(config.calibrationBlocks)"
    )
    print("")

    // Load WAV file
    let url = URL(fileURLWithPath: wavPath)
    let wav: WAVFile
    do {
        wav = try WAVFile.read(from: url)
    } catch {
        print("ERROR: Failed to read WAV file: \(error)")
        return
    }

    print("Sample rate: \(wav.sampleRate) Hz")
    print("Channels: \(wav.channels)")
    print("Bits per sample: \(wav.bitsPerSample)")
    print("Total samples: \(wav.samples.count)")
    print(
        "Duration: \(String(format: "%.2f", Double(wav.samples.count) / Double(wav.sampleRate))) seconds"
    )
    print("")

    // Initialize processor
    let blockSize = 128
    let filter = GoertzelFilter(
        targetFrequency: toneFrequency,
        sampleRate: Double(wav.sampleRate),
        blockSize: blockSize
    )
    var threshold = GoertzelThreshold(config: config)
    let decoder = MorseDecoder(initialWPM: initialWPM, adaptive: adaptive)

    let blockDuration = Double(blockSize) / Double(wav.sampleRate)

    // Apply Hamming window
    var hammingWindow = [Float](repeating: 0, count: blockSize)
    for i in 0 ..< blockSize {
        hammingWindow[i] = Float(
            0.54 - 0.46 * cos(2.0 * Double.pi * Double(i) / Double(blockSize - 1))
        )
    }

    // Process samples
    var decodedText = ""
    var keyEvents: [(isDown: Bool, timestamp: TimeInterval)] = []
    var sampleIndex = 0
    var blockStartTime: TimeInterval = 0

    print("Processing...")
    print("-".padding(toLength: 60, withPad: "-", startingAt: 0))

    while sampleIndex + blockSize <= wav.samples.count {
        let block = Array(wav.samples[sampleIndex ..< sampleIndex + blockSize])

        // Apply window
        var windowedBlock = [Float](repeating: 0, count: blockSize)
        vDSP_vmul(block, 1, hammingWindow, 1, &windowedBlock, 1, vDSP_Length(blockSize))

        // Compute magnitude
        let magnitude = filter.processSamples(windowedBlock)

        // Detect key events
        if let event = threshold.process(
            magnitude: magnitude,
            blockDuration: blockDuration,
            blockStartTime: blockStartTime
        ) {
            keyEvents.append(event)
            let state = event.isDown ? "KEY DOWN" : "KEY UP  "
            let timeMs = String(format: "%.1f", event.timestamp * 1_000)
            let ratio = magnitude / max(threshold.currentNoiseFloor, 0.0001)
            print(
                "[\(timeMs)ms] \(state) mag:\(String(format: "%.4f", magnitude)) ratio:\(String(format: "%.1f", ratio))"
            )

            // Process through morse decoder
            let outputs = decoder.processKeyEvent(
                isKeyDown: event.isDown, timestamp: event.timestamp
            )
            for output in outputs {
                switch output {
                case let .character(c):
                    decodedText += c
                case .wordSpace:
                    decodedText += " "
                case .element:
                    break
                }
            }
        }

        sampleIndex += blockSize
        blockStartTime += blockDuration
    }

    // Check for timeout at end
    let finalOutputs = decoder.checkTimeout(currentTime: blockStartTime + 1.0)
    for output in finalOutputs {
        switch output {
        case let .character(c):
            decodedText += c
        case .wordSpace:
            decodedText += " "
        case .element:
            break
        }
    }

    print("-".padding(toLength: 60, withPad: "-", startingAt: 0))
    print("")
    print("RESULTS")
    print("=".padding(toLength: 60, withPad: "=", startingAt: 0))
    print("Key events detected: \(keyEvents.count)")
    print("Final estimated WPM: \(decoder.getEstimatedWPM())")
    print("")
    print("Decoded text:")
    print("  \"\(decodedText)\"")
    print("")
}

// MARK: - Entry Point

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage: swift test_cw_decoder.swift <wav_file> [tone_frequency] [wpm|adaptive] [config]")
    print("")
    print("Arguments:")
    print("  wav_file       - Path to WAV file (16-bit PCM)")
    print("  tone_frequency - CW tone frequency in Hz (default: 700)")
    print(
        "  wpm|adaptive   - WPM number for fixed timing, or 'adaptive' for auto-detection (default: adaptive)"
    )
    print(
        "  config         - Threshold config: 'default', 'noisy', or 'aggressive' (default: default)"
    )
    print("")
    print("Threshold configs:")
    print("  default    - Balanced settings for clean to light noise")
    print("  noisy      - More aggressive noise rejection (for moderate noise)")
    print("  aggressive - Maximum noise rejection (for heavy noise/QRM)")
    print("")
    print("Examples:")
    print("  swift test_cw_decoder.swift test.wav 700 adaptive")
    print("  swift test_cw_decoder.swift test.wav 700 adaptive noisy")
    print("  swift test_cw_decoder.swift test.wav 700 20 aggressive")
    exit(1)
}

let wavPath = args[1]
let toneFrequency = args.count > 2 ? Double(args[2]) ?? 700.0 : 700.0

// Parse WPM argument: number = fixed WPM, "adaptive" or omitted = adaptive mode
var initialWPM = 20
var adaptive = true

if args.count > 3 {
    let wpmArg = args[3].lowercased()
    if wpmArg == "adaptive" {
        adaptive = true
    } else if let wpm = Int(args[3]) {
        initialWPM = wpm
        adaptive = false
    }
}

// Parse config argument
var config = ThresholdConfig.default
var configName = "default"

if args.count > 4 {
    let configArg = args[4].lowercased()
    switch configArg {
    case "noisy":
        config = ThresholdConfig.noisy
        configName = "noisy"
    case "aggressive":
        config = ThresholdConfig.aggressive
        configName = "aggressive"
    default:
        config = ThresholdConfig.default
        configName = "default"
    }
}

runTest(
    wavPath: wavPath,
    toneFrequency: toneFrequency,
    initialWPM: initialWPM,
    adaptive: adaptive,
    config: config,
    configName: configName
)
