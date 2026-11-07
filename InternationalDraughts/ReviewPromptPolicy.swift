import Foundation

/// Local-only counters. A request does not imply that StoreKit displayed a prompt
/// or that the player submitted a rating.
final class ReviewPromptPolicy {
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6787705126?action=write-review")!
    private let defaults: UserDefaults
    private let completedKey = "review.completedGames"
    private let dateKey = "review.lastRequestDate"
    private let versionKey = "review.lastRequestVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordCompletedGame() {
        defaults.set(defaults.integer(forKey: completedKey) + 1, forKey: completedKey)
    }

    func isEligible(version: String, now: Date = Date()) -> Bool {
        guard !version.isEmpty, defaults.integer(forKey: completedKey) >= 3,
              defaults.string(forKey: versionKey) != version else { return false }
        if let previous = defaults.object(forKey: dateKey) as? Date {
            return now.timeIntervalSince(previous) >= 120 * 24 * 60 * 60
        }
        return true
    }

    func recordRequest(version: String, now: Date = Date()) {
        defaults.set(now, forKey: dateKey)
        defaults.set(version, forKey: versionKey)
        defaults.set(0, forKey: completedKey)
    }
}
