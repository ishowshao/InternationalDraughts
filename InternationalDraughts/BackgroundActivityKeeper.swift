//
//  BackgroundActivityKeeper.swift
//  InternationalDraughts
//
//  MultipeerConnectivity does not keep an app running indefinitely in the
//  background. Request a short period of background execution so a nearby
//  match can survive a brief app switch (normally around 30 seconds).
//

import UIKit

final class BackgroundActivityKeeper {

    private var taskID: UIBackgroundTaskIdentifier = .invalid

    /// Start preserving the current activity when the app enters background.
    /// Repeated calls are safe and keep using the existing background task.
    func begin() {
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(
            withName: "International Draughts nearby match"
        ) { [weak self] in
            self?.end()
        }
    }

    /// End the task after returning to foreground or leaving the match.
    func end() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }

    deinit {
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }
}
