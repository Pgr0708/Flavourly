import Foundation

/// Time-of-day mood for the Home header (greeting + illustration).
enum HomeMoment {
    case morning, afternoon, night

    init(hour: Int) {
        if (5..<12).contains(hour) {
            self = .morning
        } else if (12..<18).contains(hour) {
            self = .afternoon
        } else {
            self = .night
        }
    }

    var greeting: String {
        switch self {
        case .morning: "Good Morning"
        case .afternoon: "Good Afternoon"
        case .night: "Good Evening"
        }
    }

    var imageName: String {
        switch self {
        case .morning: "HomeMorning"
        case .afternoon: "HomeAfternoon"
        case .night: "HomeNight"
        }
    }
}
