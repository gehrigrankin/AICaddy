import SwiftUI

struct MainTabView: View {
    let locationService: LocationService
    let speechService: SpeechService
    let shotParser: ShotParserService
    let courseSearch: CourseSearchService
    let clubRecommender: ClubRecommendationService
    let weatherService: WeatherService
    let elevationService: ElevationService

    var body: some View {
        TabView {
            HomeView(
                locationService: locationService,
                speechService: speechService,
                shotParser: shotParser,
                courseSearch: courseSearch,
                clubRecommender: clubRecommender,
                weatherService: weatherService,
                elevationService: elevationService
            )
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }

            NavigationStack {
                StatsDashboardView()
            }
            .tabItem {
                Image(systemName: "chart.xyaxis.line")
                Text("Stats")
            }

            NavigationStack {
                BagView()
            }
            .tabItem {
                Image(systemName: "bag.fill")
                Text("My Bag")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Image(systemName: "clock.arrow.circlepath")
                Text("History")
            }
        }
        .tint(.green)
    }
}
