// swiftlint:disable file_length type_body_length
import Foundation

// MARK: - SQLFormatter

/// SQL pretty-printer for the workbench's Format button. Walks a
/// tokenized stream with a paren-context stack so subqueries,
/// function calls, and CASE expressions all indent properly.
///
/// Not a full sqlfluff — no rule-based linting, no dialect lookup
/// tables, no expression-tree reflow. But the output is stable
/// across re-runs (idempotent) and handles the common shapes a CW
/// Sweep user actually writes: SELECT lists, WHERE/HAVING with
/// AND/OR chains, JOIN ... ON predicates, UNION, CTEs, subqueries
/// in FROM/IN/EXISTS, and CASE expressions.
enum SQLFormatter {
    // MARK: Internal

    static func format(_ sql: String) -> String {
        let tokens = Self.tokenize(sql)
            .filter {
                if case .whitespace = $0 {
                    return false
                }
                return true
            }
        var emitter = Emitter(tokens: tokens)
        emitter.run()
        return emitter.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Fileprivate

    // MARK: - Tokens

    fileprivate enum Token: Equatable {
        case word(String) // identifier or keyword
        case symbol(String) // ( ) , ; * + etc
        case stringLiteral(String) // 'foo' / "foo" / `foo`
        case comment(String) // -- … or /* … */
        case whitespace(String)
    }

    // MARK: - Emitter

    /// Walks the token stream maintaining a stack of `Frame`s, one per
    /// open paren (plus the implicit top-level frame). Each frame
    /// carries the indent level its body should sit at and the
    /// emitter mode that controls how commas and AND/OR are broken.
    fileprivate struct Emitter {
        // MARK: Lifecycle

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        // MARK: Internal

        /// What the *body* of an open frame represents — controls
        /// how commas / AND / OR are broken.
        enum FrameMode {
            case top
            /// Body of a SELECT list (or UPDATE SET list) — break commas.
            case selectList
            /// FROM / JOIN ... — break commas, but ON conditions get
            /// nested.
            case fromList
            /// WHERE / HAVING / ON predicate — break top-level AND/OR.
            case condition
            /// GROUP BY / ORDER BY / VALUES item list — break commas.
            case itemList
            /// (...) opened directly after an identifier (function
            /// call) — keep inline; commas don't break.
            case functionCall
            /// (SELECT ...) subquery or generic expression list —
            /// commas break, indent +1 from the open paren.
            case subquery
            /// (a, b, c) generic parenthesized list when not a
            /// function call — break commas.
            case parenList
            /// Inside CASE — WHEN / THEN / ELSE / END break.
            case caseExpression
        }

        struct Frame {
            var indent: Int
            var mode: FrameMode

            /// Indent at which broken items inside this frame sit
            /// (typically `indent + 1`, but commas inside SELECT
            /// stay at indent so they line up under the keyword).
            var itemIndent: Int {
                indent + 1
            }
        }

        private(set) var output = ""

        mutating func run() {
            while index < tokens.count {
                step()
            }
        }

        // MARK: Private

        /// Clauses whose body is a series of items (column / table /
        /// predicate) — each item gets its own line at the body
        /// indent. Includes FROM, WHERE, HAVING so even a single
        /// argument breaks to a new line, which keeps the visual
        /// rhythm consistent across all major clauses.
        private static let listStyleClauses: Set<String> = [
            "SELECT", "FROM", "WHERE", "HAVING",
            "GROUP BY", "ORDER BY", "VALUES", "RETURNING", "WITH",
        ]

        private let tokens: [Token]
        private var stack: [Frame] = [Frame(indent: 0, mode: .top)]
        private var index = 0
        /// True when the next emit should be at the start of a new
        /// line — i.e. the previous append was a newline + indent.
        private var atLineStart = true
        /// Set when the last emitted token was an open paren so we
        /// can avoid putting a space between `foo(` and the next
        /// argument.
        private var stickToPrev = false

        // MARK: - Helpers

        private var currentIndent: Int {
            stack.last?.indent ?? 0
        }

        // MARK: - Step

        private mutating func step() {
            let token = tokens[index]
            switch token {
            case let .word(text):
                handleWord(text)
            case let .symbol(text):
                handleSymbol(text)
            case let .stringLiteral(text):
                emitInline(text)
                index += 1
            case let .comment(text):
                if !atLineStart {
                    if !output.hasSuffix(" ") {
                        output.append(" ")
                    }
                }
                output.append(text)
                atLineStart = false
                stickToPrev = false
                index += 1
            case .whitespace:
                index += 1
            }
        }

        // MARK: - Word handling

        private mutating func handleWord(_ word: String) {
            let upper = word.uppercased()

            // Try multi-word major clause / JOIN first.
            if let clause = matchClause(startingAt: index) {
                emitClause(clause.text, consumed: clause.consumed)
                return
            }

            // Top-of-frame keywords that flip frame mode.
            if let nestedFrame = frameModeForClause(upper) {
                applyClauseFrameMode(nestedFrame)
            }

            // CASE / WHEN / THEN / ELSE / END
            if upper == "CASE" {
                emitInline(word)
                stack.append(Frame(indent: currentIndent, mode: .caseExpression))
                index += 1
                return
            }
            if upper == "END",
               let frame = stack.last,
               frame.mode == .caseExpression
            {
                emitOnNewLine(at: frame.indent, text: word)
                stack.removeLast()
                index += 1
                return
            }
            if let frame = stack.last,
               frame.mode == .caseExpression,
               ["WHEN", "ELSE"].contains(upper)
            {
                emitOnNewLine(at: frame.itemIndent, text: word)
                index += 1
                return
            }
            if upper == "THEN",
               let frame = stack.last,
               frame.mode == .caseExpression
            {
                emitInline(word)
                index += 1
                return
            }

            // Top-level AND / OR inside a condition frame breaks.
            if upper == "AND" || upper == "OR",
               let frame = stack.last,
               frame.mode == .condition
            {
                emitOnNewLine(at: frame.itemIndent, text: word)
                index += 1
                return
            }

            emitInline(word)
            index += 1
        }

        /// Multi-word clause heads (GROUP BY / ORDER BY / UNION ALL /
        /// LEFT JOIN / etc.) get matched up front so they emit as a
        /// single "clause" rather than as separate words.
        private func matchClause(startingAt idx: Int) -> (text: String, consumed: Int)? {
            guard idx < tokens.count, case let .word(first) = tokens[idx] else {
                return nil
            }
            let firstUp = first.uppercased()

            // Try 3-word JOIN heads (LEFT OUTER JOIN, etc.).
            if let two = peekWord(after: idx),
               let three = peekWord(after: two.indexAfter)
            {
                let tri = "\(firstUp) \(two.text) \(three.text)"
                if SQLFormatter.joinClauses.contains(tri) {
                    return (tri, three.indexAfter - idx)
                }
            }
            // 2-word combos (GROUP BY, INNER JOIN, UNION ALL).
            if let two = peekWord(after: idx) {
                let combined = "\(firstUp) \(two.text)"
                if SQLFormatter.majorClauses.contains(combined)
                    || SQLFormatter.joinClauses.contains(combined)
                {
                    return (combined, two.indexAfter - idx)
                }
            }
            // 1-word major clause / bare JOIN.
            if SQLFormatter.majorClauses.contains(firstUp) || firstUp == "JOIN" {
                return (firstUp, 1)
            }
            return nil
        }

        private func peekWord(after idx: Int) -> (text: String, indexAfter: Int)? {
            var cursor = idx + 1
            while cursor < tokens.count {
                if case let .word(text) = tokens[cursor] {
                    return (text.uppercased(), cursor + 1)
                }
                if case .comment = tokens[cursor] {
                    cursor += 1
                    continue
                }
                return nil
            }
            return nil
        }

        // MARK: - Clause emission

        /// Major clauses (and JOINs) start on their own line at the
        /// frame's base indent. After emitting, the frame's mode
        /// shifts to the body kind (selectList for SELECT, condition
        /// for WHERE, etc.) so subsequent commas / AND / OR break
        /// correctly. List-style clauses (SELECT / GROUP BY / ORDER
        /// BY / VALUES / RETURNING) also break a newline immediately
        /// after the keyword so each item lands on its own line at
        /// the body indent.
        private mutating func emitClause(_ text: String, consumed: Int) {
            guard let frame = stack.last else {
                return
            }
            let upper = text.uppercased()

            // JOINs sit at the surrounding frame's item indent so
            // they nest one level under FROM, matching sqlfluff's
            // "indented_joins" style:
            //   FROM
            //       table1
            //       LEFT JOIN table2 ON …
            let emitAt = isJoinClause(upper) ? frame.itemIndent : frame.indent
            emitOnNewLine(at: emitAt, text: text)
            index += consumed

            if let mode = frameModeForClause(upper) {
                applyClauseFrameMode(mode)
            }

            if Self.listStyleClauses.contains(upper),
               let updated = stack.last
            {
                output.append("\n")
                output.append(indentString(updated.itemIndent))
                atLineStart = true
                stickToPrev = false
            }
        }

        private func isJoinClause(_ upper: String) -> Bool {
            upper == "JOIN" || SQLFormatter.joinClauses.contains(upper)
        }

        private mutating func applyClauseFrameMode(_ mode: FrameMode) {
            guard !stack.isEmpty else {
                return
            }
            stack[stack.count - 1].mode = mode
        }

        /// Body mode each clause keyword puts the surrounding frame
        /// into so subsequent items break the right way.
        private func frameModeForClause(_ upper: String) -> FrameMode? {
            switch upper {
            case "SELECT": .selectList
            case "FROM": .fromList
            case "WHERE",
                 "HAVING",
                 "ON": .condition
            case "GROUP BY",
                 "ORDER BY",
                 "BY",
                 "VALUES",
                 "RETURNING": .itemList
            default: nil
            }
        }

        // MARK: - Symbol handling

        private mutating func handleSymbol(_ symbol: String) {
            switch symbol {
            case "(":
                handleOpenParen()
            case ")":
                handleCloseParen()
            case ",":
                handleComma()
            case ";":
                if output.hasSuffix(" ") {
                    output.removeLast()
                }
                output.append(";")
                output.append("\n")
                atLineStart = true
                stickToPrev = false
                index += 1
            default:
                emitInline(symbol)
                index += 1
            }
        }

        private mutating func handleOpenParen() {
            // Subquery detection runs FIRST. `WHERE x IN (SELECT …)` /
            // `WHERE EXISTS (SELECT …)` / `FROM (SELECT …)` should
            // always indent — even though `IN` / `EXISTS` look like
            // identifier-suffix tokens to a character-level check.
            let isSubquery = nextWordIsClauseStart()
            let isFunctionCall = !isSubquery && previousNonWhitespaceIsIdentifier()

            output.append("(")
            atLineStart = false
            stickToPrev = true
            index += 1

            if isFunctionCall {
                stack.append(Frame(indent: currentIndent, mode: .functionCall))
                return
            }

            let newIndent = currentIndent + 1
            if isSubquery {
                // Don't pre-emit a newline — the inner clause's
                // emitClause will newline + indent itself, and adding
                // one here would leave a blank line between `(` and
                // `SELECT`.
                stack.append(Frame(indent: newIndent, mode: .subquery))
            } else {
                stack.append(Frame(indent: newIndent, mode: .parenList))
            }
        }

        private mutating func handleCloseParen() {
            let popped = stack.popLast()
            // Subqueries close on a dedented new line for readability.
            if popped?.mode == .subquery {
                if let frame = stack.last {
                    output.append("\n")
                    output.append(indentString(frame.indent))
                    atLineStart = true
                }
            }
            if output.hasSuffix(" ") {
                output.removeLast()
            }
            output.append(")")
            atLineStart = false
            stickToPrev = false
            index += 1
        }

        private mutating func handleComma() {
            if output.hasSuffix(" ") {
                output.removeLast()
            }
            output.append(",")
            switch stack.last?.mode {
            case .functionCall,
                 .none,
                 .top:
                output.append(" ")
                atLineStart = false
            default:
                if let frame = stack.last {
                    output.append("\n")
                    output.append(indentString(frame.itemIndent))
                    atLineStart = true
                }
            }
            stickToPrev = false
            index += 1
        }

        private func indentString(_ level: Int) -> String {
            String(repeating: "    ", count: max(0, level))
        }

        private mutating func emitInline(_ text: String) {
            if atLineStart {
                output.append(text)
            } else if stickToPrev {
                output.append(text)
            } else {
                if !output.hasSuffix(" "), !output.isEmpty {
                    output.append(" ")
                }
                output.append(text)
            }
            atLineStart = false
            stickToPrev = false
        }

        private mutating func emitOnNewLine(at level: Int, text: String) {
            // Trim trailing whitespace from the current line so we
            // don't leave dangling spaces before a break.
            while output.last == " " {
                output.removeLast()
            }
            if !output.isEmpty {
                output.append("\n")
            }
            output.append(indentString(level))
            output.append(text)
            atLineStart = false
            stickToPrev = false
        }

        private func previousNonWhitespaceIsIdentifier() -> Bool {
            guard let last = output.last else {
                return false
            }
            return last.isLetter || last.isNumber || last == "_" || last == "."
        }

        private func nextWordIsClauseStart() -> Bool {
            // Start *past* the current token — `index` still points
            // at the `(` we're handling, so reading from `index`
            // would immediately trip the default branch and return
            // false, misclassifying every subquery as a paren list.
            var cursor = index + 1
            while cursor < tokens.count {
                switch tokens[cursor] {
                case let .word(text):
                    let upper = text.uppercased()
                    return upper == "SELECT" || upper == "WITH" || upper == "VALUES"
                case .whitespace,
                     .comment:
                    cursor += 1
                default:
                    return false
                }
            }
            return false
        }
    }

    /// Words we uppercase and treat as keywords during reflow.
    fileprivate static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE",
        "BETWEEN", "IS", "NULL", "AS", "ASC", "DESC", "ON", "USING",
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
        "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET",
        "UNION", "ALL", "INTERSECT", "EXCEPT", "DISTINCT",
        "WITH", "RECURSIVE", "VALUES", "RETURNING",
        "CASE", "WHEN", "THEN", "ELSE", "END", "EXISTS",
        "INSERT", "INTO", "UPDATE", "DELETE", "SET",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "CAST",
        "OVER", "PARTITION", "WINDOW",
    ]

