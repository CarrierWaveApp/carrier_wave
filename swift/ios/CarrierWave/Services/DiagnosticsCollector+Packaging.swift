import Foundation
import ZIPFoundation

// MARK: - DiagnosticsCollector.ManifestInput

extension DiagnosticsCollector {
    struct ManifestInput {
        let reportId: UUID
        let snapshot: MainActorSnapshot
        let options: CollectionOptions
        let artifacts: [DiagnosticArtifact]
        let failures: [String]
        let durationSeconds: TimeInterval
    }
}

// MARK: - Snapshot Artifacts

extension DiagnosticsCollector {
    func buildSnapshotArtifacts(
        from snapshot: MainActorSnapshot
    ) -> [DiagnosticArtifact] {
        var artifacts: [DiagnosticArtifact] = []

        if let data = try? JSONEncoder.iso8601
            .encode(snapshot.syncState)
        {
            artifacts.append(DiagnosticArtifact(
                filename: "sync-state.json",
                data: data,
                collectionMs: 0
            ))
        }

        if let data = snapshot.uploadDiagnostics {
            artifacts.append(DiagnosticArtifact(
                filename: "upload-diagnostics.json",
                data: data,
                collectionMs: 0
            ))
        }

        return artifacts
    }
}

// MARK: - Manifest Builder

extension DiagnosticsCollector {
    func buildManifest(
        _ input: ManifestInput
    ) -> DiagnosticArtifact {
        var manifest = buildManifestCore(input)
        appendManifestExtras(
            &manifest, input: input
        )

        let data = (try? JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()

        return DiagnosticArtifact(
            filename: "manifest.json", data: data,
            collectionMs: 0
        )
    }

    private func buildManifestCore(
        _ input: ManifestInput
    ) -> [String: Any] {
        var manifest: [String: Any] = [
            "reportVersion": 1,
            "reportId": input.reportId.uuidString,
            "collectedAt": ISO8601DateFormatter()
                .string(from: Date()),
            "collectionDurationSeconds": round(
                input.durationSeconds * 100
            ) / 100,
            "appVersion": input.snapshot.deviceInfo.appVersion,
            "buildNumber": input.snapshot.deviceInfo.buildNumber,
            "iosVersion": input.snapshot.deviceInfo.iosVersion,
            "deviceModel": input.snapshot.deviceInfo.deviceModel,
            "debugMode": input.snapshot.deviceInfo.debugMode,
        ]

        let callsignInfo = input.snapshot.callsignInfo
        if let callsign = callsignInfo.currentCallsign {
            manifest["userCallsign"] = callsign
        }
        if !callsignInfo.previousCallsigns.isEmpty {
            manifest["previousCallsigns"] = callsignInfo.previousCallsigns
        }
        if let desc = input.options.userDescription,
           !desc.isEmpty
        {
            manifest["userDescription"] = desc
        }

        return manifest
    }

    private func appendManifestExtras(
        _ manifest: inout [String: Any],
        input: ManifestInput
    ) {
        let svcStatus = input.snapshot.serviceStatus
        manifest["services"] = [
            "qrz": svcStatus.qrzConfigured
                ? "configured" : "not_configured",
            "pota": svcStatus.potaConfigured
                ? "configured" : "not_configured",
            "lofi": svcStatus.lofiConfigured
                ? "configured" : "not_configured",
            "lotw": svcStatus.lotwConfigured
                ? "configured" : "not_configured",
            "hamrs": svcStatus.hamrsConfigured
                ? "configured" : "not_configured",
            "icloud": svcStatus.iCloudStatus,
        ] as [String: Any]

        manifest["files"] = input.artifacts.map { artifact in
            [
                "name": artifact.filename,
                "status": "collected",
                "sizeBytes": artifact.data.count,
                "collectionMs": artifact.collectionMs,
            ] as [String: Any]
        }

        if !input.failures.isEmpty {
            manifest["collectionErrors"] = input.failures
        }

        manifest["privacyNotice"] =
            "This report contains callsigns (public amateur "
                + "radio identifiers) and app activity logs. "
                + "No passwords, API keys, or authentication "
                + "tokens are included."
    }
}

// MARK: - Zip Assembly

extension DiagnosticsCollector {
    func assembleZip(
        artifacts: [DiagnosticArtifact],
        timestamp: Date
    ) throws -> URL {
        cleanPreviousDiagnosticZips()

        let tempDir = FileManager.default.temporaryDirectory
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename =
            "carrier-wave-diagnostics-"
                + "\(fmt.string(from: timestamp)).zip"
        let zipURL = tempDir.appendingPathComponent(filename)
        let tempURL = tempDir.appendingPathComponent(
            "\(UUID().uuidString).zip.tmp"
        )

        let archive = try Archive(
            url: tempURL, accessMode: .create
        )

        for artifact in artifacts {
            try archive.addEntry(
                with: artifact.filename,
                type: .file,
                uncompressedSize: Int64(artifact.data.count),
                provider: { position, size in
                    artifact.data.subdata(
                        in: Int(position) ..< Int(position)
                            + size
                    )
                }
            )
        }

        try FileManager.default.moveItem(
            at: tempURL, to: zipURL
        )
        return zipURL
    }

    private func cleanPreviousDiagnosticZips() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default
            .contentsOfDirectory(atPath: tempDir.path)
        else {
            return
        }

        for file in contents
            where file.hasPrefix("carrier-wave-diagnostics-")
        {
            try? FileManager.default.removeItem(
                at: tempDir.appendingPathComponent(file)
            )
        }
    }
}
