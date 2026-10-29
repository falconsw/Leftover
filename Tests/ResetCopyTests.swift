import XCTest
@testable import Leftover

final class ResetCopyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRelativeUnderAnHour() {
        XCTAssertEqual(
            ResetCopy.text(for: now.addingTimeInterval(51 * 60), now: now),
            "Resets in 51 min"
        )
    }

    func testRoundsToTheNearestMinute() {
        XCTAssertEqual(
            ResetCopy.text(for: now.addingTimeInterval(50 * 60 + 20), now: now),
            "Resets in 50 min"
        )
        XCTAssertEqual(
            ResetCopy.text(for: now.addingTimeInterval(50 * 60 + 40), now: now),
            "Resets in 51 min"
        )
    }

    /// The edge the whole rule turns on: at 60 minutes it stops counting down
    /// and names a time instead, so "Resets in 60 min" never appears.
    func testSwitchesToAbsoluteAtSixtyMinutes() {
        let atTheEdge = ResetCopy.text(for: now.addingTimeInterval(60 * 60), now: now)
        XCTAssertFalse(atTheEdge.contains("min"))
        XCTAssertTrue(atTheEdge.hasPrefix("Resets "))

        let justUnder = ResetCopy.text(for: now.addingTimeInterval(59 * 60 + 20), now: now)
        XCTAssertEqual(justUnder, "Resets in 59 min")

        // 59m40s rounds to 60, which must not print as "60 min" either.
        let rounding = ResetCopy.text(for: now.addingTimeInterval(59 * 60 + 40), now: now)
        XCTAssertFalse(rounding.contains("min"))
    }

    /// The frame writes "Resets Thu 12:00 AM"; a localised template gives
    /// "12.00 AM" in some regions, so the colon is pinned.
    func testAbsoluteTimeUsesAColon() {
        let text = ResetCopy.text(for: now.addingTimeInterval(6 * 60 * 60), now: now)
        XCTAssertTrue(text.contains(":"), "expected a colon in \(text)")
        let hasPeriodBetweenDigits = text.range(of: #"\d+\.\d+"#, options: .regularExpression) != nil
        XCTAssertFalse(hasPeriodBetweenDigits, "expected no full stop between time digits in \(text)")
    }

    /// Spanish (and similar locales) format AM/PM as "a. m." / "p. m." with
    /// periods, but the time separator itself must still be a colon.
    func testSpanishLocaleKeepsColonTimeSeparator() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        let text = ResetCopy.text(for: now.addingTimeInterval(6 * 60 * 60), now: now, calendar: calendar)
        XCTAssertTrue(text.contains(":"), "expected a colon in \(text)")
        let hasPeriodBetweenDigits = text.range(of: #"\d+\.\d+"#, options: .regularExpression) != nil
        XCTAssertFalse(hasPeriodBetweenDigits, "expected no full stop between time digits in \(text)")
    }

    /// Most of the world keeps a 24-hour clock, and this line was the one
    /// place it slipped into "12:00 AM": a literal `h` and `a` in the template
    /// pin the clock to twelve hours instead of asking the locale. Regions
    /// that do write AM/PM keep it, so the frame's English copy is unchanged.
    func testFollowsTheLocalesHourCycle() {
        let twentyFourHour = ["fr_FR", "de_DE", "es_ES", "it_IT", "pt_BR", "ru_RU",
                              "tr_TR", "ja_JP", "zh_CN", "en_GB"]
        let twelveHour = ["en_US", "en_AU", "en_CA", "en_IN", "ko_KR"]
        for id in twentyFourHour + twelveHour {
            let locale = Locale(identifier: id)
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            let text = ResetCopy.text(for: now.addingTimeInterval(6 * 60 * 60), now: now,
                                      calendar: calendar, locale: locale)
            // The locale's own day-period words rather than "AM": Japanese
            // writes 午前, Korean 오전, Australia am.
            let symbols = DateFormatter()
            symbols.locale = locale
            let hasDayPeriod = text.contains(symbols.amSymbol) || text.contains(symbols.pmSymbol)
            if twelveHour.contains(id) {
                XCTAssertTrue(hasDayPeriod, "\(id) lost its AM/PM: \(text)")
            } else {
                XCTAssertFalse(hasDayPeriod, "\(id) got a 12-hour clock: \(text)")
            }
        }
    }

    /// The hover path formats the same templates on every mouse event, so the
    /// formatter behind each template is built once and then reused — while
    /// two templates, or two locales, must never share one.
    func testFormattersAreReusedPerTemplateAndLocale() {
        let calendar = Calendar(identifier: .gregorian)
        let us = Locale(identifier: "en_US")
        let first = ResetCopy.formatter(template: "E j:mm", calendar: calendar, locale: us)
        let second = ResetCopy.formatter(template: "E j:mm", calendar: calendar, locale: us)
        XCTAssertIdentical(first, second)
        XCTAssertNotIdentical(
            first,
            ResetCopy.formatter(template: "MMM d", calendar: calendar, locale: us))
        XCTAssertNotIdentical(
            first,
            ResetCopy.formatter(template: "E j:mm", calendar: calendar,
                                locale: Locale(identifier: "fr_FR")))
    }

    func testPastResetsReadAsResetting() {
        XCTAssertEqual(ResetCopy.text(for: now.addingTimeInterval(-5), now: now), "Resetting…")
    }

    func testRemainingFormatAndRoundingBoundaries() {
        let cases: [(TimeInterval, String)] = [
            (-5, "Resetting…"), (0, "Resetting…"),
            (1, "Resets in 1 sec"),
            (42, "Resets in 42 sec"),
            (50 * 60 + 40, "Resets in 51 min"),
            (59 * 60 + 40, "Resets in 1h 0m"),
            (3 * 3600 + 20 * 60, "Resets in 3h 20m"),
            (24 * 3600 - 20, "Resets in 1 Day 0h"),
            (27 * 3600, "Resets in 1 Day 3h"),
            (75 * 3600, "Resets in 3 Days 3h"),
            (26 * 86400, "Resets in 26 Days 0h")
        ]
        for (seconds, expected) in cases {
            XCTAssertEqual(ResetCopy.text(for: now.addingTimeInterval(seconds), now: now,
                                          format: .remaining), expected)
        }
    }





    @MainActor
    func testResetTimePreferencePersistsAndFallsBackToAutomatic() throws {
        let name = "ResetCopyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.resetTimeFormat, .automatic)
        preferences.resetTimeFormat = .remaining
        XCTAssertEqual(Preferences(defaults: defaults).resetTimeFormat, .remaining)
        preferences.resetTimeFormat = .automatic
        XCTAssertEqual(Preferences(defaults: defaults).resetTimeFormat, .automatic)
        defaults.set("unknown", forKey: "resetTimeFormat")
        XCTAssertEqual(Preferences(defaults: defaults).resetTimeFormat, .automatic)
    }
}

