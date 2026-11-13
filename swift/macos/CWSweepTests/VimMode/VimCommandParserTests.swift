import Testing
@testable import CWSweep

// MARK: - VimCommandParserRadioTests

struct VimCommandParserRadioTests {
    @Test func connectWithCallsign() {
        #expect(VimCommandParser.parse("connect w3lpl") == .connect("w3lpl"))
    }

    @Test func connectNoArgs() {
        #expect(VimCommandParser.parse("connect") == .connect(""))
    }

    @Test func disconnect() {
        #expect(VimCommandParser.parse("disconnect") == .disconnect)
    }

    @Test func setWPM() {
        #expect(VimCommandParser.parse("set wpm 25") == .setWPM(25))
    }

    @Test func setWPMDefault() {
        #expect(VimCommandParser.parse("set wpm") == .setWPM(25))
    }

    @Test func wpmShortcut() {
        #expect(VimCommandParser.parse("wpm 30") == .setWPM(30))
    }

    @Test func wpmShortcutDefault() {
        #expect(VimCommandParser.parse("wpm") == .setWPM(25))
    }

    @Test func setPower() {
        #expect(VimCommandParser.parse("set power 100") == .setPower(100))
    }

    @Test func setPowerDefault() {
        #expect(VimCommandParser.parse("set power") == .setPower(100))
    }

    @Test func setUnknownKey() {
        #expect(VimCommandParser.parse("set foo bar") == .unknown("set foo bar"))
    }

    @Test func setNoArgs() {
        #expect(VimCommandParser.parse("set") == .unknown("set"))
    }

    @Test func roleHunter() {
        #expect(VimCommandParser.parse("role hunter") == .setRole(.hunter))
    }

    @Test func roleActivator() {
        #expect(VimCommandParser.parse("role activator") == .setRole(.activator))
    }

    @Test func roleIsCaseInsensitive() {
        #expect(VimCommandParser.parse("role ACTIVATOR") == .setRole(.activator))
    }

    @Test(arguments: OperatingRole.allCases)
    func roleCoversEveryOperatingRole(role: OperatingRole) {
        #expect(VimCommandParser.parse("role \(role.rawValue)") == .setRole(role))
    }

    @Test func roleUnknown() {
        #expect(VimCommandParser.parse("role dxer") == .unknown("role dxer"))
    }

    @Test func roleNoArgs() {
        #expect(VimCommandParser.parse("role") == .unknown("role "))
    }

    @Test func park() {
        #expect(VimCommandParser.parse("park K-1234") == .park("K-1234"))
    }

    @Test func parkNoArgs() {
        #expect(VimCommandParser.parse("park") == .park(""))
    }

    @Test func summit() {
        #expect(VimCommandParser.parse("summit W4C/CM-001") == .summit("W4C/CM-001"))
    }

    @Test func summitNoArgs() {
        #expect(VimCommandParser.parse("summit") == .summit(""))
    }

    @Test func splitUp() {
        #expect(VimCommandParser.parse("split up 2") == .splitUp(2))
    }

    @Test func splitUpDefaultValue() {
        #expect(VimCommandParser.parse("split up") == .splitUp(1))
    }

    @Test func splitDn() {
        #expect(VimCommandParser.parse("split dn 1") == .splitDown(1))
    }

    @Test func splitDown() {
        #expect(VimCommandParser.parse("split down 3") == .splitDown(3))
    }

    @Test func splitOff() {
        #expect(VimCommandParser.parse("split off") == .splitOff)
    }

    @Test func splitNoArgs() {
        #expect(VimCommandParser.parse("split") == .splitOff)
    }

    @Test func splitUnknown() {
        #expect(VimCommandParser.parse("split sideways") == .unknown("split sideways"))
    }

    @Test func exportADIF() {
        #expect(VimCommandParser.parse("export") == .exportADIF)
    }

    @Test func importADIF() {
        #expect(VimCommandParser.parse("import") == .importADIF)
    }
}

// MARK: - VimCommandParserCWSendingTests

struct VimCommandParserCWSendingTests {
    @Test func cq() {
        #expect(VimCommandParser.parse("cq") == .cq)
    }

    @Test func sendMemoryOne() {
        #expect(VimCommandParser.parse("send 1") == .sendMemory(1))
    }

    @Test func sendMemorySix() {
        #expect(VimCommandParser.parse("send 6") == .sendMemory(6))
    }

    @Test func sendMemoryOutOfRange() {
        #expect(VimCommandParser.parse("send 7") == .sendText("7"))
    }

    @Test func sendMemoryZero() {
        #expect(VimCommandParser.parse("send 0") == .sendText("0"))
    }

