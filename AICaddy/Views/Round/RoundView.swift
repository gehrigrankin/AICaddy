import SwiftUI
import SwiftData
import CoreLocation

struct RoundView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let locationService: LocationService
    let speechService: SpeechService
    let shotParser: ShotParserService
    let courseSearch: CourseSearchService
    let clubRecommender: ClubRecommendationService
    let weatherService: WeatherService
    let elevationService: ElevationService
    var resumeRound: Round? = nil

    private let courseHistory = CourseHistoryService()
    private let courseStrategy = CourseStrategyService()

    @Query(sort: \Course.createdAt, order: .reverse) private var savedCourses: [Course]
    @Query(filter: #Predicate<Round> { $0.isComplete == true }, sort: \Round.date) private var completedRounds: [Round]

    @State private var phase: Phase = .search
    @State private var round: Round?
    @State private var activeCourse: Course?
    @State private var currentHole = 1
    @State private var showScorecard = false
    /// Where the player marked their last shot — sim "drive to ball" target.
    @State private var lastAimTarget: CLLocationCoordinate2D?

    enum Phase { case search, setup, play, summary }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .search:
                    CourseSearchView(
                        courseSearch: courseSearch,
                        locationService: locationService,
                        onCourseLoaded: { course in
                            modelContext.insert(course)
                            activeCourse = course
                            if course.tees.count == 1 {
                                startRound(course: course, teeName: course.tees[0].name)
                            } else {
                                phase = .setup
                            }
                        },
                        onCourseWithTeeLoaded: { course, teeName in
                            modelContext.insert(course)
                            activeCourse = course
                            startRound(course: course, teeName: teeName)
                        },
                        onSkip: { phase = .setup },
                        recentCourses: Array(savedCourses.prefix(5)),
                        onRecentCourseSelected: { course in
                            // Already saved — no re-fetch, keeps user-mapped holes
                            activeCourse = course
                            if course.tees.count == 1 {
                                startRound(course: course, teeName: course.tees[0].name)
                            } else {
                                phase = .setup
                            }
                        }
                    )
                    .navigationTitle("New Round")

                case .setup:
                    CourseSetupView(
                        onComplete: { course, tee in
                            if activeCourse == nil {
                                modelContext.insert(course)
                            }
                            activeCourse = course
                            startRound(course: course, teeName: tee)
                        },
                        existingCourses: {
                            if let ac = activeCourse {
                                return [ac] + savedCourses.filter { $0.id != ac.id }
                            }
                            return savedCourses.map { $0 }
                        }()
                    )
                    .navigationTitle(activeCourse != nil ? "Select Tee" : "New Round")

                case .play:
                    playPhaseView

                case .summary:
                    if let round {
                        RoundSummaryView(
                            round: round,
                            onDone: { dismiss() },
                            onHoleTap: { n in
                                currentHole = n
                                showScorecard = false
                                phase = .play
                            }
                        )
                        .navigationTitle("Summary")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .heavy))
                            Text("HOME")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .tracking(1)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            locationService.startTracking()
            speechService.requestAuthorization()
            clubRecommender.loadHistory(rounds: completedRounds)

            // Resume an in-progress round if provided
            if let resumeRound, !resumeRound.isComplete {
                round = resumeRound
                // Clamp to a hole that actually exists in this round
                let maxHole = resumeRound.holes.map(\.holeNumber).max() ?? 18
                currentHole = min(max(1, resumeRound.currentHole), maxHole)
                // Find the matching course for GPS data
                activeCourse = savedCourses.first { $0.id == resumeRound.courseId }
                phase = .play
            }
        }
        .onDisappear {
            locationService.stopTracking()
            speechService.stopListening()
        }
    }

    // MARK: - Play Phase

    @ViewBuilder
    private var playPhaseView: some View {
        if let round, let _ = currentHoleBinding {
            VStack(spacing: 0) {
                if showScorecard {
                    ScrollView {
                        VStack(spacing: 12) {
                            ScorecardView(
                                holes: round.holes,
                                courseName: round.courseName,
                                teeName: round.teeName,
                                onHoleTap: { n in
                                    currentHole = n
                                    showScorecard = false
                                }
                            )
                            Text("Tap a hole to jump to it")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                } else {
                    HolePlayView(
                        hole: holeBinding,
                        holeGps: currentHoleGps,
                        userLocation: locationService.location,
                        totalScore: round.holes.reduce(0) { $0 + $1.strokes },
                        totalPar: round.holes.filter { $0.strokes > 0 }.reduce(0) { $0 + $1.par },
                        onNext: {
                            if currentHole < lastHoleNumber {
                                currentHole += 1
                                self.round?.currentHole = currentHole
                            } else {
                                finishRound()
                            }
                        },
                        onPrev: {
                            if currentHole > 1 {
                                currentHole -= 1
                                self.round?.currentHole = currentHole
                            }
                        },
                        isFirst: currentHole == 1,
                        isLast: currentHole == lastHoleNumber,
                        speech: speechService,
                        shotParser: shotParser,
                        onHome: { dismiss() },
                        onToggleScorecard: { showScorecard.toggle() },
                        clubRecommendation: currentClubRecommendation,
                        holeTips: currentHoleTips,
                        smartAlert: currentSmartAlert,
                        dangerAlert: currentDangerAlert,
                        windSpeed: weatherService.windSpeed,
                        windDirection: weatherService.windDirectionLabel,
                        windBearing: weatherService.windDirection,
                        temperature: weatherService.temperature,
                        suggestedFairway: suggestedFairway,
                        suggestedGIR: suggestedGIR,
                        caddyTarget: currentSuggestedTarget,
                        courseLocation: courseCenterCoordinate,
                        onAimTargetChanged: { lastAimTarget = $0 },
                        onHoleMapped: { tee, green in
                            saveHoleGps(holeNumber: currentHole, tee: tee, green: green)
                        }
                    )
                    #if DEBUG
                    .overlay(alignment: .top) {
                        DebugLocationBar(
                            locationService: locationService,
                            holeGps: currentHoleGps,
                            courseLocation: courseCenterCoordinate,
                            ballTarget: lastAimTarget ?? currentSuggestedTarget
                        )
                        .padding(.top, 60)
                    }
                    #endif
                }

                #if DEBUG
                if showScorecard {
                    DebugLocationBar(
                        locationService: locationService,
                        holeGps: currentHoleGps,
                        courseLocation: courseCenterCoordinate,
                        ballTarget: lastAimTarget
                    )
                }
                #endif

                if showScorecard {
                    holeDots(round: round)
                }
            }
            .navigationBarHidden(showScorecard == false)
            .navigationTitle(showScorecard ? "SCORECARD" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showScorecard {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showScorecard.toggle()
                        } label: {
                            Text("HOLE")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }
            }
        }
    }

    private func holeDots(round: Round) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(round.holes) { h in
                    Button {
                        currentHole = h.holeNumber
                    } label: {
                        Text("\(h.holeNumber)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(
                                h.holeNumber == currentHole
                                    ? Theme.Colors.backdrop
                                    : (h.strokes > 0 ? Theme.Colors.textPrimary : Theme.Colors.textMuted)
                            )
                            .background(
                                Circle()
                                    .fill(
                                        h.holeNumber == currentHole
                                            ? Theme.Colors.accent
                                            : (h.strokes > 0 ? Theme.Colors.surfaceElevated : Theme.Colors.surface)
                                    )
                            )
                            .overlay(
                                Circle().strokeBorder(Theme.Colors.border, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Theme.Colors.surface.opacity(0.85))
    }

    // MARK: - Hole binding

    private var holeBinding: Binding<HoleScore> {
        Binding(
            get: {
                round?.holes.first { $0.holeNumber == currentHole }
                    ?? HoleScore(holeNumber: currentHole, par: 4)
            },
            set: { newValue in
                guard var holes = round?.holes,
                      let idx = holes.firstIndex(where: { $0.holeNumber == currentHole })
                else { return }
                holes[idx] = newValue
                round?.holes = holes
            }
        )
    }

    private var currentHoleBinding: HoleScore? {
        round?.holes.first { $0.holeNumber == currentHole }
    }

    private var currentHoleGps: HoleGps? {
        // Prefer the tee data stored on the round itself (survives resume when
        // the course lookup fails), then the active course.
        (round?.courseTee ?? activeCourse?.tees.first)?
            .holes.first { $0.holeNumber == currentHole }?.gps
    }

    /// Highest hole number in this round — don't hardcode 18.
    private var lastHoleNumber: Int {
        round?.holes.map(\.holeNumber).max() ?? 18
    }

    /// Course center for map framing / sim fallbacks. Uses the saved course
    /// location, else the first mapped tee of the round.
    private var courseCenterCoordinate: CLLocationCoordinate2D? {
        if let loc = activeCourse?.location {
            return loc.coordinate
        }
        let tee = round?.courseTee ?? activeCourse?.tees.first
        return tee?.holes.compactMap { $0.gps?.tee }.first?.coordinate
    }

    /// Bearing in degrees from one coordinate to another
    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let rad = atan2(y, x)
        return (rad * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Club recommendation based on GPS distance to green center, adjusted for wind, elevation, and temperature
    private var currentClubRecommendation: ClubRecommendation? {
        guard let loc = locationService.location,
              let greenCenter = currentHoleGps?.greenCenter
        else { return nil }
        let rawDist = LocationService.distanceYards(from: loc, to: greenCenter.coordinate)
        // Only recommend for approach shots (not on the green, not teeing off on par 4/5)
        guard rawDist > 30 && rawDist < 300 else { return nil }

        var adjusted = rawDist
        var noteParts: [String] = []

        // Elevation adjustment
        if let elevAdj = elevationService.playsLikeDistance(actualYards: rawDist) {
            let elevDelta = elevAdj - rawDist
            if elevDelta != 0 {
                adjusted += elevDelta
                let direction = elevDelta > 0 ? "uphill" : "downhill"
                noteParts.append("\(abs(elevDelta))y \(direction)")
            }
        }

        // Wind adjustment
        let shotBearing = Self.bearing(from: loc, to: greenCenter.coordinate)
        let windAdj = weatherService.adjustedDistance(yards: rawDist, shotBearing: shotBearing)
        let windDelta = windAdj - rawDist
        if windDelta != 0 {
            adjusted += windDelta
            if windDelta > 0 {
                noteParts.append("\(windDelta)y into wind")
            } else {
                noteParts.append("\(abs(windDelta))y downwind")
            }
        }

        // Temperature adjustment
        let tempAdj = weatherService.temperatureAdjustment(yards: rawDist)
        let tempDelta = tempAdj - rawDist
        if tempDelta != 0 {
            adjusted += tempDelta
            if tempDelta < 0 {
                noteParts.append("\(abs(tempDelta))y cold")
            } else {
                noteParts.append("\(tempDelta)y warm")
            }
        }

        let hasAdjustment = adjusted != rawDist
        let adjustedDistance: Int? = hasAdjustment ? adjusted : nil
        let adjustmentNote: String? = hasAdjustment ? "Plays \(adjusted)y (\(noteParts.joined(separator: ", ")))" : nil

        return clubRecommender.recommend(
            distanceYards: rawDist,
            adjustedDistance: adjustedDistance,
            adjustmentNote: adjustmentNote
        )
    }

    // MARK: - Tips & Alerts

    private var currentHoleTips: [CourseHistoryService.HoleTip] {
        guard let round else { return [] }
        return courseHistory.getTips(courseId: round.courseId, holeNumber: currentHole, rounds: completedRounds)
    }

    private var currentSmartAlert: SmartAlert? {
        guard let round else { return nil }
        // Check momentum first (most actionable during play)
        if let momentum = SmartAlertService.checkMomentum(holes: round.holes, currentHole: currentHole) {
            return momentum
        }
        // Then fatigue
        if let fatigue = SmartAlertService.checkFatigue(holes: round.holes) {
            return fatigue
        }
        // Then milestone
        if let milestone = SmartAlertService.checkMilestone(holes: round.holes, allRounds: completedRounds, courseName: round.courseName) {
            return milestone
        }
        // Then in-round coaching as fallback
        if let coaching = inRoundCoachingAlert {
            return coaching
        }
        return nil
    }

    /// In-round coaching based on current round performance trends
    private var inRoundCoachingAlert: SmartAlert? {
        guard let round, currentHole > 4 else { return nil }
        let holes = round.holes.filter { $0.strokes > 0 }

        // Check 3-putt trend
        let threePutts = holes.filter { ($0.putts ?? 0) >= 3 }.count
        if threePutts >= 2 {
            return SmartAlert(
                message: "2+ three-putts today. Focus on lag putting distance.",
                type: .momentum,
                icon: "circle.fill"
            )
        }

        // Check missed fairways trend
        let fairwayHoles = holes.filter { $0.par >= 4 }
        let missedFairways = fairwayHoles.filter { $0.fairwayHit == false }.count
        if fairwayHoles.count >= 4 && Double(missedFairways) / Double(fairwayHoles.count) > 0.7 {
            return SmartAlert(
                message: "Missing most fairways. Consider dropping to 3-wood off the tee.",
                type: .momentum,
                icon: "arrow.left.arrow.right"
            )
        }

        return nil
    }

    private var currentDangerAlert: DangerZoneAlert? {
        guard let holeGps = currentHoleGps else { return nil }
        let distToGreen: Int
        if let loc = locationService.location, let gc = holeGps.greenCenter {
            distToGreen = LocationService.distanceYards(from: loc, to: gc.coordinate)
        } else if let yardage = round?.holes.first(where: { $0.holeNumber == currentHole })?.yardage {
            distToGreen = yardage
        } else {
            return nil
        }
        let driverAvg = clubRecommender.clubAverages.first(where: { $0.club == .driver })?.avg
        return courseStrategy.checkDangerZones(
            distanceToGreen: distToGreen,
            holeGps: holeGps,
            clubAvgDistance: driverAvg
        )
    }

    // MARK: - Auto Stat Suggestions

    private var suggestedFairway: Bool? {
        guard let loc = locationService.location,
              let gps = currentHoleGps,
              let holeScore = round?.holes.first(where: { $0.holeNumber == currentHole }),
              holeScore.shots.count >= 1  // At least one shot taken (tee shot)
        else { return nil }
        return AutoStatDetectionService.detectFairwayHit(
            userLocation: loc,
            holeGps: gps,
            par: holeScore.par
        )
    }

    private var suggestedGIR: Bool? {
        guard let loc = locationService.location,
              let gps = currentHoleGps,
              let holeScore = round?.holes.first(where: { $0.holeNumber == currentHole }),
              holeScore.strokes > 0
        else { return nil }
        return AutoStatDetectionService.detectGreenInRegulation(
            userLocation: loc,
            holeGps: gps,
            strokesUsed: holeScore.strokes,
            par: holeScore.par
        )
    }

    /// AI caddy suggested target: where to aim the tee shot on par 4/5s
    private var currentSuggestedTarget: CLLocationCoordinate2D? {
        guard let gps = currentHoleGps,
              let tee = gps.tee,
              let holeScore = round?.holes.first(where: { $0.holeNumber == currentHole })
        else { return nil }

        // Only suggest before first shot (tee shot planning)
        guard holeScore.shots.isEmpty else { return nil }

        // Always calculate from the tee box, not user's GPS position
        let bags = (try? modelContext.fetch(FetchDescriptor<GolfBag>()))?.first?.clubs ?? []
        let result = courseStrategy.suggestedTarget(
            userLocation: tee.coordinate,
            holeGps: gps,
            par: holeScore.par,
            clubAverages: clubRecommender.clubAverages,
            bagClubs: bags
        )
        return result?.coordinate
    }

    // MARK: - Actions

    private func startRound(course: Course, teeName: String) {
        guard let tee = course.tees.first(where: { $0.name == teeName }) ?? course.tees.first else { return }

        let holes = tee.holes.map { h in
            HoleScore(holeNumber: h.holeNumber, par: h.par, yardage: h.yardage)
        }

        let newRound = Round(
            courseId: course.id,
            courseName: course.name,
            teeName: tee.name,
            holes: holes,
            courseTee: tee
        )

        modelContext.insert(newRound)
        round = newRound
        currentHole = 1
        phase = .play

        // Fetch weather and elevation data for adjustments
        if let loc = locationService.location {
            let coord = loc
            Task {
                await weatherService.fetchWeather(at: coord)
            }
            elevationService.updateElevation(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
        }
    }

    private func finishRound() {
        round?.isComplete = true
        phase = .summary
    }

    /// Save a user-mapped tee/green for a hole OSM has no data for.
    /// Persists to the course (future rounds) AND the round's stored tee
    /// (this round), and fills in the hole yardage.
    private func saveHoleGps(holeNumber: Int, tee: CLLocationCoordinate2D, green: CLLocationCoordinate2D) {
        let newGps = HoleGps(
            tee: GpsPoint(coordinate: tee),
            greenCenter: GpsPoint(coordinate: green),
            greenFront: nil,
            greenBack: nil,
            fairwayCenter: nil,
            fairwayPath: nil,
            hazards: nil
        )
        let yardage = LocationService.distanceYards(from: tee, to: green)

        // Course model — persists for every future round here
        if let course = activeCourse {
            var tees = course.tees
            for i in tees.indices {
                if let h = tees[i].holes.firstIndex(where: { $0.holeNumber == holeNumber }) {
                    tees[i].holes[h].gps = newGps
                    if tees[i].holes[h].yardage == nil {
                        tees[i].holes[h].yardage = yardage
                    }
                }
            }
            course.tees = tees
        }

        // Round's stored tee — what this round reads GPS from
        if let r = round, var storedTee = r.courseTee {
            if let h = storedTee.holes.firstIndex(where: { $0.holeNumber == holeNumber }) {
                storedTee.holes[h].gps = newGps
                if storedTee.holes[h].yardage == nil {
                    storedTee.holes[h].yardage = yardage
                }
                r.courseTee = storedTee
            }
        }

        // The scorecard's hole yardage
        if let r = round {
            var holes = r.holes
            if let h = holes.firstIndex(where: { $0.holeNumber == holeNumber }), holes[h].yardage == nil {
                holes[h].yardage = yardage
                r.holes = holes
            }
        }
    }
}
