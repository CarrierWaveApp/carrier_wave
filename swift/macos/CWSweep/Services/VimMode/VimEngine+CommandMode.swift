import Foundation

extension VimEngine {
    func completeCommand() {
        let known = [
            "agn", "alert", "cluster", "count", "cq", "connect",
            "dashboard", "disconnect", "dx", "end", "export",
            "find", "freq", "help", "import", "inspector",
            "last", "log", "logger", "mode", "notes", "park",
            "radio", "raw", "respot", "role", "rove", "send",
            "set", "skimmer", "split", "spot", "spots", "summit",
            "sync", "tu", "upload", "wpm", "wwv",
        ]
        let input = commandLineText.lowercased()
        guard !input.isEmpty else {
            return
        }
        let matches = known.filter { $0.hasPrefix(input) }
        if matches.count == 1 {
            commandLineText = matches[0] + " "
        } else if matches.count > 1 {
            let common = longestCommonPrefix(matches)
            if common.count > input.count {
                commandLineText = common
            } else {
                echo(matches.joined(separator: " "))
            }
        }
    }

    private func longestCommonPrefix(_ strings: [String]) -> String {
        guard let first = strings.first else {
            return ""
        }
        var prefix = first
        for str in strings.dropFirst() {
            while !str.hasPrefix(prefix) {
                prefix = String(prefix.dropLast())
            }
        }
        return prefix
    }
}
