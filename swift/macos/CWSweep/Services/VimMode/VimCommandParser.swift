import CarrierWaveCore
import Foundation

// MARK: - VimCommand

enum VimCommand: Equatable {
    // Radio/Config
    case connect(String) // connect w3lpl
    case disconnect // disconnect
    case setWPM(Int) // set wpm 25, wpm 25
    case setPower(Int) // set power 100
    case setRole(OperatingRole) // role hunter, role activator
    case park(String) // park K-1234
    case summit(String) // summit W4C/CM-001
    case splitUp(Int) // split up 2
    case splitDown(Int) // split dn 1
    case splitOff // split off
    case exportADIF // export adif
    case importADIF // import adif
    case tuneFrequency(Double) // freq 14.074, freq 14074 (MHz)
    case setMode(String) // mode CW, mode SSB, mode USB

    // Navigation (command palette parity)
    case navigate(SidebarItem) // logger, spots, cluster, dashboard, log, radio, sync
    case syncNow // sync now
    case toggleInspector // inspector

    // CW Sending
    case cq // cq
    case sendMemory(Int) // send 1-6
    case sendText(String) // send TU 73
    case agn // agn
    case tu // tu

    // Cluster
    case dx // dx
    case wwv // wwv
    case skimmer // skimmer
    case raw(String) // raw SH/DX

    // Activation
    case spot(String?) // spot, spot CQ 40m SSB
    case respot // respot
    case rove(String) // rove K-5678
    case endSession // end
    case upload // upload

    // Alerts
    case alertAdd(String) // alert add P5
    case alertList // alert list
    case alertClear // alert clear

    // Informational (echoed in the status line)
    case findCall(String) // find K4ABC
    case lastQSOs(Int) // last, last 10
    case sessionCount // count

    // Other
    case help // help
    case notes // notes
    case unknown(String) // unrecognized
}

// MARK: - VimCommandParser

enum VimCommandParser {
    // MARK: Internal

