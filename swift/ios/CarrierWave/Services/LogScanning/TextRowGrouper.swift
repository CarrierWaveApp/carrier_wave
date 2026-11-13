import Foundation
import Vision

// MARK: - OCRTextBlock

/// A single recognized text block from Vision OCR with its position and confidence.
struct OCRTextBlock {
    let text: String
    let confidence: Float
    /// Normalized bounding box (Vision coordinates: origin at bottom-left)
    let boundingBox: CGRect
}

// MARK: - OCRTextRow

/// A row of text reconstructed from spatially-grouped OCR blocks.
struct OCRTextRow {
    let text: String
    /// Minimum confidence across all blocks in this row
    let minConfidence: Float
    /// Average confidence across all blocks in this row
    let averageConfidence: Float
    /// Union bounding box of all blocks in this row (normalized Vision coordinates)
    let boundingBox: CGRect
}

// MARK: - TextRowGrouper

/// Groups `VNRecognizedTextObservation` results into rows by Y-coordinate clustering.
///
/// Vision OCR returns individual text blocks, not rows. This groups observations
/// whose vertical centers are within a threshold, then joins them left-to-right
/// to reconstruct each line of the original document.
enum TextRowGrouper {
    // MARK: Internal

    /// Group observations into rows, optionally stripping a detected header row.
    /// - Parameters:
    ///   - observations: Vision text observations from a single page
    ///   - yThreshold: Maximum normalized Y distance between block centers to be
    ///     considered the same row. Defaults to 5% of image height.
    ///   - stripHeader: Whether to detect and remove a header row
    /// - Returns: Array of text rows, top to bottom
    static func groupIntoRows(
        _ observations: [VNRecognizedTextObservation],
        yThreshold: CGFloat = 0.05,
        stripHeader: Bool = true
    ) -> [OCRTextRow] {
        let blocks = observations.compactMap { observation -> OCRTextBlock? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            return OCRTextBlock(
                text: normalizeOCRText(candidate.string),
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }

        guard !blocks.isEmpty else {
            return []
        }

        // Sort by Y descending (Vision origin is bottom-left, so top of page = highest Y)
        let sorted = blocks.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        // Cluster by Y proximity
        var rows: [[OCRTextBlock]] = []
        var currentRow: [OCRTextBlock] = [sorted[0]]
        var currentY = sorted[0].boundingBox.midY

        for block in sorted.dropFirst() {
            if abs(block.boundingBox.midY - currentY) <= yThreshold {
                currentRow.append(block)
            } else {
                rows.append(currentRow)
                currentRow = [block]
                currentY = block.boundingBox.midY
            }
        }
        rows.append(currentRow)

        // Sort blocks within each row left-to-right
        var textRows = rows.map { row -> OCRTextRow in
            let leftToRight = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let text = leftToRight.map(\.text).joined(separator: " ")
            let confidences = leftToRight.map(\.confidence)
            let minConf = confidences.min() ?? 0
            let avgConf = confidences.reduce(0, +) / Float(confidences.count)
            let unionBox = leftToRight.dropFirst().reduce(into: leftToRight[0].boundingBox) { union, block in
                union = union.union(block.boundingBox)
            }
            return OCRTextRow(
                text: text, minConfidence: minConf,
                averageConfidence: avgConf, boundingBox: unionBox
            )
        }

        if stripHeader, !textRows.isEmpty, isHeaderRow(textRows[0].text) {
            textRows.removeFirst()
        }

        return textRows
    }

    // MARK: Private

    // MARK: - OCR Text Normalization

    /// Characters that Vision OCR commonly confuses with ASCII equivalents
    /// when scanning handwritten amateur radio logs. Slashed Z is frequently
    /// recognized as Ukrainian Hryvnia (₴), Cyrillic lookalikes replace Latin
    /// letters, and digit/letter swaps are common in callsign contexts.
    private static let ocrSubstitutions: [Character: Character] = [
        // Slashed Z → Z (Hryvnia sign)
        "₴": "Z",
        // Cyrillic lookalikes → Latin
        "\u{0410}": "A", // А → A
        "\u{0412}": "B", // В → B
        "\u{0421}": "C", // С → C
        "\u{0415}": "E", // Е → E
        "\u{041D}": "H", // Н → H
        "\u{0406}": "I", // І → I
        "\u{041A}": "K", // К → K
        "\u{041C}": "M", // М → M
        "\u{041E}": "O", // О → O
        "\u{0420}": "P", // Р → P
        "\u{0422}": "T", // Т → T
        "\u{0425}": "X", // Х → X
        "\u{0430}": "A", // а → A (lowercase Cyrillic)
        "\u{0435}": "E", // е → E
        "\u{043E}": "O", // о → O
        "\u{0440}": "P", // р → P
        "\u{0441}": "C", // с → C
        "\u{0445}": "X", // х → X
        // Common digit/letter swaps in callsign context
        "\u{2070}": "0", // ⁰ (superscript zero)
        "\u{00B9}": "1", // ¹ (superscript one)
        "\u{00B2}": "2", // ² (superscript two)
        "\u{00B3}": "3", // ³ (superscript three)
    ]

    private static let headerKeywords: Set<String> = [
        "DATE", "TIME", "CALL", "CALLSIGN", "FREQ", "FREQUENCY",
        "MODE", "RST", "BAND", "REMARKS", "NOTES", "SENT", "RCVD",
        "NAME", "QTH", "SIG", "SIGNAL", "RPT", "REPORT",
    ]

    /// Replace known OCR-confusable characters with their ASCII equivalents.
    private static func normalizeOCRText(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            if let replacement = ocrSubstitutions[char] {
                result.append(replacement)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// A row is considered a header if 3+ of its tokens match known header keywords.
    private static func isHeaderRow(_ text: String) -> Bool {
        let tokens = text.uppercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        let matches = tokens.filter { headerKeywords.contains($0) }.count
        return matches >= 3
    }
}
