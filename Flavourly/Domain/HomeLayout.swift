import Foundation

/// The order of Home's sections for this moment and this cook: breakfast ideas first in the morning,
/// tonight's meal and quick ideas on weekday evenings, new dishes and world kitchens at the weekend,
/// and food that's about to go off whenever there is some.
enum HomeSection: String, CaseIterable {
    case rightNow, tonight, plan, useSoon, forYou, cookNow, quickActions, tryNew, local, world
}

enum HomeLayout {
    static func order(at moment: Moment, hasTonight: Bool, expiringToday: Bool, cooksAtThisMoment: Bool) -> [HomeSection] {
        var order: [HomeSection]
        switch (moment.weekend, moment.part) {
        case (_, .morning):
            order = [.rightNow, .forYou, .plan, .tonight, .useSoon, .quickActions, .cookNow, .tryNew, .local, .world]
        case (false, .evening), (false, .late):
            order = [.tonight, .rightNow, .cookNow, .useSoon, .forYou, .plan, .quickActions, .tryNew, .local, .world]
        case (true, _):
            order = [.rightNow, .tryNew, .world, .local, .forYou, .tonight, .plan, .useSoon, .cookNow, .quickActions]
        default:
            order = [.rightNow, .forYou, .useSoon, .plan, .tonight, .cookNow, .quickActions, .tryNew, .local, .world]
        }
        if !hasTonight { order.removeAll { $0 == .tonight } }
        // Food that goes off today matters more than anything but the meal itself.
        if expiringToday, let index = order.firstIndex(of: .useSoon) {
            order.remove(at: index)
            order.insert(.useSoon, at: min(1, order.count))
        }
        // A cook who rarely cooks at this time gets planning and quick actions before cooking prompts.
        if !cooksAtThisMoment, let index = order.firstIndex(of: .cookNow), index < 3 {
            order.remove(at: index)
            order.append(.cookNow)
        }
        return order
    }
}
