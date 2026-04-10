import SwiftUI
import SwiftData
import CoreLocation

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Round.date, order: .reverse) private var allRounds: [Round]
    @Query(sort: \Course.createdAt, order: .reverse) private var savedCourses: [Course]
    @Query private var bags: [GolfBag]
    @State private var showNewRound = false
    @State private var roundToResume: Round?
    @State private var geofenceDismissed = false
    @State private var showStopConfirm = false

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

    private var avgScore: Int? {
        let completed = allRounds.filter { $0.isComplete }
        guard !completed.isEmpty else { return nil }
        let total = completed.reduce(0) { $0 + $1.holes.reduce(0) { $0 + $1.strokes } }
        return total / completed.count
    }

    private var bestScore: Int? {
        allRounds.filter(\.isComplete)
            .map { $0.holes.reduce(0) { $0 + $1.strokes } }
            .filter { $0 > 0 }
            .min()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Caddy")
                                .font(.system(size: 28, weight: .heavy))
                            Text("Your intelligent golf companion")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink {
                            BagView()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 13))
                                Text("My Bag")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 8)

                    // Geofence banner
                    if let courseName = locationService.nearbyCourseName, !geofenceDismissed {
                        Button {
                            showNewRound = true
                            geofenceDismissed = true
                            locationService.dismissNearbyCourse()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.green)
                                    .frame(width: 32, height: 32)
                                    .background(.green.opacity(0.15))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(courseName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text("Tap to start your round")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.green.opacity(0.2), lineWidth: 1))
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                geofenceDismissed = true
                                locationService.dismissNearbyCourse()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                            }
                        }
                    }

                    // Resume round (prominent)
                    if let inProgress = inProgressRound {
                        Button { roundToResume = inProgress } label: {
                            HStack(spacing: 14) {
                                let score = inProgress.holes.reduce(0) { $0 + $1.strokes }
                                ZStack {
                                    Circle()
                                        .stroke(.orange.opacity(0.3), lineWidth: 3)
                                        .frame(width: 52, height: 52)
                                    Text("\(score)")
                                        .font(.system(size: 22, weight: .heavy))
                                        .foregroundStyle(.orange)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(inProgress.courseName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text("Hole \(inProgress.currentHole)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.orange)
                                        Text("·")
                                            .foregroundStyle(.tertiary)
                                        Text(inProgress.teeName)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text("Resume")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.orange.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            .padding(14)
                            .background(Color(.systemGray6).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .overlay(alignment: .topTrailing) {
                            Button { showStopConfirm = true } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 22, height: 22)
                                    .background(Color(.systemGray3))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                            }
                            .offset(x: 8, y: -8)
                        }
                        .confirmationDialog(
                            "End this round?",
                            isPresented: $showStopConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("End & Save", role: .destructive) {
                                inProgress.isComplete = true
                            }
                            Button("Delete Round", role: .destructive) {
                                modelContext.delete(inProgress)
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("You're on hole \(inProgress.currentHole) at \(inProgress.courseName).")
                        }
                    }

                    // Start round CTA
                    Button { showNewRound = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Start New Round")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.7, blue: 0.3), Color(red: 0.15, green: 0.55, blue: 0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                    }

                    // Stats at a glance
                    HStack(spacing: 10) {
                        HomeStatCard(
                            label: "HANDICAP",
                            value: calculatedHandicap.map { String(format: "%.1f", $0) } ?? "--",
                            sub: handicapRounds.isEmpty ? nil : (calculatedHandicap != nil ? "WHS" : "\(handicapRounds.count)/3"),
                            color: .green
                        )
                        HomeStatCard(
                            label: "AVG SCORE",
                            value: avgScore.map { "\($0)" } ?? "--",
                            sub: allRounds.filter(\.isComplete).isEmpty ? nil : "\(allRounds.filter(\.isComplete).count) rounds",
                            color: .cyan
                        )
                        HomeStatCard(
                            label: "BEST",
                            value: bestScore.map { "\($0)" } ?? "--",
                            sub: nil,
                            color: .yellow
                        )
                    }

                    // Quick links row
                    HStack(spacing: 10) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            QuickLink(icon: "clock.arrow.circlepath", title: "History",
                                      sub: "\(allRounds.filter(\.isComplete).count)")
                        }
                        NavigationLink {
                            StatsDashboardView()
                        } label: {
                            QuickLink(icon: "chart.xyaxis.line", title: "Stats",
                                      sub: "Analysis")
                        }
                    }

                    // Recent rounds
                    if !recentCompleted.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Recent Rounds")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                NavigationLink {
                                    HistoryView()
                                } label: {
                                    Text("See All")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.green)
                                }
                            }

                            ForEach(recentCompleted.prefix(3)) { round in
                                NavigationLink {
                                    RoundSummaryView(round: round, onDone: {})
                                } label: {
                                    RoundRow(round: round)
                                        .padding(10)
                                        .background(Color(.systemGray6).opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }

                            if allRounds.filter(\.isComplete).count >= 3 {
                                NavigationLink {
                                    YearlyWrappedView(rounds: allRounds.filter(\.isComplete))
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 13))
                                        Text("Season Recap")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundStyle(.green)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.green.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }

                    // Coming soon (minimal)
                    ComingSoonSection()
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
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

// MARK: - Stat Card

private struct HomeStatCard: View {
    let label: String
    let value: String
    let sub: String?
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(color.opacity(0.6))
                .tracking(0.5)
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            if let sub {
                Text(sub)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct QuickLink: View {
    let icon: String
    let title: String
    let sub: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 34, height: 34)
                .background(.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Coming Soon

struct ComingSoonSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMING SOON")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.tertiary)
                .tracking(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Live Leaderboard", "Skins & Nassau", "Group Rounds", "Practice Tracker"], id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(.systemGray3))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6).opacity(0.3))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
