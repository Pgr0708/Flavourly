import Foundation

@main
struct HomeDataCheck {
    static func main() throws {
        assert(HomeMoment(hour: 4).imageName == "HomeNight")
        assert(HomeMoment(hour: 5).imageName == "HomeMorning")
        assert(HomeMoment(hour: 12).imageName == "HomeAfternoon")
        assert(HomeMoment(hour: 18).imageName == "HomeNight")
        assert(HomeMoment(hour: 9).greeting == "Good Morning")
        print("HomeDataCheck passed")
    }
}
