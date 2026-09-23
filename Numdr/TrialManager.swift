import Foundation
import SwiftUI
import Combine

/// Manages the 7-day free trial that starts on first launch.
@MainActor
final class TrialManager: ObservableObject {
    @AppStorage("NumdrTrialStartDate") private var trialStartTimestamp: Double = 0
    @Published private(set) var daysRemaining: Int = 0
    private let trialLengthDays = 7

    var isTrialStarted: Bool { trialStartTimestamp > 0 }
    var trialStartDate: Date? { isTrialStarted ? Date(timeIntervalSince1970: trialStartTimestamp) : nil }

    /// Call from lifecycle (e.g. onAppear); may write AppStorage.
    func startTrialIfNeeded() {
        if !isTrialStarted {
            trialStartTimestamp = Date().timeIntervalSince1970
        }
        updateDaysRemaining()
    }

    /// Recompute remaining days; safe from lifecycle or timers.
    func updateDaysRemaining() {
        guard let start = trialStartDate else {
            daysRemaining = trialLengthDays
            return
        }
        let end = Calendar.current.date(byAdding: .day, value: trialLengthDays, to: start) ?? start
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        daysRemaining = max(0, remaining)
    }

    /// No side effects.
    var isTrialActive: Bool {
        guard let start = trialStartDate else { return true }
        let end = Calendar.current.date(byAdding: .day, value: trialLengthDays, to: start) ?? start
        return Date() < end
    }
}
