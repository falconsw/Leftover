import XCTest
@testable import Leftover

/// Catalog lookups with an explicit locale. English is the source; Chinese,
/// French and Brazilian Portuguese assertions here only prove a translation
/// that exists is served, not that every key has one.
final class LocalizationTests: XCTestCase {
    private let zhHans = Locale(identifier: "zh-Hans")
    private let zhHant = Locale(identifier: "zh-Hant")
    private let french = Locale(identifier: "fr")
    private let german = Locale(identifier: "de")
    private let japanese = Locale(identifier: "ja")
    private let russian = Locale(identifier: "ru")
    private let ukrainian = Locale(identifier: "uk")
    private let uzbek = Locale(identifier: "uz")
    private let turkish = Locale(identifier: "tr")
    private let spanish = Locale(identifier: "es")
    private let brazilianPortuguese = Locale(identifier: "pt-BR")
    private let english = Locale(identifier: "en")
    private let indonesian = Locale(identifier: "id")
    private let now = Date(timeIntervalSince1970: 1_787_900_000)
    private let resetNow = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - ElapsedCopy

    func testElapsedCopyInEnglishWhenAsked() {
        XCTAssertEqual(
            ElapsedCopy.text(since: now.addingTimeInterval(-5), now: now, locale: english),
            "just now"
        )
        XCTAssertEqual(
            ElapsedCopy.text(since: now.addingTimeInterval(-6 * 60), now: now, locale: english),
            "6 min"
        )
        XCTAssertEqual(
            ElapsedCopy.text(since: now.addingTimeInterval(-60 * 60), now: now, locale: english),
            "1 hr"
        )
        XCTAssertEqual(
            ElapsedCopy.text(since: now.addingTimeInterval(-65 * 60), now: now, locale: english),
            "1 hr 5 min"
        )
        XCTAssertEqual(
            ElapsedCopy.ago(since: now.addingTimeInterval(-6 * 60), now: now, locale: english),
            "6 min ago"
        )
    }

    // MARK: - ResetCopy


    func testResetCopyUnderAnHourInEnglishWhenAsked() {
        XCTAssertEqual(
            ResetCopy.text(for: resetNow.addingTimeInterval(51 * 60), now: resetNow, locale: english),
            "Resets in 51 min"
        )
        XCTAssertEqual(
            ResetCopy.text(for: resetNow.addingTimeInterval(-5), now: resetNow, locale: english),
            "Resetting…"
        )
    }

    // MARK: - LimitWindow.summary

    func testWindowSummaryInEnglishWhenAsked() {
        XCTAssertEqual(
            percentWindow(0.12).summary(locale: english),
            "12% Used · 88% left"
        )
        XCTAssertEqual(
            LimitWindow(id: "w", label: "Requests", used: 8).summary(locale: english),
            "8 used"
        )
        XCTAssertEqual(
            LimitWindow(id: "w", label: "Requests", remaining: 3).summary(locale: english),
            "3 left"
        )
        XCTAssertEqual(
            LimitWindow(id: "w", label: "Requests").summary(locale: english),
            "No reading"
        )
    }

    // MARK: - Menu and settings keys

    func testMenuCopyInEnglishWhenAsked() {
        XCTAssertEqual(L10n.t("Always show", locale: english), "Always show")
        XCTAssertEqual(L10n.t("Settings…", locale: english), "Settings…")
    }

    // MARK: - Sign-in

    func testSignInActionTitleStaysEnglishUnderTheTestPin() {
        XCTAssertEqual(
            SignInRoute.modal(name: "Perplexity").actionTitle,
            "Sign in to Perplexity"
        )
    }

    func testSignInCopyInEnglishWhenAsked() {
        XCTAssertEqual(
            L10n.t("Sign in to \("Perplexity")", locale: english),
            "Sign in to Perplexity"
        )
    }

    // MARK: - French

    // MARK: - German

    // MARK: - Brazilian Portuguese


    // MARK: - Japanese

    // MARK: - Russian

    // MARK: - Ukrainian

    // MARK: - Traditional Chinese

    // MARK: - Uzbek

    // MARK: - Turkish

    func testCoreCopyInTurkish() {
        XCTAssertEqual(
            ElapsedCopy.text(since: now.addingTimeInterval(-5), now: now, locale: turkish),
            "az önce"
        )
        XCTAssertEqual(
            ElapsedCopy.text(since: now.addingTimeInterval(-6 * 60), now: now, locale: turkish),
            "6 dk"
        )
        XCTAssertEqual(
            ResetCopy.text(for: resetNow.addingTimeInterval(51 * 60), now: resetNow, locale: turkish),
            "51 dk içinde sıfırlanır"
        )
        XCTAssertEqual(
            percentWindow(0.12).summary(locale: turkish),
            "%12 kullanıldı · %88 kaldı"
        )
        XCTAssertEqual(L10n.t("Settings…", locale: turkish), "Ayarlar…")
        XCTAssertEqual(
            L10n.t("Sign in to \("Perplexity")", locale: turkish),
            "Giriş yap: Perplexity"
        )
    }

    /// Turkish names the limit before the percentage, so this string takes
    /// its values numbered — `%2$@` then `%1$lld`.
    func testTurkishThresholdAlertKeepsArgumentOrder() {
        XCTAssertEqual(
            L10n.t("\(80)% of its \("weekly") limit used.", locale: turkish),
            "weekly limitinin %80 kadarı kullanıldı."
        )
    }

    // MARK: - Spanish

    private func percentWindow(_ fraction: Double) -> LimitWindow {
        LimitWindow(id: "w", label: "Monthly limit", usedFraction: fraction)
    }
}