    @Test func sendFreeformText() {
        #expect(VimCommandParser.parse("send TU 73") == .sendText("TU 73"))
    }

    @Test func sendNoArgs() {
        #expect(VimCommandParser.parse("send") == .unknown("send"))
    }

    @Test func agn() {
        #expect(VimCommandParser.parse("agn") == .agn)
    }

    @Test func tu() {
        #expect(VimCommandParser.parse("tu") == .tu)
    }
}

// MARK: - VimCommandParserClusterTests

struct VimCommandParserClusterTests {
    @Test func dx() {
        #expect(VimCommandParser.parse("dx") == .dx)
    }

    @Test func wwv() {
        #expect(VimCommandParser.parse("wwv") == .wwv)
    }

    @Test func skimmer() {
        #expect(VimCommandParser.parse("skimmer") == .skimmer)
    }

    @Test func raw() {
        #expect(VimCommandParser.parse("raw SH/DX") == .raw("SH/DX"))
    }

    @Test func rawNoArgs() {
        #expect(VimCommandParser.parse("raw") == .raw(""))
    }
}

// MARK: - VimCommandParserActivationTests

struct VimCommandParserActivationTests {
    @Test func spotNoComment() {
        #expect(VimCommandParser.parse("spot") == .spot(nil))
    }

    @Test func spotWithComment() {
        #expect(VimCommandParser.parse("spot CQ 40m SSB") == .spot("CQ 40m SSB"))
    }

    @Test func respot() {
        #expect(VimCommandParser.parse("respot") == .respot)
    }

    @Test func rove() {
        #expect(VimCommandParser.parse("rove K-5678") == .rove("K-5678"))
    }

    @Test func roveNoArgs() {
        #expect(VimCommandParser.parse("rove") == .rove(""))
    }

    @Test func endSession() {
        #expect(VimCommandParser.parse("end") == .endSession)
    }

    @Test func upload() {
        #expect(VimCommandParser.parse("upload") == .upload)
    }
}

// MARK: - VimCommandParserAlertTests

struct VimCommandParserAlertTests {
    @Test func alertAdd() {
        #expect(VimCommandParser.parse("alert add P5") == .alertAdd("P5"))
    }

    @Test func alertAddNoArg() {
        #expect(VimCommandParser.parse("alert add") == .alertAdd(""))
    }

    @Test func alertList() {
        #expect(VimCommandParser.parse("alert list") == .alertList)
    }

    @Test func alertNoSubcommand() {
        #expect(VimCommandParser.parse("alert") == .alertList)
    }

    @Test func alertClear() {
        #expect(VimCommandParser.parse("alert clear") == .alertClear)
    }

    @Test func alertUnknown() {
        #expect(VimCommandParser.parse("alert foo") == .unknown("alert foo"))
    }
}

// MARK: - VimCommandParserOtherTests

struct VimCommandParserOtherTests {
    @Test func help() {
        #expect(VimCommandParser.parse("help") == .help)
    }

    @Test func notes() {
        #expect(VimCommandParser.parse("notes") == .notes)
    }

    @Test func emptyInput() {
        #expect(VimCommandParser.parse("") == .unknown(""))
    }

    @Test func whitespaceOnly() {
        #expect(VimCommandParser.parse("   ") == .unknown(""))
    }

    @Test func unknownCommand() {
        #expect(VimCommandParser.parse("frobulate") == .unknown("frobulate"))
    }

    @Test func caseInsensitive() {
        #expect(VimCommandParser.parse("CONNECT w3lpl") == .connect("w3lpl"))
    }

    @Test func leadingTrailingWhitespace() {
        #expect(VimCommandParser.parse("  disconnect  ") == .disconnect)
    }
}

// MARK: - VimCommandParserFrequencyTests

/// `:freq` must accept exactly what the Cmd+K palette's bare-number detection accepts.
struct VimCommandParserFrequencyTests {
    @Test func freqMHzWithDecimal() {
        #expect(VimCommandParser.parse("freq 14.074") == .tuneFrequency(14.074))
    }

    @Test func freqKHzConvertsToMHz() {
        #expect(VimCommandParser.parse("freq 14074") == .tuneFrequency(14.074))
    }

    @Test func freqKHzWithDecimal() {
        #expect(VimCommandParser.parse("freq 7032.5") == .tuneFrequency(7.0325))
    }

    @Test func freqSmallMHz() {
        #expect(VimCommandParser.parse("freq 7") == .tuneFrequency(7))
    }

    @Test func freqNonNumericIsUnknown() {
        #expect(VimCommandParser.parse("freq abc") == .unknown("freq abc"))
    }

