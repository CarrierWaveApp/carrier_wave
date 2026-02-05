//
//  StreakCalculatorTests.swift
//  CarrierWaveCoreTests
//

import Foundation
import Testing
@testable import CarrierWaveCore

@Suite("Streak Calculator Tests")
struct StreakCalculatorTests {
    // MARK: Internal

    // MARK: - Tests

    @Test("Empty dates returns empty result")
    func emptyDates() {
        let result = StreakCalculator.calculateStreak(from: [])
        #expect(result.current == 0)
        #expect(result.longest == 0)
        #expect(result.currentStart == nil)
        #expect(result.longestStart == nil)
        #expect(result.lastActive == nil)
    }

    @Test("Single day streak")
    func singleDay() {
        let today = makeDate(daysAgo: 0)
        let result = StreakCalculator.calculateStreak(from: [today])

        #expect(result.current == 1)
        #expect(result.longest == 1)
        #expect(result.lastActive != nil)
    }

    @Test("Consecutive days streak")
    func consecutiveDays() {
        let dates: Set<Date> = [
            makeDate(daysAgo: 0),
            makeDate(daysAgo: 1),
            makeDate(daysAgo: 2),
        ]
        let result = StreakCalculator.calculateStreak(from: dates)

        #expect(result.current == 3)
        #expect(result.longest == 3)
    }

    @Test("Broken streak - yesterday still counts as current")
    func brokenStreakYesterday() {
        // Streak ended yesterday
        let dates: Set<Date> = [
            makeDate(daysAgo: 1),
            makeDate(daysAgo: 2),
            makeDate(daysAgo: 3),
        ]
        let result = StreakCalculator.calculateStreak(from: dates)

        #expect(result.current == 3)
        #expect(result.longest == 3)
    }

    @Test("Broken streak - two days ago no longer current")
    func brokenStreakTwoDaysAgo() {
        // Streak ended 2 days ago (gap of 1 day)
        let dates: Set<Date> = [
            makeDate(daysAgo: 2),
            makeDate(daysAgo: 3),
            makeDate(daysAgo: 4),
        ]
        let result = StreakCalculator.calculateStreak(from: dates)

        #expect(result.current == 0)
        #expect(result.longest == 3)
    }

    @Test("Multiple streaks - longest wins")
    func multipleStreaks() {
        // Two separate streaks: 2 days recently, 5 days earlier
        let dates: Set<Date> = [
            makeDate(daysAgo: 0),
            makeDate(daysAgo: 1),
            // Gap
            makeDate(daysAgo: 10),
            makeDate(daysAgo: 11),
            makeDate(daysAgo: 12),
            makeDate(daysAgo: 13),
            makeDate(daysAgo: 14),
        ]
        let result = StreakCalculator.calculateStreak(from: dates)

        #expect(result.current == 2)
        #expect(result.longest == 5)
    }

    @Test("Duplicate dates ignored")
    func duplicateDates() {
        let today = makeDate(daysAgo: 0)
        let dates: Set<Date> = [today, today, today] // Sets naturally dedupe
        let result = StreakCalculator.calculateStreak(from: dates)

        #expect(result.current == 1)
        #expect(result.longest == 1)
    }

    @Test("Last active date is tracked")
    func lastActiveDate() {
        let dates: Set<Date> = [
            makeDate(daysAgo: 5),
            makeDate(daysAgo: 10),
            makeDate(daysAgo: 2),
        ]
        let result = StreakCalculator.calculateStreak(from: dates)

        // Last active should be the most recent date
        #expect(result.lastActive == makeDate(daysAgo: 2))
    }

    // MARK: Private

    // MARK: - Helper

    private func makeDate(daysAgo: Int) -> Date {
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        )
    }
}
