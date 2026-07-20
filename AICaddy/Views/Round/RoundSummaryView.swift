import SwiftUI
import UIKit

struct RoundSummaryView: View {
    let round: Round
    let onDone: () -> Void
    var onHoleTap: ((Int) -> Void)?

    @State private var analysis: RoundAnalysis?
    @State private var loadingAnalysis = false
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    private let analysisService = RoundAnalysisService()

    private var stats: RoundStats {
        StatsCalculator.calculate(holes: round.holes)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Colors.backdrop, Theme.Colors.surfaceDeep, Theme.Colors.backdrop],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("ROUND COMPLETE")
                            .font(Theme.Font.caption(11))
                            .foregroundStyle(Theme.Colors.accent)
                            .tracking(2)
                        Text(round.courseName.uppercased())
                            .font(Theme.Font.display(20))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .tracking(1)
                        Text("\(round.teeName.uppercased()) · \(round.date.formatted(date: .abbreviated, time: .omitted).uppercased())")
                            .font(Theme.Font.caption(10))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(0.5)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 4) {
                        Text("\(stats.totalStrokes)")
                            .font(Theme.Font.display(72))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        ScoreText(scoreToPar: stats.scoreToPar)
                            .font(Theme.Font.display(22))
                        Text("FRONT \(stats.frontNine) · BACK \(stats.backNine)")
                            .font(Theme.Font.caption(10))
                            .foregroundStyle(Theme.Colors.textMuted)
                            .tracking(1)
                    }
                    .padding(.vertical, 4)

                    LazyVGrid(columns: [.init(), .init(), .init()], spacing: 8) {
                        StatCard(label: "PUTTS", value: "\(stats.totalPutts)", sub: String(format: "%.1f/HOLE", stats.puttsPerHole))
                        StatCard(label: "GIR", value: "\(stats.greensInRegulation)/\(stats.girHoles)",
                                 sub: String(format: "%.0f%%", stats.greensInRegulationPct))
                        StatCard(label: "FAIRWAYS", value: "\(stats.fairwaysHit)/\(stats.fairwayHoles)",
                                 sub: String(format: "%.0f%%", stats.fairwaysPct))
                    }

                    sectionHeader("SCORING")
                    HStack(spacing: 4) {
                        ScoringPill(label: "EAGLES", count: stats.eagles, color: Theme.Colors.accent)
                        ScoringPill(label: "BIRDIES", count: stats.birdies, color: Theme.Colors.positive)
                        ScoringPill(label: "PARS", count: stats.pars, color: Theme.Colors.textPrimary)
                        ScoringPill(label: "BOGEYS", count: stats.bogeys, color: Theme.Colors.textSecondary)
                        ScoringPill(label: "DBL", count: stats.doubleBogeys, color: Theme.Colors.negative)
                        ScoringPill(label: "3+", count: stats.triplePlus, color: Theme.Colors.textMuted)
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

                    WhatCostYouCompactCard(holes: round.holes)

                    LazyVGrid(columns: [.init(), .init()], spacing: 8) {
                        StatCard(label: "1-PUTTS", value: "\(stats.oneputts)")
                        StatCard(label: "3-PUTTS", value: "\(stats.threeputts)")
                        if stats.upAndDownAttempts > 0 {
                            StatCard(label: "UP & DOWN", value: String(format: "%.0f%%", stats.upAndDownPct),
                                     sub: "\(stats.upAndDowns)/\(stats.upAndDownAttempts)")
                        }
                        if stats.sandSaveAttempts > 0 {
                            StatCard(label: "SAND SAVES", value: String(format: "%.0f%%", stats.sandSavePct),
                                     sub: "\(stats.sandSaves)/\(stats.sandSaveAttempts)")
                        }
                        if stats.scramblingPct > 0 {
                            StatCard(label: "SCRAMBLING", value: String(format: "%.0f%%", stats.scramblingPct))
                        }
                        if stats.avgDrivingDistance > 0 {
                            StatCard(label: "AVG DRIVE", value: "\(stats.avgDrivingDistance)Y",
                                     sub: "\(stats.driveCount) DRIVES")
                        }
                    }

                    if stats.par3Avg > 0 || stats.par4Avg > 0 || stats.par5Avg > 0 {
                        sectionHeader("AVG BY PAR")
                        LazyVGrid(columns: [.init(), .init(), .init()], spacing: 8) {
                            if stats.par3Avg > 0 { StatCard(label: "PAR 3", value: String(format: "%.1f", stats.par3Avg)) }
                            if stats.par4Avg > 0 { StatCard(label: "PAR 4", value: String(format: "%.1f", stats.par4Avg)) }
                            if stats.par5Avg > 0 { StatCard(label: "PAR 5", value: String(format: "%.1f", stats.par5Avg)) }
                        }
                    }

                    if !stats.clubDistances.isEmpty {
                        sectionHeader("CLUB DISTANCES")
                        LazyVGrid(columns: [.init(), .init()], spacing: 8) {
                            ForEach(
                                stats.clubDistances.sorted { $0.value.avg > $1.value.avg },
                                id: \.key
                            ) { club, data in
                                StatCard(label: club.displayName.uppercased(), value: "\(data.avg)Y", sub: "\(data.count) SHOTS")
                            }
                        }
                    }

                    sectionHeader("SCORECARD")
                    ScorecardView(
                        holes: round.holes,
                        courseName: round.courseName,
                        teeName: round.teeName,
                        onHoleTap: onHoleTap
                    )

                    if let analysis {
                        RoundAnalysisView(analysis: analysis)
                    } else if loadingAnalysis {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.Colors.accent)
                            Text("AI COACH IS ANALYZING...")
                                .font(Theme.Font.caption(10))
                                .foregroundStyle(Theme.Colors.textMuted)
                                .tracking(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(Theme.Colors.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                    }

                    HStack(spacing: 10) {
                        Button {
                            let card = ShareableScorecard(round: round, stats: stats)
                            shareImage = card.renderImage()
                            showShareSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .heavy))
                                Text("SHARE")
                                    .font(Theme.Font.title(13))
                                    .tracking(1)
                            }
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .fill(Theme.Colors.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
                            )
                        }

                        Button { onDone() } label: {
                            Text("DONE")
                                .font(Theme.Font.title(14))
                                .tracking(1.5)
                                .foregroundStyle(Theme.Colors.backdrop)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                        .fill(Theme.Colors.accent)
                                )
                        }
                    }
                    .padding(.bottom, 20)
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
        .task {
            guard analysis == nil, round.isComplete else { return }
            loadingAnalysis = true
            analysis = await analysisService.analyze(round: round)
            loadingAnalysis = false
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Font.caption(10))
                .foregroundStyle(Theme.Colors.accent)
                .tracking(1.5)
            Spacer()
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct StatCard: View {
    let label: String
    let value: String
    var sub: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(Theme.Font.caption(9))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(1)
            Text(value)
                .font(Theme.Font.display(20))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let sub {
                Text(sub)
                    .font(Theme.Font.caption(8))
                    .foregroundStyle(Theme.Colors.textMuted)
                    .tracking(0.5)
            }
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

struct ScoringPill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(Theme.Font.display(18))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Font.caption(8))
                .foregroundStyle(Theme.Colors.textMuted)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}
