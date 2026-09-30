//
//  DropsManager.swift
//  GoViral
//
//  Created by Minaxi on 16/08/26.
//

import UIKit
import Drops

enum DropsManager {

    // MARK: - Success

    static func showSuccess(title: String, subtitle: String? = nil) {
        DispatchQueue.main.async {
            var drop = Drop(title: title, subtitle: subtitle)
            drop.icon = UIImage(systemName: "checkmark.circle.fill")?
                .withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
            drop.action = Drop.Action(handler: { Drops.hideCurrent() })
            drop.position = Drop.Position.top
            drop.duration = Drop.Duration.seconds(3.0)
            drop.accessibility = Drop.Accessibility(
                message: "Success: \(title)"
            )
            Drops.show(drop)
        }
    }

    // MARK: - Error

    static func showError(title: String, subtitle: String? = nil) {
        DispatchQueue.main.async {
            var drop = Drop(title: title, subtitle: subtitle)
            drop.icon = UIImage(systemName: "xmark.circle.fill")?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            drop.action = Drop.Action(handler: { Drops.hideCurrent() })
            drop.position = Drop.Position.top
            drop.duration = Drop.Duration.seconds(4.0)
            drop.accessibility = Drop.Accessibility(
                message: "Error: \(title)"
            )
            Drops.show(drop)
        }
    }

    // MARK: - Info

    static func showInfo(title: String, subtitle: String? = nil) {
        DispatchQueue.main.async {
            var drop = Drop(title: title, subtitle: subtitle)
            drop.icon = UIImage(systemName: "info.circle.fill")?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            drop.action = Drop.Action(handler: { Drops.hideCurrent() })
            drop.position = Drop.Position.top
            drop.duration = Drop.Duration.seconds(3.0)
            drop.accessibility = Drop.Accessibility(
                message: "Info: \(title)"
            )
            Drops.show(drop)
        }
    }

    // MARK: - Loading (persists until hide() is called)

    static func showLoading(title: String, subtitle: String? = nil) {
        DispatchQueue.main.async {
            var drop = Drop(title: title, subtitle: subtitle)
            drop.icon = UIImage(systemName: "arrow.triangle.2.circlepath")?
                .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
            drop.position = Drop.Position.top
            drop.duration = Drop.Duration.seconds(1.5) // Auto-dismisses after 1.5s
            drop.accessibility = Drop.Accessibility(
                message: "Loading: \(title)"
            )
            Drops.show(drop)
        }
    }

    // MARK: - Dismiss

    static func hide() {
        DispatchQueue.main.async {
            Drops.hideCurrent()
        }
    }
}
