import SwiftUI
import SwiftData
import CoreLocation

struct HomeView: View {
    @Query(sort: \Round.date, order: .reverse) private var allRounds: [Round]
    @Query(sort: \Course.createdAt, order: .reverse) private var savedCourses: [Course]
    @Query private var bags: [GolfBag]
    @State private var showNewRound = false
    @State private var roundToResume: Round?
    @State private var geofenceDismissed = false

    let locationService: LocationService
    let speechService: SpeechService
    let shotParser: ShotParserService
    let courseSearch: CourseSearchService
    let clubRecommender: ClubRecommendationService
    let weatherService: WeatherService
    let elevationService: ElevationService

    private var inProgressRound: Round? {
        allRounds.first { !$0.isComplete }
    }

    private var recentCompleted: [Round] {
        Array(allRounds.filter(\.isComplete).prefix(5))
    }

    private var handicapRounds: [HandicapRound] {
        allRounds.filter(\.isComplete)
            .sorted { $0.date > $1.date }
            .prefix(20)
            .compactMap { HandicapRound.fromRound($0) }
    }

    private var calculatedHandicap: Double? {
        HandicapCalculator.calculateIndex(rounds: handicapRounds)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero
                    VStack(spacing: 8) {
                        Text("⛳")
                            .font(.system(size: 48))
                        Text("AI Caddy")
                            .font(.largeTitle.bold())
                        Text("Track your round with voice.\nGet the stats you never had time to log.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Nearby course geofence banner
                    if let courseName = locationService.nearbyCourseName,
                       !geofenceDismissed {
                        Button {
                            showNewRound = true
                            geofenceDismissed = true
                            locationService.dismissNearbyCourse()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NEARBY COURSE DETECTED")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.blue)
                                    Text("Looks like you're at \(courseName). Tap to start a round.")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                geofenceDismissed = true
                                locationService.dismissNearbyCourse()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .contentShape(Rectangle())
                            }
                        }
                    }

                    // Handicap Index
                    if let handicap = calculatedHandicap {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HANDICAP INDEX")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f", handicap))
                                    .font(.system(size: 28, weight: .bold))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(handicapRounds.count) rounds")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("WHS")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else if !handicapRounds.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HANDICAP INDEX")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text("--")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(handicapRounds.count)/3 rounds to calculate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Resume in-progress
                    if let inProgress = inProgressRound {
                        Button { roundToResume = inProgress } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ROUND IN PROGRESS")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.orange)
                                    Text(inProgress.courseName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Hole \(inProgress.currentHole) · \(inProgress.teeName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(inProgress.holes.reduce(0) { $0 + $1.strokes })")
                                        .font(.title.bold())
                                    Text(inProgress.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    // Start new round
                    Button { showNewRound = true } label: {
                        Text("Start New Round")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // Quick links
                    HStack(spacing: 12) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            QuickLink(icon: "chart.bar.fill", title: "History",
                                      sub: "\(recentCompleted.count) rounds")
                        }
                        NavigationLink {
                            StatsDashboardView()
                        } label: {
                            QuickLink(icon: "chart.line.uptrend.xyaxis", title: "Stats",
                                      sub: "Dashboard")
                        }
                        NavigationLink {
                            BagView()
                        } label: {
                            QuickLink(icon: "bag.fill", title: "My Bag",
                                      sub: "\(bags.first?.clubs.count ?? 0) clubs")
                        }
                    }

                    // Recent rounds
                    if !recentCompleted.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Rounds")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)

                            ForEach(recentCompleted) { round in
                                NavigationLink {
                                    RoundSummaryView(round: round, onDone: {})
                                } label: {
                                    RoundRow(round: round)
                                        .padding(12)
                                        .background(Color(.systemGray6).opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }

                            if allRounds.filter(\.isComplete).count >= 3 {
                                NavigationLink {
                                    YearlyWrappedView(rounds: allRounds.filter(\.isComplete))
                                } label: {
                                    Text("View Season Recap")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.green)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.green.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }

                    // On the Horizon
                    ComingSoonSection()
                }
                .padding()
            }
            .onAppear {
                setupCourseGeofences()
            }
            .onChange(of: locationService.nearbyCourseId) { _, newValue in
                if newValue != nil {
                    geofenceDismissed = false
                }
            }
            .fullScreenCover(isPresented: $showNewRound) {
                RoundView(
                    locationService: locationService,
                    speechService: speechService,
                    shotParser: shotParser,
                    courseSearch: courseSearch,
                    clubRecommender: clubRecommender,
                    weatherService: weatherService,
                    elevationService: elevationService
                )
            }
            .fullScreenCover(item: $roundToResume) { round in
                RoundView(
                    locationService: locationService,
                    speechService: speechService,
                    shotParser: shotParser,
                    courseSearch: courseSearch,
                    clubRecommender: clubRecommender,
                    weatherService: weatherService,
                    elevationService: elevationService,
                    resumeRound: round
                )
            }
        }
    }

    private func setupCourseGeofences() {
        let geofenceInfos: [LocationService.CourseGeofenceInfo] = savedCourses.compactMap { course in
            guard let lat = course.locationLat, let lng = course.locationLng else { return nil }
            return LocationService.CourseGeofenceInfo(
                id: course.id,
                name: course.name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)
            )
        }
        guard !geofenceInfos.isEmpty else { return }
        locationService.requestPermission()
        locationService.startMonitoringCourses(geofenceInfos)
    }
}

struct QuickLink: View {
    let icon: String
    let title: String
    let sub: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
            Text(title).font(.subheadline.bold())
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemGray6).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Coming Soon

private struct ComingSoonFeature: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
}

private let comingSoonFeatures: [ComingSoonFeature] = [
    .init(icon: "list.number", name: "Live Leaderboard"),
    .init(icon: "dollarsign.circle", name: "Skins & Nassau"),
    .init(icon: "person.3.fill", name: "Group Rounds"),
    .init(icon: "figure.golf", name: "Practice Tracker"),
    .init(icon: "target", name: "Goal Setting"),
    .init(icon: "book.closed.fill", name: "Drill Library"),
    .init(icon: "calendar.badge.clock", name: "Season Stats"),
]

struct ComingSoonSection: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On the Horizon")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(comingSoonFeatures) { feature in
                    ComingSoonTile(icon: feature.icon, name: feature.name)
                }
            }
        }
    }
}

private struct ComingSoonTile: View {
    let icon: String
    let name: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color(.systemGray3))
            Text(name)
                .font(.caption.bold())
                .foregroundStyle(Color(.systemGray2))
            Text("Coming Soon")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(.systemGray3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemGray6).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(0.7)
    }
}
