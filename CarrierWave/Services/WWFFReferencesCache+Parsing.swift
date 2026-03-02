// WWFF References Cache - Parsing
//
// CSV parsing, name index building, and utility functions
// for the WWFF references cache.
//
// CSV columns (26): reference[0], status[1], name[2], program[3],
// dxcc[4], state[5], county[6], continent[7], iota[8],
// iaruLocator[9], latitude[10], longitude[11], IUCNcat[12],
// validFrom[13], validTo[14], notes[15], lastMod[16],
// changeLog[17], reviewFlag[18], specialFlags[19], website[20],
// country[21], region[22], dxccEnum[23], qsoCount[24], lastAct[25]

import Foundation

extension WWFFReferencesCache {
    /// Parse the WWFF directory CSV into reference objects
    func parseCSV(_ csv: String) -> [String: WWFFReference] {
        var result: [String: WWFFReference] = [:]

        for line in csv.components(separatedBy: .newlines).dropFirst() {
            guard !line.isEmpty else {
                continue
            }
            let fields = parseCSVLine(line)
            guard fields.count >= 12 else {
                continue
            }

            let reference = fields[0].uppercased()
            let name = fields[2]
            guard !reference.isEmpty, !name.isEmpty else {
                continue
            }

            let status = fields[1].lowercased()

            let grid = cleanField(fields[safe: 9])
            let iota = cleanField(fields[safe: 8])
            let continent = cleanField(fields[safe: 7])
            let country = cleanField(fields[safe: 21])
            let region = cleanField(fields[safe: 22])
            let iucnCat = cleanField(fields[safe: 12])
            let dxccEnum = fields[safe: 23].flatMap { Int($0) }

            let ref = WWFFReference(
                reference: reference,
                name: name,
                program: fields[3],
                status: status,
                continent: continent,
                iota: iota,
                grid: grid,
                latitude: Double(fields[10]),
                longitude: Double(fields[11]),
                iucnCategory: iucnCat,
                country: country,
                region: region,
                dxccEntity: dxccEnum
            )
            result[reference] = ref
        }
        return result
    }

    /// Build the name index for full-text search
    func buildNameIndex() {
        var index: [String: [String]] = [:]

        for (code, ref) in references {
            // Index reference name words
            let nameWords = ref.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }

            // Index code parts (e.g., "kff", "1234" from "KFF-1234")
            let codeWords = code.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            // Index country words
            let countryWords = (ref.country ?? "").lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }

            for word in nameWords + codeWords + countryWords {
                if index[word] == nil {
                    index[word] = [code]
                } else {
                    index[word]?.append(code)
                }
            }
        }

        nameIndex = index
    }

    /// Parse a CSV line handling quoted fields
    func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == ",", !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))

        return fields
    }

    /// Calculate distance between two coordinates using Haversine formula
    nonisolated func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let haversineLat = sin(dLat / 2) * sin(dLat / 2)
        let haversineLon = sin(dLon / 2) * sin(dLon / 2)
            * cos(lat1Rad) * cos(lat2Rad)
        let centralAngle =
            2 * atan2(
                sqrt(haversineLat + haversineLon),
                sqrt(1 - haversineLat - haversineLon)
            )
        return earthRadiusKm * centralAngle
    }

    // MARK: - Private Helpers

    /// Clean a field value, returning nil for empty or dash-only values
    private func cleanField(_ value: String?) -> String? {
        guard let trimmed = value?
            .trimmingCharacters(in: .whitespaces),
            !trimmed.isEmpty, trimmed != "-"
        else {
            return nil
        }
        return trimmed
    }
}

// MARK: - Array safe subscript

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