/// A weekday only identifies a day inside the coming week. Codex's monthly
/// window resets nearly four weeks out, and "Resets Mon 3:55 PM" read as *this*
/// Monday — which is what made the app appear to disagree with Codex's own
/// "Resets Sep 28".
final class ResetCopyDistantDateTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    /// The reported case: 1 Sep to 28 Sep.
    func testAMonthAwayShowsTheDateNotAWeekday() {
        let text = ResetCopy.text(for: date("2026-09-28T15:55:00+07:00"),
                                  now: date("2026-09-01T23:30:00+07:00"),
                                  calendar: calendar)
        XCTAssertTrue(text.contains("28"), "the day of the month is missing: \(text)")
        XCTAssertFalse(text.contains("Mon"), "a date four weeks out still reads as a weekday")
        XCTAssertFalse(text.contains("PM"), "a time four weeks out is noise")
    }

    /// Inside the week a weekday is the friendlier answer, and unambiguous.
    func testWithinTheWeekKeepsTheWeekdayAndTime() {
        let text = ResetCopy.text(for: date("2026-09-04T12:00:00+07:00"),
                                  now: date("2026-09-01T23:30:00+07:00"),
                                  calendar: calendar)
        XCTAssertTrue(text.contains("12:00"), "expected a time: \(text)")
    }

    /// Seven days out is the same weekday name as today — the first genuinely
    /// ambiguous distance, so it is where the date form starts.
    func testSevenDaysIsAlreadyTooFarForAWeekday() {
        let text = ResetCopy.text(for: date("2026-09-08T12:00:00+07:00"),
                                  now: date("2026-09-01T12:00:00+07:00"),
                                  calendar: calendar)
        XCTAssertTrue(text.contains("8"), "expected a date: \(text)")
    }

    func testCountsWholeCalendarDaysNotElapsedHours() {
        // 23:30 to 00:30 the next day is one hour, but a different day.
        XCTAssertEqual(
            ResetCopy.daysApart(from: date("2026-09-01T23:30:00+07:00"),
                                to: date("2026-09-02T00:30:00+07:00"),
                                calendar: calendar), 1)
    }
}

/// Vendors disagree on which end of the figure to show — Codex writes "87%
/// remaining", Claude writes a percentage used. A notch that picks one side
/// makes the user convert in their head, and "12% Used" beside Codex's own
/// "87% remaining" reads as two different numbers rather than one seen from
/// either end. That is what made a correct reading look wrong.
final class WindowSummaryTests: XCTestCase {
    private func window(_ fraction: Double) -> LimitWindow {
        LimitWindow(id: "w", label: "Monthly limit", usedFraction: fraction)
    }

