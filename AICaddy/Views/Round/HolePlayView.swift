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

    @State private var showTipsSheet = false
    @State private var smartAlertDismissed = false
    @State private var fairwayManuallySet = false
    @State private var girManuallySet = false

    private var runningToPar: Int { totalScore - totalPar }
    private var holesPlayed: Int { hole.holeNumber - 1 }

    /// Measure distance from tee box before first shot, from user position after
    private var distanceMeasurePoint: CLLocationCoordinate2D? {
        if hole.shots.isEmpty, let tee = holeGps?.tee {
            return tee.coordinate
        }
        return userLocation
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
                caddyTarget: holeGps != nil ? caddyTarget : nil
            )
            .ignoresSafeArea()

            // MARK: Overlay UI
            VStack(spacing: 0) {
                // Top overlay: hole info
                topOverlay
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                // Smart alert banner (dismissible)
                if let alert = smartAlert, !smartAlertDismissed {
                    smartAlertBanner(alert)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Bottom panel
                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            .onChange(of: hole.holeNumber) { _, _ in
                smartAlertDismissed = false
                fairwayManuallySet = false
                girManuallySet = false
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
        HStack(alignment: .top, spacing: 10) {
            playerCard
            Spacer(minLength: 0)
            WindCompass(
                speedMph: windSpeed,
                fromDegrees: windBearing
            )
            if !holeTips.isEmpty || dangerAlert != nil {
                tipsButton
            }
            if let gps = holeGps, let loc = distanceMeasurePoint {
                distanceCard(userLocation: loc, gps: gps)
            }
        }
    }

    private var playerCard: some View {
        HStack(spacing: 10) {
            // Hole number badge
            VStack(spacing: 0) {
                Text("HOLE")
                    .font(Theme.Font.caption(8))
                    .foregroundStyle(Theme.Colors.accent)
                    .tracking(1)
                Text("\(hole.holeNumber)")
                    .font(Theme.Font.display(22))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Colors.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.4), lineWidth: 1)
            )

            // Course info (par + yardage)
            VStack(alignment: .leading, spacing: 3) {
                Text("PAR \(hole.par)")
                    .font(Theme.Font.title(14))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .tracking(0.5)
                if let y = hole.yardage {
                    Text("\(y) YARDS")
                        .font(Theme.Font.caption(9))
                        .foregroundStyle(Theme.Colors.textMuted)
                        .tracking(0.8)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(Theme.Colors.divider)
                .frame(width: 1, height: 34)
                .padding(.horizontal, 2)

            // Round score
            VStack(spacing: 1) {
                Text(scoreBadge)
                    .font(Theme.Font.display(20))
                    .foregroundStyle(scoreColor)
                Text("THRU \(holesPlayed)")
                    .font(Theme.Font.caption(8))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .tracking(0.8)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.card)
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
        HStack(alignment: .top, spacing: 12) {
            if let front = gps.greenFront {
                let d = LocationService.distanceYards(from: loc, to: front.coordinate)
                distanceTile(label: "FRONT", yards: d, accent: Theme.Colors.positive, large: false)
            }
            if let center = gps.greenCenter {
                let d = LocationService.distanceYards(from: loc, to: center.coordinate)
                VStack(spacing: 1) {
                    distanceTile(label: "PIN", yards: d, accent: Theme.Colors.textPrimary, large: true)
                    if let adj = clubRecommendation?.adjustedDistance, adj != d {
                        Text("PLAYS \(adj)")
                            .font(Theme.Font.caption(8))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(0.5)
                    }
                }
            }
            if let back = gps.greenBack {
                let d = LocationService.distanceYards(from: loc, to: back.coordinate)
                distanceTile(label: "BACK", yards: d, accent: Theme.Colors.negative, large: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.card)
    }

    private func distanceTile(label: String, yards: Int, accent: Color, large: Bool) -> some View {
        VStack(spacing: 1) {
            Text("\(yards)")
                .font(Theme.Font.display(large ? 22 : 14))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.Font.caption(large ? 9 : 8))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.8)
        }
    }

    // MARK: - Smart Alert Banner

    private func smartAlertBanner(_ alert: SmartAlert) -> some View {
        HStack(spacing: 6) {
            Image(systemName: alert.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            Text(alert.message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { smartAlertDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(smartAlertColor(for: alert.type).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func smartAlertColor(for type: SmartAlert.AlertType) -> Color {
        switch type {
        case .momentum: return .orange
        case .pace: return .purple
        case .fatigue: return .blue
        case .milestone: return .yellow
        case .weather: return .cyan
        }
    }

    // MARK: - Tips Sheet

    private var tipsSheet: some View {
        NavigationStack {
            List {
                if let danger = dangerAlert {
                    Section("Danger Zone") {
                        Label {
                            Text(danger.message)
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(danger.severity == .high ? .red : .orange)
                        }
                    }
                }
                if !holeTips.isEmpty {
                    Section("Hole Tips") {
                        ForEach(holeTips) { tip in
                            Label {
                                Text(tip.message)
                                    .font(.subheadline)
                            } icon: {
                                Image(systemName: tipIcon(for: tip.type))
                                    .foregroundStyle(tipColor(for: tip.type))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hole \(hole.holeNumber) Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTipsSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
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
        case .noteFromPast: return .blue
        case .missTendency: return .orange
        case .scoringPattern: return .purple
        case .strategy: return .green
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
                    Text("Hole \(hole.holeNumber)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    if hole.strokes > 0 {
                        Text(hole.scoreLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button { adjustStrokes(-1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Button { adjustStrokes(1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .gesture(panelDragGesture(current: .collapsed))
        .sensoryFeedback(.impact(weight: .light), trigger: hole.strokes)
    }

    // MARK: Simple — score +/-, stats, quick buttons, mic + next hole

    private var simplePanel: some View {
        VStack(spacing: 8) {
            // Drag handle
            panelDragHandle

            // Score row: [mic/notes] [−] [score] [+] [next]
            HStack(spacing: 0) {
                // Left: mic + notes stacked
                VStack(spacing: 6) {
                    Button { startVoiceInput() } label: {
                        Image(systemName: speech.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(speech.isListening ? .green : .white)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Button {
                        notesDraft = hole.notes ?? ""
                        showNotesSheet = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "note.text")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                            if hole.notes != nil && !(hole.notes?.isEmpty ?? true) {
                                Circle().fill(.green).frame(width: 6, height: 6).offset(x: 1, y: -1)
                            }
                        }
                    }
                }
                .frame(width: 40)

                Spacer()

                // Center: − score +
                HStack(spacing: 14) {
                    Button { adjustStrokes(-1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    VStack(spacing: 2) {
                        ScoreCircle(strokes: hole.strokes, par: hole.par, size: 60)
                        if hole.strokes > 0 {
                            Text(hole.scoreLabel)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }

                    Button { adjustStrokes(1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }

                Spacer()

                // Right: next hole
                Button { attemptNextHole() } label: {
                    Image(systemName: isLast ? "flag.checkered" : "forward.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .frame(width: 40)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hole.strokes)

            // Putts, Fairway, GIR
            statsRow

            // Quick score buttons
            clubSelectorRow

            // Status feedback (compact)
            if parsing {
                Text("Processing...")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            } else if !lastParse.isEmpty {
                Text(lastParse)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                // Drag handle
                panelDragHandle

                // Voice / text input
                VoiceInputView(
                    onResult: handleInput,
                    disabled: parsing,
                    placeholder: voicePrompt,
                    speech: speech
                )

                // Status feedback
                if parsing {
                    Text("Processing...")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                if !lastParse.isEmpty && !parsing {
                    Text("Recorded: \(lastParse)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }

                // Shot log
                if !hole.shots.isEmpty {
                    shotLogView
                }

                // Navigation with full labels
                HStack(spacing: 10) {
                    Button { onPrev() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Previous")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 130, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isFirst)
                    .opacity(isFirst ? 0.3 : 1)

                    Button { attemptNextHole() } label: {
                        HStack(spacing: 4) {
                            Text(isLast ? "Finish Round" : "Next Hole")
                            Image(systemName: isLast ? "flag.checkered" : "chevron.right")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .offset(y: max(0, panelDragOffset))
        .gesture(panelDragGesture(current: .full))
    }

    // MARK: - Shared Subviews

    private var statsRow: some View {
        HStack(spacing: 6) {
            // Putts
            VStack(spacing: 2) {
                Text("Putts").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 6) {
                    Button { adjustPutts(-1) } label: {
                        Image(systemName: "minus").font(.system(size: 9))
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Text(hole.putts.map { "\($0)" } ?? "-")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 20)
                    Button { adjustPutts(1) } label: {
                        Image(systemName: "plus").font(.system(size: 9))
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Fairway
            Button { toggleFairway() } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Text("Fairway").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        if !fairwayManuallySet && suggestedFairway != nil && hole.fairwayHit != nil {
                            Image(systemName: "location.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.cyan.opacity(0.7))
                        }
                    }
                    Text(fairwayText)
                        .font(.subheadline.bold())
                        .foregroundStyle(fairwayColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(fairwayBgMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(hole.par < 4)
            .opacity(hole.par < 4 ? 0.4 : 1)

            // GIR
            Button { toggleGIR() } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Text("GIR").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        if !girManuallySet && suggestedGIR != nil && hole.greenInRegulation != nil {
                            Image(systemName: "location.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.cyan.opacity(0.7))
                        }
                    }
                    Text(girText)
                        .font(.subheadline.bold())
                        .foregroundStyle(girColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(girBgMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Drag Handle + Gesture

    private var panelDragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(.white.opacity(0.3))
            .frame(width: 40, height: 5)
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

    private var clubSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(bagClubs.isEmpty ? BagClub.defaultBag : bagClubs) { bagClub in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            if selectedClub == bagClub.club {
                                selectedClub = nil
                            } else {
                                selectedClub = bagClub.club
                                recordClubSelection(bagClub.club)
                            }
                        }
                    } label: {
                        VStack(spacing: 1) {
                            Text(bagClub.club.displayName)
                                .font(.system(size: 10, weight: selectedClub == bagClub.club ? .heavy : .semibold))
                            if let y = bagClub.effectiveYardage {
                                Text("\(y)y")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(selectedClub == bagClub.club ? .white.opacity(0.8) : .white.opacity(0.4))
                            }
                            if selectedClub == bagClub.club, let thought = bagClub.swingThought, !thought.isEmpty {
                                Text(thought)
                                    .font(.system(size: 7, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .italic()
                            }
                        }
                        .foregroundStyle(selectedClub == bagClub.club ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(selectedClub == bagClub.club ? Color.green : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
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
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Shot Log").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button("Clear") { clearShots() }
                    .font(.system(size: 10)).foregroundStyle(.red)
            }
            ForEach(hole.shots) { shot in
                HStack(spacing: 6) {
                    Text("\(shot.shotNumber).")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                    if let club = shot.club {
                        Text(club.displayName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    if let dist = shot.distanceYards {
                        Text("\(dist)y").font(.system(size: 11)).foregroundStyle(.white)
                    }
                    if let result = shot.result {
                        Text(result.displayName)
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if shot.isPutt {
                        Text("putt").font(.system(size: 9)).foregroundStyle(.blue)
                    }
                    Spacer()
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            VStack(spacing: 20) {
                Text("How'd you do on Hole \(hole.holeNumber)?")
                    .font(.title3.bold())
                    .padding(.top, 8)

                if sheetMode == .both {
                    // Quick score row
                    VStack(spacing: 8) {
                        Text("Score")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            sheetScoreButton(label: "Birdie", value: hole.par - 1, color: .red)
                            sheetScoreButton(label: "Par", value: hole.par, color: .green)
                            sheetScoreButton(label: "Bogey", value: hole.par + 1, color: .cyan)
                            sheetScoreButton(label: "Double", value: hole.par + 2, color: .blue)
                        }

                        HStack(spacing: 8) {
                            Text("Other:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                            Text("Score: \(sheetStrokes)")
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Putts stepper
                VStack(spacing: 8) {
                    Text("How many putts?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Stepper(value: $sheetPutts, in: 0...5) {
                        Text("\(sheetPutts) putts")
                            .font(.headline)
                    }
                    .padding(.horizontal, 40)
                }

                Spacer()

                // Save & Continue
                Button {
                    if sheetMode == .both && sheetStrokes > 0 {
                        hole.strokes = sheetStrokes
                        StatsCalculator.deriveHoleStats(&hole)
                    }
                    hole.putts = sheetPutts
                    showCompletionSheet = false
                    onNext()
                } label: {
                    Text("Save & Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            (sheetMode == .both && sheetStrokes == 0)
                                ? Color.green.opacity(0.4)
                                : Color.green
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(sheetMode == .both && sheetStrokes == 0)

                // Skip button
                Button {
                    showCompletionSheet = false
                    onNext()
                } label: {
                    Text("Skip")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            .padding()
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func sheetScoreButton(label: String, value: Int, color: Color) -> some View {
        Button {
            sheetStrokes = value
            sheetCustomScore = ""
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text("\(value)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(sheetStrokes == value ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(sheetStrokes == value ? color.opacity(0.6) : color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                if let strokes = parsed.totalStrokes {
                    hole.strokes = strokes
                    lastParse = "Score: \(strokes)"
                }

                if !parsed.shots.isEmpty {
                    hole.shots.append(contentsOf: parsed.shots)
                    if parsed.totalStrokes == nil {
                        hole.strokes = hole.shots.count
                    }
                    let desc = parsed.shots.map { s in
                        [s.club?.displayName, s.distanceYards.map { "\($0)y" }, s.result?.displayName]
                            .compactMap { $0 }.joined(separator: " ")
                    }.joined(separator: ", ")
                    lastParse = desc.isEmpty ? "shots added" : desc
                }

                if let putts = parsed.putts { hole.putts = putts }
                if let fir = parsed.fairwayHit { hole.fairwayHit = fir }
                if let gir = parsed.greenInRegulation { hole.greenInRegulation = gir }

                StatsCalculator.deriveHoleStats(&hole)
                parsing = false
            }
        }
    }

    // MARK: - Display helpers

    private var fairwayText: String {
        hole.par < 4 ? "N/A" : (hole.fairwayHit == true ? "Hit" : hole.fairwayHit == false ? "Miss" : "-")
    }
    private var fairwayColor: Color {
        hole.fairwayHit == true ? .green : hole.fairwayHit == false ? .red : .primary
    }
    private var fairwayBgMaterial: AnyShapeStyle {
        if hole.fairwayHit == true { return AnyShapeStyle(.green.opacity(0.3)) }
        if hole.fairwayHit == false { return AnyShapeStyle(.red.opacity(0.3)) }
        return AnyShapeStyle(.ultraThinMaterial)
    }
    private var girText: String {
        hole.greenInRegulation == true ? "Yes" : hole.greenInRegulation == false ? "No" : "-"
    }
    private var girColor: Color {
        hole.greenInRegulation == true ? .green : hole.greenInRegulation == false ? .red : .primary
    }
    private var girBgMaterial: AnyShapeStyle {
        if hole.greenInRegulation == true { return AnyShapeStyle(.green.opacity(0.3)) }
        if hole.greenInRegulation == false { return AnyShapeStyle(.red.opacity(0.3)) }
        return AnyShapeStyle(.ultraThinMaterial)
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
            VStack(spacing: 12) {
                TextEditor(text: $notesDraft)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(minHeight: 120)

                // Voice-to-text row
                HStack(spacing: 12) {
                    Button {
                        toggleDictation()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isTranscribing ? "mic.fill" : "mic")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isTranscribing ? .red : .accentColor)
                            Text(isTranscribing ? "Stop" : "Dictate")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isTranscribing ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    }

                    if isTranscribing && !speech.transcript.isEmpty {
                        Text(speech.transcript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Hole \(holeNumber) Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                }
            }
        }
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