    /// Major clauses that start a new line at the current frame's
    /// base indent and shift the body indent in by one.
    fileprivate static let majorClauses: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY",
        "LIMIT", "OFFSET", "UNION", "UNION ALL", "INTERSECT", "EXCEPT",
        "WITH", "VALUES", "RETURNING",
    ]

    /// Multi-word JOIN heads that act like a single clause keyword.
    fileprivate static let joinClauses: Set<String> = [
        "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN",
        "CROSS JOIN", "LEFT OUTER JOIN", "RIGHT OUTER JOIN", "FULL OUTER JOIN",
    ]

    // MARK: Private

    // MARK: - Tokenizer

    private static func tokenize(_ sql: String) -> [Token] {
        var tokens: [Token] = []
        var index = sql.startIndex
        let end = sql.endIndex

        while index < end {
            let char = sql[index]
            if let token = scanWhitespace(sql, &index, end: end, char: char) {
                tokens.append(token); continue
            }
            if let token = scanLineComment(sql, &index, end: end, char: char) {
                tokens.append(token); continue
            }
            if let token = scanBlockComment(sql, &index, end: end, char: char) {
                tokens.append(token); continue
            }
            if let token = scanStringLiteral(sql, &index, end: end, char: char) {
                tokens.append(token); continue
            }
            if let token = scanWord(sql, &index, end: end, char: char) {
                tokens.append(token); continue
            }
            // Multi-char operators must stay glued — otherwise `!=`
            // becomes `!` `=`, which the emitter then puts a space
            // between, breaking the SQL.
            if let (op, span) = matchOperator(in: sql, at: index) {
                tokens.append(.symbol(op))
                index = sql.index(index, offsetBy: span)
                continue
            }
            tokens.append(.symbol(String(char)))
            index = sql.index(after: index)
        }
        return tokens
    }

    private static func scanWhitespace(
        _ sql: String, _ index: inout String.Index, end: String.Index, char: Character
    ) -> Token? {
        guard char.isWhitespace else {
            return nil
        }
        let start = index
        while index < end, sql[index].isWhitespace {
            index = sql.index(after: index)
        }
        return .whitespace(String(sql[start ..< index]))
    }

    private static func scanLineComment(
        _ sql: String, _ index: inout String.Index, end: String.Index, char: Character
    ) -> Token? {
        guard char == "-",
              sql.index(after: index) < end,
              sql[sql.index(after: index)] == "-"
        else {
            return nil
        }
        let start = index
        while index < end, sql[index] != "\n" {
            index = sql.index(after: index)
        }
        return .comment(String(sql[start ..< index]))
    }

    private static func scanBlockComment(
        _ sql: String, _ index: inout String.Index, end: String.Index, char: Character
    ) -> Token? {
        guard char == "/",
              sql.index(after: index) < end,
              sql[sql.index(after: index)] == "*"
        else {
            return nil
        }
        let start = index
        index = sql.index(index, offsetBy: 2)
        while index < end {
            if sql[index] == "*",
               sql.index(after: index) < end,
               sql[sql.index(after: index)] == "/"
            {
                index = sql.index(index, offsetBy: 2)
                break
            }
            index = sql.index(after: index)
        }
        return .comment(String(sql[start ..< index]))
    }

    private static func scanStringLiteral(
        _ sql: String, _ index: inout String.Index, end: String.Index, char: Character
    ) -> Token? {
        guard char == "'" || char == "\"" || char == "`" else {
            return nil
        }
        let quote = char
        let start = index
        index = sql.index(after: index)
        while index < end {
            if sql[index] == quote {
                let next = sql.index(after: index)
                if next < end, sql[next] == quote {
                    index = sql.index(after: next)
                    continue
                }
                index = next
                break
            }
            index = sql.index(after: index)
        }
        return .stringLiteral(String(sql[start ..< index]))
    }

    private static func scanWord(
        _ sql: String, _ index: inout String.Index, end: String.Index, char: Character
    ) -> Token? {
        guard char.isLetter || char.isNumber || char == "_" else {
            return nil
        }
        let start = index
        while index < end {
            let charHere = sql[index]
            if charHere.isLetter || charHere.isNumber
                || charHere == "_" || charHere == "."
            {
                index = sql.index(after: index)
            } else {
                break
            }
        }
        let raw = String(sql[start ..< index])
        let folded = keywords.contains(raw.uppercased()) ? raw.uppercased() : raw
        return .word(folded)
    }

    /// Try to match a SQLite multi-char operator starting at `at`.
    /// Tries longest-first (3-char before 2-char) so `->>` doesn't
    /// get truncated to `->`. Returns `nil` when only a single-char
    /// symbol is available.
    private static func matchOperator(in sql: String, at start: String.Index) -> (String, Int)? {
        let three = ["->>"]
        let two: [String] = [
            "!=", "<>", "<=", ">=", "==", "||", "<<", ">>", "->",
        ]
        // Three-char first.
        for op in three {
            if let end = sql.index(start, offsetBy: 3, limitedBy: sql.endIndex),
               sql[start ..< end] == Substring(op)
            {
                return (op, 3)
            }
        }
        for op in two {
            if let end = sql.index(start, offsetBy: 2, limitedBy: sql.endIndex),
               sql[start ..< end] == Substring(op)
            {
                return (op, 2)
            }
        }
        return nil
    }
}

// swiftlint:enable type_body_length
// swiftlint:enable file_length
