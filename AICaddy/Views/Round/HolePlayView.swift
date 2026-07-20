import SwiftUI
import SwiftData
import CoreLocation

enum PanelHeight: Int, CaseIterable {
    case collapsed = 0
    case simple = 1
    case full = 2

    var next: PanelHeight {
        PanelHeight(rawValue: (rawValue + 1) % 3) ?? .collapsed
    }
    var prev: PanelHeight {
        PanelHeight(rawValue: (rawValue + 2) % 3) ?? .collapsed
    }
}

struct HolePlayView: View {
    @Binding var hole: HoleScore
    let holeGps: HoleGps?
    let userLocation: CLLocationCoordinate2D?
    let totalScore: Int
    let totalPar: Int
    let onNext: () -> Void
    let onPrev: () -> Void
    let isFirst: Bool
    let isLast: Bool

    @State private var parsing = false
    @State private var lastParse = ""
    @State private var panelHeight: PanelHeight = .simple
    @State private var showNotesSheet = false
    @State private var notesDraft = ""
    @State private var showClubPicker = false
    @State private var draggedCaddyTarget: CLLocationCoordinate2D?
    @State private var showCompletionSheet = false
    @State private var sheetStrokes: Int = 0
    @State private var sheetPutts: Int = 2
    @State private var sheetCustomScore: String = ""
    @State private var sheetMode: CompletionSheetMode = .both
    @State private var selectedClub: Club?
    @State private var panelDragOffset: CGFloat = 0

    @Query private var bags: [GolfBag]
    private var bagClubs: [BagClub] { bags.first?.clubs ?? [] }

    enum CompletionSheetMode {
        case both      // missing strokes (and putts)
        case puttsOnly // strokes entered, putts missing
    }

    @Bindable var speech: SpeechService
    let shotParser: ShotParserService
    var onHome: (() -> Void)? = nil
    var onToggleScorecard: (() -> Void)? = nil
    var clubRecommendation: ClubRecommendation?
    var holeTips: [CourseHistoryService.HoleTip] = []
    var smartAlert: SmartAlert? = nil
    var dangerAlert: DangerZoneAlert? = nil
    var windSpeed: Double? = nil
    var windDirection: String? = nil
    var windBearing: Double? = nil
    var temperature: Int? = nil
    var suggestedFairway: Bool? = nil
    var suggestedGIR: Bool? = nil
    var caddyTarget: CLLocationCoordinate2D? = nil
    /// Course center for map framing when the hole has no GPS data.
    var courseLocation: CLLocationCoordinate2D? = nil
    /// Reports where the player marked their shot (dragged aim target) —
    /// lets the debug sim "drive to the ball".
    var onAimTargetChanged: ((CLLocationCoordinate2D?) -> Void)? = nil
    /// Saves user-mapped tee/green for holes OSM has no data for.
    var onHoleMapped: ((CLLocationCoordinate2D, CLLocationCoordinate2D) -> Void)? = nil

    // Hole-mapping flow (tap tee, tap green)
    @State private var isMappingHole = false
    @State private var mappedTee: CLLocationCoordinate2D?

    @State private var showTipsSheet = false
    @State private var smartAlertDismissed = false
    @State private var fairwayManuallySet = false
    @State private var girManuallySet = false

    private var runningToPar: Int { totalScore - totalPar }
    private var holesPlayed: Int { hole.holeNumber - 1 }

    /// Where distances measure from. Follows the player as they move — the
    /// old "tee until a shot is logged" rule froze every yardage at the tee
    /// number for players who don't log shots immediately.
    private var distanceMeasurePoint: CLLocationCoordinate2D? {
        guard let loc = userLocation else {
            return holeGps?.tee?.coordinate
        }

        if let tee = holeGps?.tee {
            let distFromTee = LocationService.distanceYards(from: loc, to: tee.coordinate)

            // Standing on/near the tee box: snap to the tee for clean planning numbers
            if hole.shots.isEmpty && distFromTee < 30 {
                return tee.coordinate
            }

            // GPS nowhere near this hole (previewing from home): measure from the tee
            if let green = holeGps?.greenCenter {
                let distFromGreen = LocationService.distanceYards(from: loc, to: green.coordinate)
                if min(distFromTee, distFromGreen) > 1100 {
                    return tee.coordinate
                }
            }
        }

        return loc
    }

    /// Distance (yards) from the current origin to the green center.
    private var yardsToGreen: Int? {
        guard let origin = distanceMeasurePoint,
              let green = holeGps?.greenCenter else { return nil }
        return LocationService.distanceYards(from: origin, to: green.coordinate)
    }

