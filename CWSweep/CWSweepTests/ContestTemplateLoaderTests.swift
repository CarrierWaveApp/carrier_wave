import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - ContestTemplateLoader Tests

@Test func templateLoaderDecodesBundledTemplates() async throws {
    let loader = ContestTemplateLoader()
    let templates = try await loader.allTemplates()
    // Should find at least the 8 bundled templates
    #expect(templates.count >= 8)
}

@Test func templateLoaderFindsCQWW() async throws {
    let loader = ContestTemplateLoader()
    let template = try await loader.template(for: "cq-ww-cw")
    #expect(template != nil)
    #expect(template?.name == "CQ World Wide DX Contest CW")
    #expect(template?.modes == ["CW"])
}

@Test func templateLoaderFindsFieldDay() async throws {
    let loader = ContestTemplateLoader()
    let template = try await loader.template(for: "arrl-field-day")
    #expect(template != nil)
    #expect(template?.name == "ARRL Field Day")
}

@Test func templateLoaderReturnsNilForUnknown() async throws {
    let loader = ContestTemplateLoader()
    let template = try await loader.template(for: "nonexistent-contest")
    #expect(template == nil)
}

@Test func templateLoaderAllTemplatesNonEmpty() async throws {
    let loader = ContestTemplateLoader()
    let templates = try await loader.allTemplates()
    #expect(!templates.isEmpty)
    for template in templates {
        #expect(!template.id.isEmpty)
        #expect(!template.name.isEmpty)
        #expect(!template.bands.isEmpty)
        #expect(!template.modes.isEmpty)
    }
}
