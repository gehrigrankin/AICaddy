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

    private var completedRounds: [Round] {
        allRounds.filter(\.isComplete)
    }

    private var handicapRounds: [HandicapRound] {
        completedRounds
            .sorted { $0.date > $1.date }
            .prefix(20)
            .compactMap { HandicapRound.fromRound($0) }
    }

    private var calculatedHandicap: Double? {
        HandicapCalculator.calculateIndex(rounds: handicapRounds)
    }

    private var avgScore: Int? {
        guard !completedRounds.isEmpty else { return nil }
        let total = completedRounds.reduce(0) { $0 + $1.holes.reduce(0) { $0 + $1.strokes } }
        return total / completedRounds.count
    }

    private var bestScore: Int? {
        completedRounds
            .map { $0.holes.reduce(0) { $0 + $1.strokes } }
            .filter { $0 > 0 }
            .min()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                            .padding(.top, 12)

                        if let courseName = locationService.nearbyCourseName, !geofenceDismissed {
                            geofenceBanner(courseName: courseName)
                        }

                        if let inProgress = inProgressRound {
                            resumeCard(inProgress: inProgress)
                        }

                        teeOffButton

                        careerStatsRow

                        menuGrid

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            }
            .onAppear { setupCourseGeofences() }
            .onChange(of: locationService.nearbyCourseId) { _, newValue in
                if newValue != nil { geofenceDismissed = false }
            }
            .fullScreenCover(isPresented: $showNewRound) { roundCover(resume: nil) }
            .fullScreenCover(item: $roundToResume) { roundCover(resume: $0) }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Theme.Colors.backdrop, Theme.Colors.surfaceDeep, Theme.Colors.backdrop],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI CADDY")
                    .font(Theme.Font.display(28))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(2)
                Text("MAIN MENU")
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(3)
            }
            Spacer()
            Image(systemName: "figure.golf")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(Theme.Colors.surfaceElevated)
                )
                .overlay(Circle().strokeBorder(Theme.Colors.border, lineWidth: 1))
        }
    }

    // MARK: - Geofence banner

    private func geofenceBanner(courseName: String) -> some View {
        Button {
            showNewRound = true
            geofenceDismissed = true
            locationService.dismissNearbyCourse()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.Colors.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(courseName.uppercased())
                        .font(Theme.Font.label(13))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(0.5)
                    Text("Tap to tee off")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .gameCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Resume card

    private func resumeCard(inProgress: Round) -> some View {
        let score = inProgress.holes.reduce(0) { $0 + $1.strokes }
        return Button { roundToResume = inProgress } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Theme.Colors.accent.opacity(0.35), lineWidth: 3)
                        .frame(width: 56, height: 56)
                    Text("\(score)")
                        .font(Theme.Font.display(22))
                        .foregroundStyle(Theme.Colors.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("ROUND IN PROGRESS")
                        .font(Theme.Font.caption(9))
                        .foregroundStyle(Theme.Colors.accent)
                        .tracking(1.2)
                    Text(inProgress.courseName)
                        .font(Theme.Font.title(16))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("HOLE \(inProgress.currentHole)")
                            .font(Theme.Font.caption(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("·")
                            .foregroundStyle(Theme.Colors.textMuted)
                        Text(inProgress.teeName.uppercased())
                            .font(Theme.Font.caption(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
                Text("RESUME")
                    .font(Theme.Font.label(11))
                    .tracking(1)
                    .foregroundStyle(Theme.Colors.backdrop)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.Colors.accent))
            }
            .gameCard()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button { showStopConfirm = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.Colors.surfaceElevated))
                    .overlay(Circle().strokeBorder(Theme.Colors.border, lineWidth: 1))
            }
            .offset(x: 6, y: -6)
        }
        .confirmationDialog(
            "End this round?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("End & Save", role: .destructive) { inProgress.isComplete = true }
            Button("Delete Round", role: .destructive) { modelContext.delete(inProgress) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You're on hole \(inProgress.currentHole) at \(inProgress.courseName).")
        }
    }

    // MARK: - Tee off CTA

    private var teeOffButton: some View {
        Button { showNewRound = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.Colors.backdrop)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TEE OFF")
                        .font(Theme.Font.display(26))
                        .foregroundStyle(Theme.Colors.backdrop)
                        .tracking(2)
                    Text("START A NEW ROUND")
                        .font(Theme.Font.caption(10))
                        .foregroundStyle(Theme.Colors.backdrop.opacity(0.65))
                        .tracking(1.5)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.Colors.backdrop.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Colors.accent, Color(red: 0.98, green: 0.67, blue: 0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .themeShadow(ShadowStyle(color: Theme.Colors.accent.opacity(0.35), radius: 18, x: 0, y: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Career stats row

    private var careerStatsRow: some View {
        HStack(spacing: 10) {
            CareerStat(label: "HANDICAP",
                       value: calculatedHandicap.map { String(format: "%.1f", $0) } ?? "--")
            CareerStat(label: "AVG",
                       value: avgScore.map { "\($0)" } ?? "--")
            CareerStat(label: "BEST",
                       value: bestScore.map { "\($0)" } ?? "--")
            CareerStat(label: "ROUNDS",
                       value: "\(completedRounds.count)")
        }
    }

    // MARK: - Menu grid

    private var menuGrid: some View {
        VStack(spacing: 10) {
            NavigationLink {
                BagView()
            } label: {
                MenuRow(icon: "bag.fill", title: "MY BAG", subtitle: "LOADOUT & YARDAGES")
            }
            .buttonStyle(.plain)

            NavigationLink {
                StatsDashboardView()
            } label: {
                MenuRow(icon: "chart.xyaxis.line", title: "STATS", subtitle: "CAREER ANALYTICS")
            }
            .buttonStyle(.plain)

            NavigationLink {
                HistoryView()
            } label: {
                MenuRow(icon: "clock.arrow.circlepath", title: "HISTORY", subtitle: "\(completedRounds.count) ROUNDS PLAYED")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Round cover

    @ViewBuilder
    private func roundCover(resume: Round?) -> some View {
        if let resume {
            RoundView(
                locationService: locationService,
                speechService: speechService,
                shotParser: shotParser,
                courseSearch: courseSearch,
                clubRecommender: clubRecommender,
                weatherService: weatherService,
                elevationService: elevationService,
                resumeRound: resume
            )
        } else {
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

// MARK: - Career stat

private struct CareerStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(1)
            Text(value)
                .font(Theme.Font.display(22))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Menu row

private struct MenuRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .fill(Theme.Colors.accentSoft)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.title(15))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(1)
                Text(subtitle)
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .tracking(0.8)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.Colors.textMuted)
        }
        .gameCard()
    }
}
