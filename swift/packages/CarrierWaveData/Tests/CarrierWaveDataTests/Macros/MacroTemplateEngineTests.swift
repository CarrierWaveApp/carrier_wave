import CarrierWaveData
import Foundation
import Testing

struct MacroTemplateEngineTests {
    @Test func bareTokenIsError() {
        let engine = MacroTemplateEngine(args: [])
        #expect(throws: MacroTemplateError.self) {
            _ = try engine.resolve("hello {foo}", values: [:])
        }
    }

    @Test func argTokenResolves() throws {
        let arg = RadioMacroArg(name: "mycall", type: .string)
        let engine = MacroTemplateEngine(args: [arg])
        let result = try engine.resolve("DE {arg.mycall}", values: ["arg.mycall": "W6JY"])
        #expect(result == "DE W6JY")
    }

    @Test func ctxTokenResolves() throws {
        let engine = MacroTemplateEngine(args: [])
        let result = try engine.resolve(
            "FREQ {ctx.freq}",
            values: ["ctx.freq": "7032000"]
        )
        #expect(result == "FREQ 7032000")
    }

    @Test func argTokenWithoutDeclarationFails() {
        let engine = MacroTemplateEngine(args: [])
        #expect(throws: MacroTemplateError.self) {
            _ = try engine.resolve("{arg.notDeclared}", values: ["arg.notDeclared": "x"])
        }
    }

    @Test func malformedTemplateThrows() {
        let engine = MacroTemplateEngine(args: [])
        #expect(throws: MacroTemplateError.self) {
            _ = try engine.resolve("oops {never closed", values: [:])
        }
    }

    @Test func strictBoolRejectsYesAndOne() {
        let engine = MacroTemplateEngine(args: [])
        #expect(throws: MacroTemplateError.self) {
            _ = try engine.resolveBool("yes", values: [:])
        }
        #expect(throws: MacroTemplateError.self) {
            _ = try engine.resolveBool("1", values: [:])
        }
    }

    @Test func strictBoolAcceptsTrueAndFalse() throws {
        let engine = MacroTemplateEngine(args: [])
        #expect(try engine.resolveBool("true", values: [:]) == true)
        #expect(try engine.resolveBool("false", values: [:]) == false)
    }

    @Test func applyAsciiRejectsNonAscii() {
        #expect(throws: MacroFormatError.self) {
            _ = try MacroFormat.applyASCII("CQ — DE W6JY")
        }
    }

    @Test func applyAsciiAcceptsPlain() throws {
        let result = try MacroFormat.applyASCII("CQ DE W6JY")
        #expect(result == "CQ DE W6JY")
    }
}
