import SwiftUI
import SwiftData

@main
struct AICaddyApp: App {
    @State private var locationService = LocationService()
    @State private var speechService = SpeechService()
    @State private var clubRecommender = ClubRecommendationService()
    @State private var weatherService = WeatherService()
    @State private var elevationService = ElevationService()

    private let shotParser = ShotParserService()
    private let courseSearch = CourseSearchService()

    var body: some Scene {
        WindowGroup {
            HomeView(
                locationService: locationService,
                speechService: speechService,
                shotParser: shotParser,
                courseSearch: courseSearch,
                clubRecommender: clubRecommender,
                weatherService: weatherService,
                elevationService: elevationService
            )
            .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Course.self, Round.self, GolfBag.self, EquipmentLog.self])
    }
}