    @Test func freqOutOfRangeIsUnknown() {
        // 500 ..< 1000 is neither a plausible MHz nor kHz value in the palette parser.
        #expect(VimCommandParser.parse("freq 600") == .unknown("freq 600"))
    }

    @Test func freqZeroIsUnknown() {
        #expect(VimCommandParser.parse("freq 0") == .unknown("freq 0"))
    }

    @Test func freqNoArgsIsUnknown() {
        #expect(VimCommandParser.parse("freq") == .unknown("freq"))
    }

    @Test func paletteParserMatchesVimParser() {
        for input in ["14.074", "14074", "7", "3573", "abc", "600", ""] {
            let expected = CommandPaletteFrequencyParser.parse(input)
            let vim = VimCommandParser.parse("freq \(input)")
            if let expected {
                #expect(vim == .tuneFrequency(expected), "input: \(input)")
            } else if case .tuneFrequency = vim {
                Issue.record("\(input) should not tune")
            }
        }
    }
}

// MARK: - VimCommandParserModeTests

struct VimCommandParserModeTests {
    @Test func modeCW() {
        #expect(VimCommandParser.parse("mode CW") == .setMode("CW"))
    }

    @Test func modeSSBUppercases() {
        #expect(VimCommandParser.parse("mode ssb") == .setMode("SSB"))
    }

    @Test func modeUSB() {
        #expect(VimCommandParser.parse("mode usb") == .setMode("USB"))
    }

    @Test func modeFT8() {
        #expect(VimCommandParser.parse("mode ft8") == .setMode("FT8"))
    }

    @Test func modeUnknownKeyword() {
        #expect(VimCommandParser.parse("mode banana") == .unknown("mode banana"))
    }

    @Test func modeNoArgs() {
        #expect(VimCommandParser.parse("mode") == .unknown("mode"))
    }
}

// MARK: - VimCommandParserNavigationTests

struct VimCommandParserNavigationTests {
    @Test func logger() {
        #expect(VimCommandParser.parse("logger") == .navigate(.logger))
    }

    @Test func spots() {
        #expect(VimCommandParser.parse("spots") == .navigate(.spots))
    }

    @Test func cluster() {
        #expect(VimCommandParser.parse("cluster") == .navigate(.cluster))
    }

    @Test func dashboard() {
        #expect(VimCommandParser.parse("dashboard") == .navigate(.dashboard))
    }

    @Test func logIsQSOLog() {
        #expect(VimCommandParser.parse("log") == .navigate(.qsoLog))
    }

    @Test func radio() {
        #expect(VimCommandParser.parse("radio") == .navigate(.radio))
    }

    @Test func syncNoArgsNavigates() {
        #expect(VimCommandParser.parse("sync") == .navigate(.sync))
    }

    @Test func syncNowTriggersSync() {
        #expect(VimCommandParser.parse("sync now") == .syncNow)
    }

    @Test func syncNowIsCaseInsensitive() {
        #expect(VimCommandParser.parse("sync NOW") == .syncNow)
    }

    @Test func syncUnknownArg() {
        #expect(VimCommandParser.parse("sync later") == .unknown("sync later"))
    }

    @Test func inspector() {
        #expect(VimCommandParser.parse("inspector") == .toggleInspector)
    }

    @Test func navigationIsCaseInsensitive() {
        #expect(VimCommandParser.parse("Dashboard") == .navigate(.dashboard))
    }
}

// MARK: - VimCommandParserInfoTests

struct VimCommandParserInfoTests {
    @Test func findUppercasesCallsign() {
        #expect(VimCommandParser.parse("find k4abc") == .findCall("K4ABC"))
    }

    @Test func findTakesFirstToken() {
        #expect(VimCommandParser.parse("find W1AW extra") == .findCall("W1AW"))
    }

    @Test func findNoArgs() {
        #expect(VimCommandParser.parse("find") == .unknown("find"))
    }

    @Test func lastDefaultsToFive() {
        #expect(VimCommandParser.parse("last") == .lastQSOs(5))
    }

    @Test func lastExplicitCount() {
        #expect(VimCommandParser.parse("last 10") == .lastQSOs(10))
    }

    @Test func lastZeroIsUnknown() {
        #expect(VimCommandParser.parse("last 0") == .unknown("last 0"))
    }

    @Test func lastNegativeIsUnknown() {
        #expect(VimCommandParser.parse("last -3") == .unknown("last -3"))
    }

    @Test func lastNonNumericIsUnknown() {
        #expect(VimCommandParser.parse("last many") == .unknown("last many"))
    }

    @Test func count() {
        #expect(VimCommandParser.parse("count") == .sessionCount)
    }
}
