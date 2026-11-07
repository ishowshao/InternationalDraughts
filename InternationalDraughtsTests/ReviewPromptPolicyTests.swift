import Foundation
import Testing
@testable import InternationalDraughts

struct ReviewPromptPolicyTests {
    @Test func requiresCompletedGamesAndPersistsAcrossLaunches() throws {
        let name = "ReviewTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let policy = ReviewPromptPolicy(defaults: defaults)
        #expect(!policy.isEligible(version: "1.6"))
        for _ in 0..<2 { policy.recordCompletedGame() }
        #expect(!policy.isEligible(version: "1.6"))
        policy.recordCompletedGame()
        #expect(ReviewPromptPolicy(defaults: defaults).isEligible(version: "1.6"))
        #expect(!policy.isEligible(version: ""))
    }

    @Test func respectsVersionCooldownAndFreshGames() throws {
        let name = "ReviewTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let policy = ReviewPromptPolicy(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = now.addingTimeInterval(120 * 24 * 60 * 60)
        for _ in 0..<3 { policy.recordCompletedGame() }
        policy.recordRequest(version: "1.6", now: now)
        #expect(!policy.isEligible(version: "1.7", now: later))
        for _ in 0..<3 { policy.recordCompletedGame() }
        #expect(!policy.isEligible(version: "1.6", now: later))
        #expect(!policy.isEligible(version: "1.7", now: later.addingTimeInterval(-1)))
        #expect(!policy.isEligible(version: "1.7", now: now.addingTimeInterval(-1)))
        #expect(policy.isEligible(version: "1.7", now: later))
    }
}
