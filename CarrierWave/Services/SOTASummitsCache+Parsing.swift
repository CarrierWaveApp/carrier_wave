// SOTA Summits Cache - Parsing
//
// CSV parsing, name index building, and utility functions
// for the SOTA summits cache.

import CarrierWaveData
import Foundation

extension SOTASummitsCache {
    /// Parse the SOTA summitslist.csv into summit objects
    /// CSV columns (17): SummitCode[0], AssociationName[1], RegionName[2],
    /// SummitName[3], AltM[4], AltFt[5], GridRef1[6], GridRef2[7],
    /// Longitude[8], Latitude[9], Points[10], BonusPoints[11],
    /// ValidFrom[12], ValidTo[13], ActivationCount[14],
    /// ActivationDate[15], ActivationCall[16]
    func parseCSV(_ csv: String) -> [String: SOTASummit] {
        let today = todayString()
        var result: [String: SOTASummit] = [:]

        for line in csv.components(separatedBy: .newlines).dropFirst() {
            guard !line.isEmpty else {
                continue
            }
            let fields = parseCSVLine(line)
            guard fields.count >= 15 else {
                continue
            }

            let code = fields[0].uppercased()
            let name = fields[3]
            guard !code.isEmpty, !name.isEmpty else {
                continue
            }

            // Filter out expired summits (ValidTo < today)
            let validTo = fields[13]
            if !validTo.isEmpty, validTo < today {
                continue
            }

            let grid = gridFromFields(fields[6], fields[7])

            let summit = SOTASummit(
                code: code,
                name: name,
                associationName: fields[1],
                regionName: fields[2],
                altitudeM: Int(fields[4]) ?? 0,
                altitudeFt: Int(fields[5]) ?? 0,
                latitude: Double(fields[9]),
                longitude: Double(fields[8]),
                points: Int(fields[10]) ?? 0,
                bonusPoints: Int(fields[11]) ?? 0,
                activationCount: Int(fields[14]) ?? 0,
                grid: grid
            )
            result[code] = summit
        }
        return result
    }

    /// Build the name index for full-text search
    /// Maps lowercase words to arrays of summit codes.
    /// Indexes summit name words and code segments (association, region).
    func buildNameIndex() {
        var index: [String: [String]] = [:]

        for (code, summit) in summits {
            // Index summit name words
            let nameWords = summit.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }

            // Index code parts (e.g., "w4c", "cm", "001" from "W4C/CM-001")
            let codeWords = code.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            for word in nameWords + codeWords {
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

    /// Convert SOTA grid references to a Maidenhead grid if possible
    func gridFromFields(_ gridRef1: String, _ gridRef2: String) -> String? {
        // SOTA provides OS/Irish grid refs, not Maidenhead.
        // We use lat/lon for distance calculations instead.
        // If a Maidenhead grid is embedded in gridRef2, use it.
        let ref = gridRef2.isEmpty ? gridRef1 : gridRef2
        guard !ref.isEmpty else {
            return nil
        }
        // Basic Maidenhead check: 2 letters + 2 digits (+ optional 2 letters)
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 4,
           trimmed.prefix(2).allSatisfy(\.isLetter),
           trimmed.dropFirst(2).prefix(2).allSatisfy(\.isNumber)
        {
            return trimmed
        }
        return nil
    }

    /// Today's date as "dd/MM/yyyy" matching SOTA CSV date format
    func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
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
        let haversineLon = sin(dLon / 2) * sin(dLon / 2) * cos(lat1Rad) * cos(lat2Rad)
        let centralAngle =
            2 * atan2(
                sqrt(haversineLat + haversineLon),
                sqrt(1 - haversineLat - haversineLon)
            )
        return earthRadiusKm * centralAngle
    }
}