    /// Pick the bag club whose effective yardage gets closest to the pin (ties → longer club).
    /// Falls back to the longest club overall if yardages or green data are missing.
    private func defaultClubForDistance() -> Club? {
        let candidates = (bagClubs.isEmpty ? BagClub.defaultBag : bagClubs)
            .compactMap { bc -> (Club, Int)? in
                guard let y = bc.effectiveYardage, y > 0 else { return nil }
                return (bc.club, y)
            }
        guard !candidates.isEmpty else { return nil }

        if let target = yardsToGreen {
            return candidates.min { a, b in
                let da = abs(a.1 - target)
                let db = abs(b.1 - target)
                if da != db { return da < db }
                return a.1 > b.1
            }?.0
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    /// Target coordinate when a club is actively aimed. Placed along the fairway
    /// centerline at the selected club's distance from the origin.
    private var aimedClubTarget: CLLocationCoordinate2D? {
        guard let club = selectedClub,
              let gps = holeGps,
              let origin = distanceMeasurePoint,
              let bag = bagClubs.first(where: { $0.club == club }),
              let yards = bag.effectiveYardage else {
            return nil
        }
        return CourseStrategyService.interpolateAlongFairway(
            from: origin,
            holeGps: gps,
            targetDistance: yards
        )
    }

    /// Effective caddy target shown on the map. Priority:
    /// user-dragged override → aimed club position → AI caddy suggestion.
    private var effectiveCaddyTarget: CLLocationCoordinate2D? {
        draggedCaddyTarget ?? aimedClubTarget ?? caddyTarget
    }

    /// Label shown on the aim card: selected club name if aiming, else nil (annotation falls back to "AIM HERE").
    private var effectiveCaddyLabel: String? {
        selectedClub?.displayName
    }

    var body: some View {
        ZStack {
            // MARK: Full-screen map background (always show, even without hole GPS)
            HoleMapView(
                holeGps: holeGps,
                holeNumber: hole.holeNumber,
                par: hole.par,
                userLocation: userLocation,
                distanceMeasurePoint: distanceMeasurePoint,
                courseLocation: courseLocation,
                caddyTarget: holeGps != nil ? effectiveCaddyTarget : nil,
                caddyTargetLabel: holeGps != nil ? effectiveCaddyLabel : nil,
                onCaddyTargetDragged: { coord in
                    draggedCaddyTarget = coord
                    onAimTargetChanged?(coord)
                },
                isMappingMode: isMappingHole,
                onMapTap: handleMappingTap,
                mappingPreviewTee: isMappingHole ? mappedTee : nil,
                onTargetPlaced: { coord in
                    // The long-press marker doubles as "my ball is here"
                    onAimTargetChanged?(coord)
                }
            )
            .ignoresSafeArea()

            // MARK: Overlay UI
            VStack(spacing: 0) {
                // Top overlay: hole info
                topOverlay
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                // Hole-mapping: OSM has no data for many courses — let the
                // player map the hole in two taps (tee, then green).
                if isMappingHole {
                    mappingBanner
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                } else if holeGps?.tee == nil || holeGps?.greenCenter == nil {
                    mapThisHoleButton
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                // Smart alert banner (dismissible)
                if let alert = smartAlert, !smartAlertDismissed {
                    smartAlertBanner(alert)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Floating club selector — above the bottom panel, leading edge
                HStack {
                    clubSelectButton
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                // Bottom panel
                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            .onChange(of: hole.holeNumber) { _, _ in
                smartAlertDismissed = false
                fairwayManuallySet = false
                girManuallySet = false
                draggedCaddyTarget = nil
                onAimTargetChanged?(nil)
                selectedClub = defaultClubForDistance()
                isMappingHole = false
                mappedTee = nil
            }
            .onChange(of: selectedClub) { _, _ in
                draggedCaddyTarget = nil
            }
            .onAppear {
                if selectedClub == nil {
                    selectedClub = defaultClubForDistance()
                }
            }
            .onChange(of: holeGps?.tee?.lat) { _, _ in
                if selectedClub == nil {
                    selectedClub = defaultClubForDistance()
                }
            }
            .onChange(of: suggestedFairway) { _, newValue in
                if !fairwayManuallySet, let val = newValue, hole.fairwayHit == nil {
                    hole.fairwayHit = val
                }
            }
            .onChange(of: suggestedGIR) { _, newValue in
                if !girManuallySet, let val = newValue, hole.greenInRegulation == nil {
                    hole.greenInRegulation = val
                }
            }
        }
        .sheet(isPresented: $showCompletionSheet) {
            completionSheet
        }
    }

    // MARK: - Hole Mapping (tap tee, tap green)

    private var mapThisHoleButton: some View {
        Button {
            isMappingHole = true
            mappedTee = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .heavy))
                Text("MAP THIS HOLE")
                    .font(Theme.Font.title(12))
                    .tracking(1)
            }
            .foregroundStyle(Theme.Colors.backdrop)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.Colors.accent))
            .themeShadow(ShadowStyle(color: Theme.Colors.accent.opacity(0.35), radius: 10, x: 0, y: 4))
        }
    }

    private var mappingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: mappedTee == nil ? "figure.golf" : "flag.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.Colors.accent)
            Text(mappedTee == nil ? "TAP THE TEE BOX" : "NOW TAP THE GREEN")
                .font(Theme.Font.title(13))
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(1)
            Spacer()
            Button {
                isMappingHole = false
                mappedTee = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Colors.accent.opacity(0.5), lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.pill)
    }