    func testItShowsBothEndsOfTheSameFigure() {
        XCTAssertEqual(window(0.12).summary, "12% Used · 88% left")
    }

    /// The two halves must always agree, or the line contradicts itself.
    func testTheHalvesAlwaysSumToAHundred() {
        for percent in stride(from: 0, through: 100, by: 7) {
            let text = window(Double(percent) / 100).summary
            let numbers = text.split(separator: " ").compactMap { Int($0.replacingOccurrences(of: "%", with: "")) }
            XCTAssertEqual(numbers.count, 2, "unexpected wording: \(text)")
            XCTAssertEqual(numbers[0] + numbers[1], 100, "\(text) does not add up")
        }
    }

    /// A limit can be reported past full; "-4% left" would be nonsense.
    func testAnOverspentLimitNeverGoesNegative() {
        XCTAssertEqual(window(1.04).summary, "104% Used · 0% left")
    }

    /// Below one percent, whole percents collapse a real reading into "0%" —
    /// the one number that looks most like nothing used. Both halves gain the
    /// tenth so they still add up.
    func testFractionsOfAPercentSurviveBelowOne() {
        XCTAssertEqual(window(0.0034).summary, "0.3% Used · 99.7% left")
        XCTAssertEqual(window(0.998).summary, "99.8% Used · 0.2% left")
    }

    /// A tenth of nothing is not zero: it says so rather than pretending.
    func testVanishingFractionsSaySo() {
        XCTAssertEqual(window(0.0004).summary, "<0.1% Used · >99.9% left")
    }


    /// Counts have no denominator, so they keep their own wording.
    func testCountsAreUntouched() {
        XCTAssertEqual(LimitWindow(id: "w", label: "Requests", used: 8).summary, "8 used")
        XCTAssertEqual(LimitWindow(id: "w", label: "Requests", remaining: 3).summary, "3 left")
    }

    private func snapshot(_ fraction: Double) -> ProviderSnapshot {
        ProviderSnapshot(id: "p", displayName: "P", glyph: .third, fidelity: .official,
                         status: .ok,
                         windows: [LimitWindow(id: "w", label: "W", usedFraction: fraction)],
                         headlineID: "w")
    }

    /// Only the number shortens; the wording around it does not.
    func testALargeCountKeepsItsWording() {
        XCTAssertEqual(LimitWindow(id: "w", label: "Tokens", used: 651_061).summary, "651k used")
    }

    /// Both ends stay on the line — the card is the detailed view — but the
    /// remaining figure leads when the notch is set that way.
    func testRemainingLeadsWhenSet() {
        XCTAssertEqual(window(0.12).summary(showingRemaining: true), "88% left · 12% Used")
    }

    /// Swapping the order never changes the numbers, so the halves still add
    /// up in either mode.
    func testTheHalvesStillSumToAHundredWhenRemainingLeads() {
        for percent in stride(from: 0, through: 100, by: 7) {
            let text = window(Double(percent) / 100).summary(showingRemaining: true)
            let numbers = text.split(separator: " ").compactMap { Int($0.replacingOccurrences(of: "%", with: "")) }
            XCTAssertEqual(numbers.count, 2, "unexpected wording: \(text)")
            XCTAssertEqual(numbers[0] + numbers[1], 100, "\(text) does not add up")
        }
    }

    func testAnOverspentLimitLeadsWithNothingLeft() {
        XCTAssertEqual(window(1.04).summary(showingRemaining: true), "0% left · 104% Used")
    }

    func testFractionsOfAPercentLeadFromTheOtherEnd() {
        XCTAssertEqual(window(0.0034).summary(showingRemaining: true), "99.7% left · 0.3% Used")
        XCTAssertEqual(window(0.998).summary(showingRemaining: true), "0.2% left · 99.8% Used")
        XCTAssertEqual(window(0.0004).summary(showingRemaining: true), ">99.9% left · <0.1% Used")
    }

    /// Counts keep their own wording — "3 left" already leads with what is left.
    func testCountsAreUntouchedWhenRemainingLeads() {
        XCTAssertEqual(LimitWindow(id: "w", label: "Requests", used: 8).summary(showingRemaining: true), "8 used")
        XCTAssertEqual(LimitWindow(id: "w", label: "Requests", remaining: 3).summary(showingRemaining: true), "3 left")
    }
}

