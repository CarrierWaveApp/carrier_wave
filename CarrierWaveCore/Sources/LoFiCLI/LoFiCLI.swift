// swiftlint:disable function_body_length
import CarrierWaveCore
import Foundation
import Security

// MARK: - LoFiCLI

@main
struct LoFiCLI {
    // MARK: Internal

    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        let verbose = args.contains("--verbose") || args.contains("-v")
        args.removeAll { $0 == "--verbose" || $0 == "-v" }

        guard let command = args.first else {
            printUsage()
            exit(1)
        }

        let credentials = FileCredentialStore()
        let logger = ConsoleLogger()
        let client = LoFiClient(credentials: credentials, logger: logger, verbose: verbose)

        do {
            switch command {
            case "register":
                try await handleRegister(args: Array(args.dropFirst()), client: client)
            case "link":
                try await handleLink(args: Array(args.dropFirst()), client: client)
            case "download":
                try await handleDownload(args: Array(args.dropFirst()), client: client)
            case "status":
                handleStatus(client: client)
            case "import-credentials":
                try handleImportCredentials(credentials: credentials)
            case "help",
                 "--help",
                 "-h":
                printUsage()
            default:
                printError("Unknown command: \(command)")
                printUsage()
                exit(1)
            }
        } catch {
            printError(error.localizedDescription)
            exit(1)
        }
    }

    // MARK: - Register

    static func handleRegister(args: [String], client: LoFiClient) async throws {
        var callsign: String?
        var email: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--callsign":
                i += 1
                callsign = args[safe: i]
            case "--email":
                i += 1
                email = args[safe: i]
            default:
                break
            }
            i += 1
        }

        guard let callsign else {
            printError("--callsign is required")
            exit(1)
        }

        printInfo("Configuring LoFi for \(callsign.uppercased())...")
        try client.configure(callsign: callsign, email: email)

        printInfo("Registering with LoFi server...")
        let registration = try await client.register()

        printInfo("Registration successful!")
        printInfo("  Account: \(registration.account.call)")
        printInfo("  Client UUID: \(registration.client.uuid)")
        if let cutoff = registration.account.cutoffDate {
            printInfo("  Cutoff date: \(cutoff)")
        }
        printInfo("  Batch size: \(registration.meta.flags.suggestedSyncBatchSize)")

        // Automatically link device if email was provided
        if let email {
            printInfo("")
            printInfo("Linking device to \(email)...")
            try await client.linkDevice(email: email)
            printInfo("Link email sent. Check your inbox and confirm the link.")
        }
    }

    // MARK: - Link

    static func handleLink(args: [String], client: LoFiClient) async throws {
        var email: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--email":
                i += 1
                email = args[safe: i]
            default:
                break
            }
            i += 1
        }

        guard let email else {
            printError("--email is required")
            exit(1)
        }

        printInfo("Sending device link email to \(email)...")
        try await client.linkDevice(email: email)
        printInfo("Check your email and confirm the link.")
        printInfo("Once confirmed, run: lofi-cli link-confirm")
    }

    // MARK: - Download

    static func handleDownload(args: [String], client: LoFiClient) async throws {
        var fresh = false
        var outputPath: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--fresh":
                fresh = true
            case "--output":
                i += 1
                outputPath = args[safe: i]
            default:
                break
            }
            i += 1
        }

        if fresh {
            printInfo("Fresh download - resetting sync timestamp...")
            client.resetSyncTimestamp()
        }

        printInfo("Downloading QSOs...")
        let startTime = Date()

        let result: LoFiDownloadResult
        if fresh {
            result = try await client.fetchAllQsos()
        } else {
            result = try await client.fetchAllQsosSinceLastSync(
                onProgress: { progress in
                    let pct = progress.totalQSOs > 0
                        ? Int(Double(progress.downloadedQSOs) / Double(progress.totalQSOs) * 100)
                        : 0
                    let msg = "\r  \(progress.downloadedQSOs)/\(progress.totalQSOs) QSOs (\(pct)%), "
                        + "\(progress.processedOperations)/\(progress.totalOperations) operations"
                    FileHandle.standardError.write(Data(msg.utf8))
                }
            )
            FileHandle.standardError.write(Data("\n".utf8))
        }

        let qsos = result.qsos
        let elapsed = Date().timeIntervalSince(startTime)

        // Group by operation for summary
        var opCounts: [String: Int] = [:]
        for (_, op) in qsos {
            opCounts[op.uuid, default: 0] += 1
        }

        printInfo("Download complete in \(String(format: "%.1f", elapsed))s")
        printInfo("  Operations: \(opCounts.count)")
        printInfo("  QSOs: \(qsos.count)")

        // Three-step pipeline breakdown
        printPipelineBreakdown(result: result)

        // Date range
        let timestamps = qsos.compactMap(\.0.startAtMillis)
        if let minTs = timestamps.min(), let maxTs = timestamps.max() {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            let minDate = Date(timeIntervalSince1970: minTs / 1_000.0)
            let maxDate = Date(timeIntervalSince1970: maxTs / 1_000.0)
            printInfo("  Date range: \(fmt.string(from: minDate)) to \(fmt.string(from: maxDate))")
        }

        // Write JSON output if requested
        if let outputPath {
            printInfo("Writing QSOs to \(outputPath)...")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let output = qsos.map { qso, op in
                DownloadedQSO(
                    uuid: qso.uuid,
                    operationUUID: op.uuid,
                    operationTitle: op.title,
                    stationCall: op.stationCall,
                    theirCall: qso.their?.call,
                    band: qso.band,
                    mode: qso.mode,
                    freqKHz: qso.freq,
                    startAtMillis: qso.startAtMillis,
                    rstSent: qso.our?.sent,
                    rstRcvd: qso.their?.sent,
                    theirGrid: qso.their?.guess?.grid,
                    theirName: qso.their?.guess?.name,
                    notes: qso.notes,
                    deleted: qso.deleted
                )
            }

            let data = try encoder.encode(output)
            try data.write(to: URL(fileURLWithPath: outputPath))
            printInfo("Wrote \(output.count) QSOs to \(outputPath)")
        }
    }

    // MARK: - Status

    static func handleStatus(client: LoFiClient) {
        printInfo("LoFi CLI Status")
        printInfo("  Configured: \(client.isConfigured)")
        printInfo("  Linked: \(client.isLinked)")
        printInfo("  Has token: \(client.hasToken)")
        printInfo("  Callsign: \(client.getCallsign() ?? "not set")")
        printInfo("  Email: \(client.getEmail() ?? "not set")")

        let lastSync = client.getLastSyncMillis()
        if lastSync > 0 {
            let date = Date(timeIntervalSince1970: Double(lastSync) / 1_000.0)
            let fmt = ISO8601DateFormatter()
            printInfo("  Last sync: \(fmt.string(from: date))")
        } else {
            printInfo("  Last sync: never")
        }

        let flags = client.getSyncFlags()
        printInfo("  Sync batch size: \(flags.suggestedSyncBatchSize)")
        printInfo("  Sync loop delay: \(flags.suggestedSyncLoopDelay)ms")
    }

    // MARK: - Import Credentials

    static func handleImportCredentials(credentials: FileCredentialStore) throws {
        let service = "com.fullduplex.credentials"

        printInfo("Importing LoFi credentials from iOS app Keychain...")
        printInfo("  Keychain service: \(service)")

        var imported = 0
        for key in LoFiCredentialKey.allCases {
            if let value = readKeychainValue(service: service, account: key.rawValue) {
                try credentials.setString(value, for: key)
                let display = key == .authToken || key == .clientSecret
                    ? "\(value.prefix(8))..."
                    : value
                printInfo("  \(key.rawValue) = \(display)")
                imported += 1
            }
        }

        if imported == 0 {
            printError("No LoFi credentials found in Keychain.")
            printError("Make sure you've configured LoFi in the Carrier Wave app first.")
            exit(1)
        }

        printInfo("Imported \(imported) credentials.")
        printInfo("Run 'lofi-cli status' to verify, then 'lofi-cli download --fresh' to test.")
    }

    // MARK: - Helpers

    static func printUsage() {
        let usage = """
        Usage: lofi-cli [--verbose|-v] <command> [options]

        Global options:
          --verbose, -v        Show all HTTP requests, responses, and headers

        Commands:
          register             Register a NEW client with LoFi
            --callsign <CALL>    Your callsign (required)
            --email <EMAIL>      Your email (auto-links device if provided)

          import-credentials   Import existing credentials from iOS app Keychain
                               (avoids cutoff date restrictions from new registration)

          link                 Link device via email
            --email <EMAIL>      Email to send link to (required)

          download             Download QSOs
            --fresh              Reset sync timestamp and download all
            --output <PATH>      Write QSOs to JSON file

          status               Show current credential state

          help                 Show this help message

        Credentials are stored in ~/.config/lofi-cli/credentials.json
        """
        print(usage)
    }

    static func printInfo(_ message: String) {
        print(message)
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    }

    // MARK: Private

    private static func readKeychainValue(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return string
    }
}

// MARK: - DownloadedQSO

/// Simplified QSO representation for JSON output
struct DownloadedQSO: Encodable {
    let uuid: String
    let operationUUID: String
    let operationTitle: String?
    let stationCall: String
    let theirCall: String?
    let band: String?
    let mode: String?
    let freqKHz: Double?
    let startAtMillis: Double?
    let rstSent: String?
    let rstRcvd: String?
    let theirGrid: String?
    let theirName: String?
    let notes: String?
    let deleted: Int?
}

// MARK: - Array extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// swiftlint:enable function_body_length
