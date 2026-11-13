// WWFF References Cache - Name Index
//
// Name index building for the WWFF references cache full-text search.
// Directory download, CSV parsing, and storage live in the Rust core
// (`ReferenceDataApi`).

import Foundation

extension WWFFReferencesCache {
    /// Build the name index for full-text search
    func buildNameIndex() {
        var index: [String: [String]] = [:]
        let snapshot = referencesSnapshot()

        for (code, ref) in snapshot {
            let nameWords = ref.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }

            let codeWords = code.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            let countryWords = (ref.country ?? "").lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }

            for word in nameWords + codeWords + countryWords {
                index[word, default: []].append(code)
            }
        }

        let built = index
            .map { (word: $0.key, codes: $0.value) }
            .sorted { $0.word < $1.word }
        storeNameIndex(built)
    }
}