/// "Resets in 4h 55m (13:30)" — how long there is, and when that is.
///
/// One timestamp read twice, so the two halves cannot disagree, and the day is
/// carried only when there is more than one day it could mean.
final class ResetStampTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()
    private let english = Locale(identifier: "en_GB")

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    private func stamped(_ from: String, _ to: String) -> String {
        ResetCopy.text(for: date(to), now: date(from), calendar: calendar,
                       format: .remaining, locale: english, withAbsoluteStamp: true)
    }

    /// Later today: the time alone. There is only one 13:30 it could be.
    func testSameDayCarriesTheTimeAlone() {
        let text = stamped("2026-09-01T08:35:00+07:00", "2026-09-01T13:30:00+07:00")
        XCTAssertEqual(text, "Resets in 4h 55m (13:30)")
    }

    /// Past midnight: the weekday joins it, because "01:30" alone would read
    /// as this morning — the one already gone.
    func testCrossingIntoAnotherDayCarriesTheDay() {
        let text = stamped("2026-09-01T21:00:00+07:00", "2026-09-02T01:30:00+07:00")
        XCTAssertEqual(text, "Resets in 4h 30m (Wed 01:30)")
    }

    /// A weekly window: days and hours, then the day and time it lands.
    func testAWeeklyWindowCarriesTheDayAndTime() {
        let text = stamped("2026-09-01T09:00:00+07:00", "2026-09-06T08:55:00+07:00")
        XCTAssertEqual(text, "Resets in 4 Days 23h (Sun 08:55)")
    }

    /// Past the week a weekday is ambiguous — the same reason `text` drops it
    /// there — so the stamp becomes a date.
    func testPastTheWeekTheStampBecomesADate() {
        let text = stamped("2026-09-01T23:30:00+07:00", "2026-09-28T15:55:00+07:00")
        XCTAssertTrue(text.hasPrefix("Resets in 26 Days"), text)
        XCTAssertTrue(text.contains("28"), text)
        XCTAssertFalse(text.contains("Mon"), "a date four weeks out still reads as a weekday: \(text)")
    }

    /// Both halves are read off one instant, so the countdown and the clock
    /// time can never drift apart.
    func testTheTwoHalvesComeFromOneTimestamp() {
        let from = date("2026-09-01T08:35:00+07:00")
        let to = date("2026-09-01T13:30:00+07:00")
        let combined = ResetCopy.text(for: to, now: from, calendar: calendar,
                                      format: .remaining, locale: english, withAbsoluteStamp: true)
        let relative = ResetCopy.text(for: to, now: from, calendar: calendar,
                                      format: .remaining, locale: english)
        let absolute = ResetCopy.absoluteStamp(for: to, now: from, calendar: calendar,
                                               locale: english)
        XCTAssertEqual(combined, "\(relative) (\(absolute))")
    }

    /// Asked for off, nothing changes — which is what keeps every surface that
    /// has not got the room exactly as it was.
    func testWithoutTheStampNothingChanges() {
        let from = date("2026-09-01T08:35:00+07:00")
        let to = date("2026-09-01T13:30:00+07:00")
        for format in ResetTimeFormat.allCases {
            XCTAssertEqual(
                ResetCopy.text(for: to, now: from, calendar: calendar, format: format, locale: english),
                ResetCopy.text(for: to, now: from, calendar: calendar, format: format,
                               locale: english, withAbsoluteStamp: false))
        }
    }

    /// The date format already names the day past the hour, so it is never
    /// made to say it twice — only its one relative case takes a stamp.
    func testTheDateFormatIsNotStampedTwice() {
        let under = stampedAutomatic("2026-09-01T08:35:00+07:00", "2026-09-01T09:20:00+07:00")
        XCTAssertEqual(under, "Resets in 45 min (09:20)")

        let over = stampedAutomatic("2026-09-01T08:35:00+07:00", "2026-09-01T13:30:00+07:00")
        XCTAssertFalse(over.contains("("), "the absolute form was stamped with itself: \(over)")
    }

    private func stampedAutomatic(_ from: String, _ to: String) -> String {
        ResetCopy.text(for: date(to), now: date(from), calendar: calendar,
                       format: .automatic, locale: english, withAbsoluteStamp: true)
    }
}

/// The stamp costs a row about 40pt, and the notch's card has not got it. A
/// card decides once, for every row on it, so a reset never half-appears.
@MainActor
final class ResetStampFitTests: XCTestCase {

    func testTheGapMeasuredIsTheGapDrawn() {
        // The two halves, the gap `SplitRow` draws, and the slack the fit test
        // keeps back: that width fits, a point under it does not.
        let width = NotchLayout.splitRowGap + NotchLayout.splitRowSlack
            + ("ab" as NSString).size(withAttributes: [.font: NotchLayout.cardBodyFont]).width
            + ("cd" as NSString).size(withAttributes: [.font: NotchLayout.cardBodyFont]).width
        XCTAssertTrue(NotchLayout.splitRowFits(leading: "ab", trailing: "cd", width: width))
        XCTAssertFalse(NotchLayout.splitRowFits(leading: "ab", trailing: "cd", width: width - 1))
    }

}
