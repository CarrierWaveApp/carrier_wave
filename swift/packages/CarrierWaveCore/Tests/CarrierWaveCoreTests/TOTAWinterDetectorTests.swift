//
//  TOTAWinterDetectorTests.swift
//  CarrierWaveCoreTests
//

import Foundation
import Testing
@testable import CarrierWaveCore

struct TOTAWinterDetectorTests {
    // MARK: Internal

    @Test("Northern hemisphere January is winter")
    func northernJanuaryIsWinter() {
        let date = makeDate(year: 2_026, month: 1, day: 15)
        #expect(TOTAWinterDetector.isWinter(latitude: 33.8, date: date))
    }

    @Test("Northern hemisphere July is not winter")
    func northernJulyNotWinter() {
        let date = makeDate(year: 2_026, month: 7, day: 15)
        #expect(!TOTAWinterDetector.isWinter(latitude: 33.8, date: date))
    }

    @Test("Southern hemisphere July is winter")
    func southernJulyIsWinter() {
        let date = makeDate(year: 2_026, month: 7, day: 15)
        #expect(TOTAWinterDetector.isWinter(latitude: -33.8, date: date))
    }

    @Test("Southern hemisphere January is not winter")
    func southernJanuaryNotWinter() {
        let date = makeDate(year: 2_026, month: 1, day: 15)
        #expect(!TOTAWinterDetector.isWinter(latitude: -33.8, date: date))
    }

    @Test("Equator-adjacent never winter")
    func equatorialNeverWinter() {
        let dateJan = makeDate(year: 2_026, month: 1, day: 15)
        let dateJul = makeDate(year: 2_026, month: 7, day: 15)
        #expect(!TOTAWinterDetector.isWinter(latitude: 2.0, date: dateJan))
        #expect(!TOTAWinterDetector.isWinter(latitude: -2.0, date: dateJul))
    }

    @Test("Nil latitude defaults to northern")
    func nilLatitudeDefaultsNorthern() {
        let dateDec = makeDate(year: 2_026, month: 12, day: 15)
        #expect(TOTAWinterDetector.isWinter(latitude: nil, date: dateDec))
    }

    @Test("December is winter in northern hemisphere")
    func decemberIsWinter() {
        let date = makeDate(year: 2_026, month: 12, day: 31)
        #expect(TOTAWinterDetector.isWinter(latitude: 45.0, date: date))
    }

    @Test("February is winter in northern hemisphere")
    func februaryIsWinter() {
        let date = makeDate(year: 2_026, month: 2, day: 1)
        #expect(TOTAWinterDetector.isWinter(latitude: 45.0, date: date))
    }

    // MARK: Private

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? Date()
    }
}