    static func parse(_ input: String) -> VimCommand {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .unknown("")
        }
        let tokens = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let command = tokens[0].lowercased()
        let args = tokens.count > 1 ? tokens[1] : nil
        return parseRadioAndCW(command: command, args: args, raw: trimmed)
            ?? parseClusterAndActivation(command: command, args: args, raw: trimmed)
            ?? parseNavigation(command: command, args: args)
            ?? parseRadioControlAndInfo(command: command, args: args)
            ?? .unknown(trimmed)
    }

    // MARK: Private

    private static func parseRadioAndCW(command: String, args: String?, raw: String) -> VimCommand? {
        switch command {
        case "connect": .connect(args ?? "")
        case "disconnect": .disconnect
        case "set": parseSet(args)
        case "wpm": .setWPM(Int(args ?? "") ?? 25)
        case "role": parseRole(args)
        case "park": .park(args ?? "")
        case "summit": .summit(args ?? "")
        case "split": parseSplit(args)
        case "export": .exportADIF
        case "import": .importADIF
        case "cq": .cq
        case "send": parseSend(args)
        case "agn": .agn
        case "tu": .tu
        default: nil
        }
    }

    private static func parseClusterAndActivation(command: String, args: String?, raw: String) -> VimCommand? {
        switch command {
        case "dx": .dx
        case "wwv": .wwv
        case "skimmer": .skimmer
        case "raw": .raw(args ?? "")
        case "spot": .spot(args)
        case "respot": .respot
        case "rove": .rove(args ?? "")
        case "end": .endSession
        case "upload": .upload
        case "alert": parseAlert(args)
        case "help": .help
        case "notes": .notes
        default: nil
        }
    }

    // MARK: Command palette parity

    private static func parseNavigation(command: String, args: String?) -> VimCommand? {
        switch command {
        case "logger": .navigate(.logger)
        case "spots": .navigate(.spots)
        case "cluster": .navigate(.cluster)
        case "satellites", "sat": .navigate(.satellites)
        case "dashboard": .navigate(.dashboard)
        case "log": .navigate(.qsoLog)
        case "radio": .navigate(.radio)
        case "sync": parseSync(args)
        case "inspector": .toggleInspector
        default: nil
        }
    }

    private static func parseRadioControlAndInfo(command: String, args: String?) -> VimCommand? {
        switch command {
        case "freq": parseFreq(args)
        case "mode": parseMode(args)
        case "find": parseFind(args)
        case "last": parseLast(args)
        case "count": .sessionCount
        default: nil
        }
    }

    /// `:sync` shows the Sync pane; `:sync now` kicks off a sync immediately.
    private static func parseSync(_ args: String?) -> VimCommand {
        guard let args else {
            return .navigate(.sync)
        }
        return args.lowercased() == "now" ? .syncNow : .unknown("sync \(args)")
    }

    /// Same kHz/MHz rules as the Cmd+K palette (`CommandPaletteFrequencyParser`).
    private static func parseFreq(_ args: String?) -> VimCommand {
        guard let args else {
            return .unknown("freq")
        }
        guard let mhz = CommandPaletteFrequencyParser.parse(args) else {
            return .unknown("freq \(args)")
        }
        return .tuneFrequency(mhz)
    }

    /// Accepts the radio palette's mode vocabulary (`RadioCommandParser.modeKeywords`).
    private static func parseMode(_ args: String?) -> VimCommand {
        guard let args else {
            return .unknown("mode")
        }
        let mode = args.uppercased()
        guard RadioCommandParser.modeKeywords.contains(mode) else {
            return .unknown("mode \(args)")
        }
        return .setMode(mode)
    }

    private static func parseFind(_ args: String?) -> VimCommand {
        guard let args, let callsign = args.split(separator: " ").first else {
            return .unknown("find")
        }
        return .findCall(String(callsign).uppercased())
    }

    /// `:last` defaults to 5; an explicit count must be a positive integer.
    private static func parseLast(_ args: String?) -> VimCommand {
        guard let args else {
            return .lastQSOs(5)
        }
        guard let count = Int(args), count > 0 else {
            return .unknown("last \(args)")
        }
        return .lastQSOs(count)
    }

    private static func parseSet(_ args: String?) -> VimCommand {
        guard let args else {
            return .unknown("set")
        }
        let parts = args.split(separator: " ", maxSplits: 1).map(String.init)
        guard let key = parts.first?.lowercased() else {
            return .unknown("set")
        }
        let value = parts.count > 1 ? parts[1] : nil
        switch key {
        case "wpm": return .setWPM(Int(value ?? "") ?? 25)
        case "power": return .setPower(Int(value ?? "") ?? 100)
        default: return .unknown("set \(args)")
        }
    }

    /// Every `OperatingRole` is addressable by its raw value, so new roles
    /// become `:role <name>` targets without touching the parser.
    private static func parseRole(_ args: String?) -> VimCommand {
        guard let args, let role = OperatingRole(rawValue: args.lowercased()) else {
            return .unknown("role \(args ?? "")")
        }
        return .setRole(role)
    }

    private static func parseSplit(_ args: String?) -> VimCommand {
        guard let args else {
            return .splitOff
        }
        let parts = args.split(separator: " ").map(String.init)
        guard let direction = parts.first?.lowercased() else {
            return .splitOff
        }
        let value = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        switch direction {
        case "up": return .splitUp(value)
        case "dn",
             "down": return .splitDown(value)
        case "off": return .splitOff
        default: return .unknown("split \(args)")
        }
    }

    private static func parseSend(_ args: String?) -> VimCommand {
        guard let args else {
            return .unknown("send")
        }
        if let num = Int(args), (1 ... 6).contains(num) {
            return .sendMemory(num)
        }
        return .sendText(args)
    }

    private static func parseAlert(_ args: String?) -> VimCommand {
        guard let args else {
            return .alertList
        }
        let parts = args.split(separator: " ", maxSplits: 1).map(String.init)
        guard let subcommand = parts.first?.lowercased() else {
            return .alertList
        }
        switch subcommand {
        case "add": return .alertAdd(parts.count > 1 ? parts[1] : "")
        case "list": return .alertList
        case "clear": return .alertClear
        default: return .unknown("alert \(args)")
        }
    }
}
