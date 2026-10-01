//
//  DropsManager.swift
//  Flavourly
//
//  Status banners for every action: success, error, warning, info and live progress.
//  Each kind pairs with its own haptic so users feel the outcome as well as see it.
//

import UIKit
import Drops

enum DropsManager {
    private static let brandGreen = UIColor(red: 0.08, green: 0.34, blue: 0.20, alpha: 1)
    private static var lastProgressStep: [String: Int] = [:]

    // MARK: - Outcomes

    static func showSuccess(title: String, subtitle: String? = nil) {
        Haptics.success()
        show(title: title, subtitle: subtitle, symbol: "checkmark.circle.fill", tint: .systemGreen, seconds: 2.6)
    }

    static func showError(title: String, subtitle: String? = nil) {
        Haptics.error()
        show(title: title, subtitle: subtitle, symbol: "xmark.octagon.fill", tint: .systemRed, seconds: 4)
    }

    static func showWarning(title: String, subtitle: String? = nil) {
        Haptics.warning()
        show(title: title, subtitle: subtitle, symbol: "exclamationmark.triangle.fill", tint: .systemOrange, seconds: 3.5)
    }

    static func showInfo(title: String, subtitle: String? = nil) {
        show(title: title, subtitle: subtitle, symbol: "info.circle.fill", tint: .systemBlue, seconds: 2.6)
    }

    /// Short "working on it" banner that dismisses itself.
    static func showLoading(title: String, subtitle: String? = nil) {
        show(title: title, subtitle: subtitle, symbol: "arrow.triangle.2.circlepath", tint: .systemOrange, seconds: 1.5)
    }

    // MARK: - Progress

    /// Shows "Title · 40%" with a progress ring. Throttled to 25 % steps per `id`
    /// so a fast-moving job does not flood the screen. 100 % becomes a success banner.
    static func showProgress(id: String, title: String, fraction: Double, subtitle: String? = nil) {
        let clamped = min(max(fraction, 0), 1)
        let step = Int((clamped * 4).rounded(.down))
        guard lastProgressStep[id] != step else { return }
        lastProgressStep[id] = step
        if clamped >= 1 {
            lastProgressStep[id] = nil
            Drops.hideAll()
            showSuccess(title: title, subtitle: subtitle ?? "Done")
            return
        }
        Haptics.step()
        Drops.hideAll()
        var drop = Drop(
            title: "\(title) · \(Int(clamped * 100))%",
            subtitle: subtitle,
            icon: ringImage(clamped),
            position: .top,
            duration: .seconds(6)
        )
        drop.action = Drop.Action { Drops.hideCurrent() }
        Drops.show(drop)
    }

    /// Ends a progress run early (failure or cancel) without a success banner.
    static func endProgress(id: String) {
        lastProgressStep[id] = nil
        Drops.hideAll()
    }

    // MARK: - Dismiss

    static func hide() { Drops.hideCurrent() }

    // MARK: - Private

    private static func show(title: String, subtitle: String?, symbol: String, tint: UIColor, seconds: TimeInterval) {
        var drop = Drop(
            title: title,
            subtitle: subtitle,
            subtitleNumberOfLines: 2,
            icon: UIImage(systemName: symbol)?.withTintColor(tint, renderingMode: .alwaysOriginal),
            position: .top,
            duration: .seconds(seconds)
        )
        drop.action = Drop.Action { Drops.hideCurrent() }
        Drops.show(drop)
    }

    private static func ringImage(_ fraction: Double) -> UIImage {
        let size = CGSize(width: 26, height: 26)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2.5, dy: 2.5)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let track = UIBezierPath(ovalIn: rect)
            track.lineWidth = 3.5
            UIColor(white: 0.88, alpha: 1).setStroke()
            track.stroke()
            let start = -CGFloat.pi / 2
            let arc = UIBezierPath(
                arcCenter: center, radius: rect.width / 2,
                startAngle: start, endAngle: start + 2 * .pi * CGFloat(max(fraction, 0.02)),
                clockwise: true
            )
            arc.lineWidth = 3.5
            arc.lineCapStyle = .round
            brandGreen.setStroke()
            arc.stroke()
        }
    }
}