    private func handleMappingTap(_ coordinate: CLLocationCoordinate2D) {
        if mappedTee == nil {
            mappedTee = coordinate
        } else if let tee = mappedTee {
            isMappingHole = false
            mappedTee = nil
            onHoleMapped?(tee, coordinate)
        }
    }

    // MARK: - Top Overlay

    private var scoreBadge: String {
        if runningToPar == 0 { return "E" }
        return runningToPar > 0 ? "+\(runningToPar)" : "\(runningToPar)"
    }

    private var scoreColor: Color {
        if runningToPar < 0 { return Theme.Colors.positive }
        if runningToPar > 0 { return Theme.Colors.negative }
        return Theme.Colors.textPrimary
    }

    private var topOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                playerCard
                Spacer(minLength: 0)
                WindCompass(
                    speedMph: windSpeed,
                    fromDegrees: windBearing
                )
                if !holeTips.isEmpty || dangerAlert != nil {
                    tipsButton
                }
                scorecardButton
            }

            if let gps = holeGps, let loc = distanceMeasurePoint {
                HStack {
                    distanceCard(userLocation: loc, gps: gps)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var scorecardButton: some View {
        Button { onToggleScorecard?() } label: {
            VStack(spacing: 2) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.Colors.backdrop)
                Text("CARD")
                    .font(Theme.Font.caption(9))
                    .foregroundStyle(Theme.Colors.backdrop)
                    .tracking(1)
            }
            .frame(width: 56, height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Colors.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.Colors.accent, lineWidth: 1)
            )
            .themeShadow(ShadowStyle(color: Theme.Colors.accent.opacity(0.35), radius: 10, x: 0, y: 4))
        }
    }

    private var playerCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("H\(hole.holeNumber) · PAR \(hole.par)")
                    .font(Theme.Font.title(13))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.5)
                if let y = hole.yardage {
                    Text("\(y)Y")
                        .font(Theme.Font.caption(10))
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            Rectangle()
                .fill(Theme.Colors.divider)
                .frame(width: 1, height: 28)
            Text(scoreBadge)
                .font(Theme.Font.display(20))
                .foregroundStyle(scoreColor)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.pill)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tipsButton: some View {
        Button { showTipsSheet = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                            .fill(Theme.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                            .strokeBorder(Theme.Colors.border, lineWidth: 1)
                    )
                    .themeShadow(Theme.Shadow.pill)
                if dangerAlert != nil {
                    Circle()
                        .fill(Theme.Colors.negative)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Theme.Colors.surface, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }
        }
        .sheet(isPresented: $showTipsSheet) { tipsSheet }
    }

    private func distanceCard(userLocation loc: CLLocationCoordinate2D, gps: HoleGps) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if let front = gps.greenFront {
                let d = LocationService.distanceYards(from: loc, to: front.coordinate)
                smallDistanceTile(label: "F", yards: d, accent: Theme.Colors.positive)
            }
            if let center = gps.greenCenter {
                let d = LocationService.distanceYards(from: loc, to: center.coordinate)
                pinDistanceTile(yards: d)
            }
            if let back = gps.greenBack {
                let d = LocationService.distanceYards(from: loc, to: back.coordinate)
                smallDistanceTile(label: "B", yards: d, accent: Theme.Colors.negative)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.pill)
    }

    private func pinDistanceTile(yards: Int) -> some View {
        VStack(spacing: -1) {
            Text("yds to pin")
                .font(Theme.Font.caption(8))
                .foregroundStyle(Theme.Colors.textMuted)
            Text("\(yards)")
                .font(Theme.Font.display(17))
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.numericText())
        }
    }

    private func smallDistanceTile(label: String, yards: Int, accent: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(yards)")
                .font(Theme.Font.display(11))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.Font.caption(7))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.5)
        }
    }

    // MARK: - Smart Alert Banner

    private func smartAlertBanner(_ alert: SmartAlert) -> some View {
        HStack(spacing: 8) {
            Image(systemName: alert.icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(smartAlertColor(for: alert.type))
            Text(alert.message.uppercased())
                .font(Theme.Font.caption(10))
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(0.5)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { smartAlertDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(smartAlertColor(for: alert.type).opacity(0.5), lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.pill)
    }

    private func smartAlertColor(for type: SmartAlert.AlertType) -> Color {
        switch type {
        case .momentum: return Theme.Colors.accent
        case .pace: return Theme.Colors.accent
        case .fatigue: return Theme.Colors.textSecondary
        case .milestone: return Theme.Colors.positive
        case .weather: return Theme.Colors.textSecondary
        }
    }

    // MARK: - Tips Sheet

    private var tipsSheet: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backdrop.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let danger = dangerAlert {
                            tipSection(title: "DANGER ZONE", color: Theme.Colors.negative) {
                                tipRow(
                                    icon: "exclamationmark.triangle.fill",
                                    iconColor: danger.severity == .high ? Theme.Colors.negative : Theme.Colors.accent,
                                    message: danger.message
                                )
                            }
                        }
                        if !holeTips.isEmpty {
                            tipSection(title: "HOLE TIPS", color: Theme.Colors.accent) {
                                ForEach(holeTips) { tip in
                                    tipRow(
                                        icon: tipIcon(for: tip.type),
                                        iconColor: tipColor(for: tip.type),
                                        message: tip.message
                                    )
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("HOLE \(hole.holeNumber) TIPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showTipsSheet = false
                    } label: {
                        Text("DONE")
                            .font(Theme.Font.caption(12))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(1)
                    }
                }
            }
            .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func tipSection<Content: View>(title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Font.caption(10))
                .foregroundStyle(color)
                .tracking(1.2)
            content()
        }
    }

    private func tipRow(icon: String, iconColor: Color, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                )
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
    }

    private func tipIcon(for type: CourseHistoryService.TipType) -> String {
        switch type {
        case .noteFromPast: return "note.text"
        case .missTendency: return "arrow.left.arrow.right"
        case .scoringPattern: return "chart.bar.fill"
        case .strategy: return "flag.fill"
        }
    }

    private func tipColor(for type: CourseHistoryService.TipType) -> Color {
        switch type {
        case .noteFromPast: return Theme.Colors.textSecondary
        case .missTendency: return Theme.Colors.negative
        case .scoringPattern: return Theme.Colors.accent
        case .strategy: return Theme.Colors.positive
        }
    }

    // MARK: - Bottom Panel (3 heights)

    @ViewBuilder
    private var bottomPanel: some View {
        switch panelHeight {
        case .collapsed:
            collapsedPanel
        case .simple:
            simplePanel
        case .full:
            fullPanel
        }
    }

    // MARK: Collapsed — thin bar with score + hole info

    private var collapsedPanel: some View {
        VStack(spacing: 0) {
            panelDragHandle
            HStack(spacing: 12) {
                ScoreCircle(strokes: hole.strokes, par: hole.par, size: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("HOLE \(hole.holeNumber)")
                        .font(Theme.Font.title(13))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(0.8)
                    if hole.strokes > 0 {
                        Text(hole.scoreLabel.uppercased())
                            .font(Theme.Font.caption(10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    stepperButton(icon: "minus") { adjustStrokes(-1) }
                    stepperButton(icon: "plus") { adjustStrokes(1) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.card)
        .gesture(panelDragGesture(current: .collapsed))
        .sensoryFeedback(.impact(weight: .light), trigger: hole.strokes)
    }

    private func stepperButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.Colors.surfaceElevated))
                .overlay(Circle().strokeBorder(Theme.Colors.border, lineWidth: 1))
        }
    }

    // MARK: Simple — score +/-, stats, quick buttons, mic + next hole

    private var simplePanel: some View {
        VStack(spacing: 10) {
            panelDragHandle

            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    Button { startVoiceInput() } label: {
                        Image(systemName: speech.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(speech.isListening ? Theme.Colors.accent : Theme.Colors.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.Colors.surfaceElevated))
                            .overlay(Circle().strokeBorder(Theme.Colors.border, lineWidth: 1))
                    }
                    Button {
                        notesDraft = hole.notes ?? ""
                        showNotesSheet = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "note.text")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Theme.Colors.surfaceElevated))
                                .overlay(Circle().strokeBorder(Theme.Colors.border, lineWidth: 1))
                            if hole.notes != nil && !(hole.notes?.isEmpty ?? true) {
                                Circle().fill(Theme.Colors.accent).frame(width: 6, height: 6).offset(x: 1, y: -1)
                            }
                        }
                    }
                }
                .frame(width: 40)

                Spacer()

                HStack(spacing: 14) {
                    Button { adjustStrokes(-1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Theme.Colors.surfaceElevated))
                            .overlay(Circle().strokeBorder(Theme.Colors.border, lineWidth: 1))
                    }

                    VStack(spacing: 2) {
                        ScoreCircle(strokes: hole.strokes, par: hole.par, size: 60)
                        if hole.strokes > 0 {
                            Text(hole.scoreLabel.uppercased())
                                .font(Theme.Font.caption(9))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .tracking(0.8)
                        }
                    }

                    Button { adjustStrokes(1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Theme.Colors.surfaceElevated))
                            .overlay(Circle().strokeBorder(Theme.Colors.border, lineWidth: 1))
                    }
                }

                Spacer()

                Button { attemptNextHole() } label: {
                    Image(systemName: isLast ? "flag.checkered" : "forward.fill")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.Colors.backdrop)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.Colors.accent))
                        .themeShadow(ShadowStyle(color: Theme.Colors.accent.opacity(0.35), radius: 10, x: 0, y: 4))
                }
                .frame(width: 44)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hole.strokes)

            if parsing {
                Text("PROCESSING...")
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1)
            } else if !lastParse.isEmpty {
                Text(lastParse)
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.card)
        .offset(y: max(0, panelDragOffset))
        .gesture(panelDragGesture(current: .simple))
        .sheet(isPresented: $showNotesSheet) {
            HoleNotesSheet(
                holeNumber: hole.holeNumber,
                notesDraft: $notesDraft,
                speech: speech,
                onSave: {
                    hole.notes = notesDraft.isEmpty ? nil : notesDraft
                    showNotesSheet = false
                },
                onCancel: {
                    showNotesSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: Full — voice input, shot log, navigation (scoring lives in Simple)

    private var fullPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                panelDragHandle

                VoiceInputView(
                    onResult: handleInput,
                    disabled: parsing,
                    placeholder: voicePrompt,
                    speech: speech
                )

                if parsing {
                    Text("PROCESSING...")
                        .font(Theme.Font.caption(11))
                        .foregroundStyle(Theme.Colors.accent)
                        .tracking(1)
                }
                if !lastParse.isEmpty && !parsing {
                    Text("RECORDED: \(lastParse.uppercased())")
                        .font(Theme.Font.caption(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .tracking(0.5)
                }

                if !hole.shots.isEmpty {
                    shotLogView
                }

                HStack(spacing: 10) {
                    Button { onPrev() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .heavy))
                            Text("PREV")
                                .font(Theme.Font.title(13))
                                .tracking(1)
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 110, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(Theme.Colors.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                    }
                    .disabled(isFirst)
                    .opacity(isFirst ? 0.3 : 1)

                    Button { attemptNextHole() } label: {
                        HStack(spacing: 6) {
                            Text(isLast ? "FINISH ROUND" : "NEXT HOLE")
                                .font(Theme.Font.title(14))
                                .tracking(1)
                            Image(systemName: isLast ? "flag.checkered" : "chevron.right")
                                .font(.system(size: 13, weight: .heavy))
                        }
                        .foregroundStyle(Theme.Colors.backdrop)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(Theme.Colors.accent)
                        )
                        .themeShadow(ShadowStyle(color: Theme.Colors.accent.opacity(0.35), radius: 10, x: 0, y: 4))
                    }
                }
            }
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.card)
        .offset(y: max(0, panelDragOffset))
        .gesture(panelDragGesture(current: .full))
    }

    // MARK: - Shared Subviews

    private var statsRow: some View {
        HStack(spacing: 6) {
            // Putts
            VStack(spacing: 3) {
                Text("PUTTS")
                    .font(Theme.Font.caption(9))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .tracking(1)
                HStack(spacing: 6) {
                    Button { adjustPutts(-1) } label: {
                        Image(systemName: "minus").font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.Colors.surfaceDeep))
                    }
                    Text(hole.putts.map { "\($0)" } ?? "-")
                        .font(Theme.Font.title(14))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 20)
                    Button { adjustPutts(1) } label: {
                        Image(systemName: "plus").font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.Colors.surfaceDeep))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                    .fill(Theme.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
            )

            // Fairway
            Button { toggleFairway() } label: {
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        Text("FAIRWAY")
                            .font(Theme.Font.caption(9))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                        if !fairwayManuallySet && suggestedFairway != nil && hole.fairwayHit != nil {
                            Image(systemName: "location.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Theme.Colors.accent.opacity(0.7))
                        }
                    }
                    Text(fairwayText.uppercased())
                        .font(Theme.Font.title(14))
                        .foregroundStyle(fairwayColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .fill(fairwayFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .strokeBorder(fairwayStroke, lineWidth: 1)
                )
            }
            .disabled(hole.par < 4)
            .opacity(hole.par < 4 ? 0.4 : 1)

            // GIR
            Button { toggleGIR() } label: {
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        Text("GIR")
                            .font(Theme.Font.caption(9))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                        if !girManuallySet && suggestedGIR != nil && hole.greenInRegulation != nil {
                            Image(systemName: "location.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Theme.Colors.accent.opacity(0.7))
                        }
                    }
                    Text(girText.uppercased())
                        .font(Theme.Font.title(14))
                        .foregroundStyle(girColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .fill(girFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .strokeBorder(girStroke, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Drag Handle + Gesture

    private var panelDragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Theme.Colors.textMuted)
            .frame(width: 40, height: 4)
            .padding(.vertical, 4)
    }

    /// Attach to any panel to make it draggable between heights
    private func panelDragGesture(current: PanelHeight) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                panelDragOffset = value.translation.height
            }
            .onEnded { value in
                let threshold: CGFloat = 50
                withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                    if value.translation.height > threshold {
                        // Dragged down → collapse
                        panelHeight = current == .full ? .simple : .collapsed
                    } else if value.translation.height < -threshold {
                        // Dragged up → expand
                        panelHeight = current == .collapsed ? .simple : .full
                    }
                    panelDragOffset = 0
                }
            }
    }

    // MARK: - Club Selector

    private var selectedBagClub: BagClub? {
        guard let c = selectedClub else { return nil }
        return (bagClubs.isEmpty ? BagClub.defaultBag : bagClubs).first { $0.club == c }
    }

    private var clubSelectButton: some View {
        Button { showClubPicker = true } label: {
            VStack(spacing: 2) {
                Text(selectedBagClub?.club.displayName.uppercased() ?? "CLUB")
                    .font(Theme.Font.label(11))
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let y = selectedBagClub?.effectiveYardage {
                    Text("\(y)Y")
                        .font(Theme.Font.display(16))
                        .foregroundStyle(Theme.Colors.textPrimary)
                } else {
                    Text("--")
                        .font(Theme.Font.display(16))
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            .frame(width: 82, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.5), lineWidth: 1.5)
            )
            .themeShadow(Theme.Shadow.pill)
        }
        .sheet(isPresented: $showClubPicker) {
            clubPickerSheet
        }
    }

    private var clubPickerSheet: some View {
        let sortedClubs = (bagClubs.isEmpty ? BagClub.defaultBag : bagClubs)
            .sorted { (a, b) in
                // Longest → shortest, with putter last, nil yardages last
                if a.club == .putter { return false }
                if b.club == .putter { return true }
                switch (a.effectiveYardage, b.effectiveYardage) {
                case let (ay?, by?): return ay > by
                case (_?, nil): return true
                case (nil, _?): return false
                default: return false
                }
            }
        return ZStack {
            Theme.Colors.backdrop.ignoresSafeArea()
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("SELECT CLUB")
                        .font(Theme.Font.display(20))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(2)
                    if let y = yardsToGreen {
                        Text("\(y)Y TO PIN")
                            .font(Theme.Font.caption(11))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(1)
                    }
                }
                .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(sortedClubs) { bc in
                            clubPickerRow(bc)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func clubPickerRow(_ bc: BagClub) -> some View {
        let isSelected = selectedClub == bc.club
        let diff: Int? = {
            guard let y = bc.effectiveYardage, let pin = yardsToGreen else { return nil }
            return y - pin
        }()
        return Button {
            selectedClub = bc.club
            showClubPicker = false
        } label: {
            HStack(spacing: 12) {
                Text(bc.club.displayName.uppercased())
                    .font(Theme.Font.title(15))
                    .foregroundStyle(isSelected ? Theme.Colors.backdrop : Theme.Colors.textPrimary)
                    .tracking(0.5)
                    .frame(width: 90, alignment: .leading)

                Spacer()

                if let d = diff {
                    Text(d == 0 ? "ON PIN" : (d > 0 ? "+\(d)Y" : "\(d)Y"))
                        .font(Theme.Font.caption(10))
                        .foregroundStyle(isSelected ? Theme.Colors.backdrop.opacity(0.7) : Theme.Colors.textMuted)
                        .tracking(0.5)
                }

                if let y = bc.effectiveYardage {
                    Text("\(y)Y")
                        .font(Theme.Font.display(18))
                        .foregroundStyle(isSelected ? Theme.Colors.backdrop : Theme.Colors.accent)
                        .frame(width: 68, alignment: .trailing)
                } else {
                    Text("--")
                        .font(Theme.Font.display(18))
                        .foregroundStyle(Theme.Colors.textMuted)
                        .frame(width: 68, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func recordClubSelection(_ club: Club) {
        // Add or update the current shot with this club
        let shotNum = hole.shots.count + 1
        let shot = Shot(shotNumber: shotNum, club: club)
        hole.shots.append(shot)
        hole.strokes = max(hole.strokes, hole.shots.count)
        StatsCalculator.deriveHoleStats(&hole)
        lastParse = club.displayName
    }

    private var shotLogView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SHOT LOG")
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .tracking(1)
                Spacer()
                Button { clearShots() } label: {
                    Text("CLEAR")
                        .font(Theme.Font.caption(10))
                        .foregroundStyle(Theme.Colors.negative)
                        .tracking(1)
                }
            }
            ForEach(hole.shots) { shot in
                HStack(spacing: 6) {
                    Text("\(shot.shotNumber).")
                        .font(Theme.Font.caption(10))
                        .foregroundStyle(Theme.Colors.textMuted)
                    if let club = shot.club {
                        Text(club.displayName.uppercased())
                            .font(Theme.Font.label(11))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(0.5)
                    }
                    if let dist = shot.distanceYards {
                        Text("\(dist)Y")
                            .font(Theme.Font.caption(11))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    if let result = shot.result {
                        Text(result.displayName.uppercased())
                            .font(Theme.Font.caption(9))
                            .tracking(0.5)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.Colors.surfaceDeep)
                            )
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if shot.isPutt {
                        Text("PUTT")
                            .font(Theme.Font.caption(9))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(0.5)
                    }
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                .fill(Theme.Colors.surfaceDeep.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Completion Sheet

    private func attemptNextHole() {
        if hole.strokes == 0 {
            // No score entered at all
            sheetMode = .both
            sheetStrokes = 0
            sheetPutts = 2
            sheetCustomScore = ""
            showCompletionSheet = true
        } else if hole.putts == nil {
            // Score entered but no putts
            sheetMode = .puttsOnly
            sheetPutts = 2
            showCompletionSheet = true
        } else {
            // Both filled, advance immediately
            onNext()
        }
    }

    private var completionSheet: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backdrop.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("HOLE \(hole.holeNumber) RESULTS")
                        .font(Theme.Font.display(20))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(1.5)
                        .padding(.top, 12)

                    if sheetMode == .both {
                        VStack(spacing: 10) {
                            Text("SCORE")
                                .font(Theme.Font.caption(10))
                                .foregroundStyle(Theme.Colors.textMuted)
                                .tracking(1)

                            HStack(spacing: 8) {
                                sheetScoreButton(label: "BIRDIE", value: hole.par - 1)
                                sheetScoreButton(label: "PAR", value: hole.par)
                                sheetScoreButton(label: "BOGEY", value: hole.par + 1)
                                sheetScoreButton(label: "DOUBLE", value: hole.par + 2)
                            }

                            HStack(spacing: 8) {
                                Text("OTHER")
                                    .font(Theme.Font.caption(10))
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .tracking(1)
                                TextField("#", text: $sheetCustomScore)
                                    .keyboardType(.numberPad)
                                    .frame(width: 60)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: sheetCustomScore) { _, newValue in
                                        if let val = Int(newValue), val > 0 {
                                            sheetStrokes = val
                                        }
                                    }
                            }

                            if sheetStrokes > 0 {
                                Text("SCORE: \(sheetStrokes)")
                                    .font(Theme.Font.title(15))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .tracking(1)
                            }
                        }
                    }

                    VStack(spacing: 8) {
                        Text("PUTTS")
                            .font(Theme.Font.caption(10))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)

                        Stepper(value: $sheetPutts, in: 0...5) {
                            Text("\(sheetPutts) PUTTS")
                                .font(Theme.Font.title(15))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .tracking(1)
                        }
                        .padding(.horizontal, 40)
                    }

                    if hole.par >= 4 {
                        sheetTripleToggle(
                            label: "FAIRWAY HIT?",
                            value: hole.fairwayHit,
                            onChange: { hole.fairwayHit = $0 }
                        )
                    }

                    sheetTripleToggle(
                        label: "GREEN IN REGULATION?",
                        value: hole.greenInRegulation,
                        onChange: { hole.greenInRegulation = $0 }
                    )

                    Spacer()

                    Button {
                        if sheetMode == .both && sheetStrokes > 0 {
                            hole.strokes = sheetStrokes
                            StatsCalculator.deriveHoleStats(&hole)
                        }
                        hole.putts = sheetPutts
                        showCompletionSheet = false
                        onNext()
                    } label: {
                        Text("SAVE & CONTINUE")
                            .font(Theme.Font.title(15))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Colors.backdrop)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .fill(
                                        (sheetMode == .both && sheetStrokes == 0)
                                            ? Theme.Colors.accent.opacity(0.4)
                                            : Theme.Colors.accent
                                    )
                            )
                    }
                    .disabled(sheetMode == .both && sheetStrokes == 0)

                    Button {
                        showCompletionSheet = false
                        onNext()
                    } label: {
                        Text("SKIP")
                            .font(Theme.Font.caption(11))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                    }
                    .padding(.bottom, 12)
                }
                .padding()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private func sheetTripleToggle(label: String, value: Bool?, onChange: @escaping (Bool?) -> Void) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(Theme.Font.caption(10))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(1)
            HStack(spacing: 8) {
                tripleButton(title: "YES", isSelected: value == true, tint: Theme.Colors.positive) {
                    onChange(value == true ? nil : true)
                }
                tripleButton(title: "NO", isSelected: value == false, tint: Theme.Colors.negative) {
                    onChange(value == false ? nil : false)
                }
            }
        }
    }

    private func tripleButton(title: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.title(13))
                .tracking(1)
                .foregroundStyle(isSelected ? Theme.Colors.backdrop : Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .fill(isSelected ? tint : Theme.Colors.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                        .strokeBorder(isSelected ? tint : Theme.Colors.border, lineWidth: 1)
                )
        }
    }

    private func sheetScoreButton(label: String, value: Int) -> some View {
        let isSelected = sheetStrokes == value
        return Button {
            sheetStrokes = value
            sheetCustomScore = ""
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(Theme.Font.caption(10))
                    .foregroundStyle(isSelected ? Theme.Colors.backdrop : Theme.Colors.textSecondary)
                    .tracking(0.8)
                Text("\(value)")
                    .font(Theme.Font.display(18))
                    .foregroundStyle(isSelected ? Theme.Colors.backdrop : Theme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                    .fill(isSelected ? Theme.Colors.accent : Theme.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Actions

    private func startVoiceInput() {
        if speech.isListening {
            speech.stopListening()
        } else {
            speech.startListening { result in
                handleInput(result)
            }
        }
    }

    private func adjustStrokes(_ delta: Int) {
        hole.strokes = max(0, hole.strokes + delta)
        StatsCalculator.deriveHoleStats(&hole)
    }

    private func adjustPutts(_ delta: Int) {
        hole.putts = max(0, (hole.putts ?? 0) + delta)
    }

    private func toggleFairway() {
        guard hole.par >= 4 else { return }
        fairwayManuallySet = true
        switch hole.fairwayHit {
        case true: hole.fairwayHit = false
        case false: hole.fairwayHit = nil
        default: hole.fairwayHit = true
        }
    }

    private func toggleGIR() {
        girManuallySet = true
        switch hole.greenInRegulation {
        case true: hole.greenInRegulation = false
        case false: hole.greenInRegulation = nil
        default: hole.greenInRegulation = true
        }
    }

    private func clearShots() {
        hole.shots = []
        hole.strokes = 0
        hole.putts = nil
        hole.fairwayHit = nil
        hole.greenInRegulation = nil
        hole.upAndDown = nil
        hole.sandSave = nil
        lastParse = ""
    }

    private func handleInput(_ input: String) {
        parsing = true
        lastParse = ""

        Task {
            let parsed = await shotParser.parse(
                input: input,
                holeNumber: hole.holeNumber,
                par: hole.par,
                yardage: hole.yardage,
                currentShotNumber: hole.shots.count + 1
            )

            await MainActor.run {
                // Shared, tested logic — reconciles strokes from swings +
                // putts + penalty strokes (the old inline version undercounted)
                lastParse = HoleScoreUpdater.apply(parsed, to: &hole)
                parsing = false
            }
        }
    }

    // MARK: - Display helpers

    private var fairwayText: String {
        hole.par < 4 ? "N/A" : (hole.fairwayHit == true ? "Hit" : hole.fairwayHit == false ? "Miss" : "-")
    }
    private var fairwayColor: Color {
        hole.fairwayHit == true ? Theme.Colors.positive :
        hole.fairwayHit == false ? Theme.Colors.negative : Theme.Colors.textPrimary
    }
    private var fairwayFill: Color {
        if hole.fairwayHit == true { return Theme.Colors.positive.opacity(0.15) }
        if hole.fairwayHit == false { return Theme.Colors.negative.opacity(0.15) }
        return Theme.Colors.surfaceElevated
    }
    private var fairwayStroke: Color {
        if hole.fairwayHit == true { return Theme.Colors.positive.opacity(0.4) }
        if hole.fairwayHit == false { return Theme.Colors.negative.opacity(0.4) }
        return Theme.Colors.border
    }
    private var girText: String {
        hole.greenInRegulation == true ? "Yes" : hole.greenInRegulation == false ? "No" : "-"
    }
    private var girColor: Color {
        hole.greenInRegulation == true ? Theme.Colors.positive :
        hole.greenInRegulation == false ? Theme.Colors.negative : Theme.Colors.textPrimary
    }
    private var girFill: Color {
        if hole.greenInRegulation == true { return Theme.Colors.positive.opacity(0.15) }
        if hole.greenInRegulation == false { return Theme.Colors.negative.opacity(0.15) }
        return Theme.Colors.surfaceElevated
    }
    private var girStroke: Color {
        if hole.greenInRegulation == true { return Theme.Colors.positive.opacity(0.4) }
        if hole.greenInRegulation == false { return Theme.Colors.negative.opacity(0.4) }
        return Theme.Colors.border
    }

    private var voicePrompt: String {
        let shotNum = hole.shots.count + 1
        if shotNum == 1 {
            if hole.par == 3 { return "\"7 iron on the green\" or \"par\"" }
            return "\"driver 250 fairway\" or \"\(hole.par)\""
        } else if hole.greenInRegulation == true || hole.shots.last?.result == .green {
            return "\"2 putts\" or \"1 putt birdie\""
        } else if shotNum == hole.par - 1 {
            return "\"8 iron on the green\" or \"bunker\""
        } else if hole.shots.last?.result == .bunker {
            return "\"sand wedge on the green\" or \"chip and a putt\""
        } else {
            return "\"chip and 2 putts\" or \"bogey\""
        }
    }
}

// MARK: - Hole Notes Sheet

private struct HoleNotesSheet: View {
    let holeNumber: Int
    @Binding var notesDraft: String
    @Bindable var speech: SpeechService
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var isTranscribing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backdrop.ignoresSafeArea()
                VStack(spacing: 14) {
                    TextEditor(text: $notesDraft)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tint(Theme.Colors.accent)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(Theme.Colors.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                        .frame(minHeight: 140)

                    HStack(spacing: 12) {
                        Button { toggleDictation() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isTranscribing ? "mic.fill" : "mic")
                                    .font(.system(size: 13, weight: .heavy))
                                Text(isTranscribing ? "STOP" : "DICTATE")
                                    .font(Theme.Font.caption(11))
                                    .tracking(1)
                            }
                            .foregroundStyle(isTranscribing ? Theme.Colors.negative : Theme.Colors.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(isTranscribing ? Theme.Colors.negative.opacity(0.15) : Theme.Colors.accentSoft)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isTranscribing ? Theme.Colors.negative.opacity(0.4) : Theme.Colors.accent.opacity(0.4), lineWidth: 1)
                            )
                        }

                        if isTranscribing && !speech.transcript.isEmpty {
                            Text(speech.transcript)
                                .font(Theme.Font.caption(11))
                                .foregroundStyle(Theme.Colors.textMuted)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("HOLE \(holeNumber) NOTES")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(Theme.Font.caption(12))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onSave) {
                        Text("SAVE")
                            .font(Theme.Font.caption(12))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(1)
                    }
                }
            }
            .toolbarBackground(Theme.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func toggleDictation() {
        if isTranscribing {
            speech.stopListening()
            isTranscribing = false
        } else {
            isTranscribing = true
            speech.startListening { result in
                // Append transcribed text to existing notes
                if notesDraft.isEmpty {
                    notesDraft = result
                } else {
                    notesDraft += " " + result
                }
                isTranscribing = false
            }
        }
    }
}

