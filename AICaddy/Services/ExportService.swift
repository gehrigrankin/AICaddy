import Foundation
import UIKit

/// Export rounds as CSV or PDF
enum ExportService {

    // MARK: - CSV Export

    static func exportCSV(rounds: [Round]) -> URL? {
        var csv = "Date,Course,Tee,Score,To Par,Putts,GIR,GIR%,FIR,FIR%,Front 9,Back 9\n"

        for round in rounds where round.isComplete {
            let stats = StatsCalculator.calculate(holes: round.holes)
            let dateStr = round.date.formatted(date: .numeric, time: .omitted)
            let toPar = stats.scoreToPar >= 0 ? "+\(stats.scoreToPar)" : "\(stats.scoreToPar)"

            csv += "\(dateStr),\"\(round.courseName)\",\(round.teeName),\(stats.totalStrokes),\(toPar),"
            csv += "\(stats.totalPutts),\(stats.greensInRegulation)/\(stats.girHoles),"
            csv += String(format: "%.0f", stats.greensInRegulationPct) + ","
            csv += "\(stats.fairwaysHit)/\(stats.fairwayHoles),"
            csv += String(format: "%.0f", stats.fairwaysPct) + ","
            csv += "\(stats.frontNine),\(stats.backNine)\n"
        }

        // Detailed hole-by-hole sheet
        csv += "\n\nHOLE BY HOLE DETAIL\n"
        csv += "Date,Course,Hole,Par,Yardage,Score,Putts,Fairway,GIR\n"

        for round in rounds where round.isComplete {
            let dateStr = round.date.formatted(date: .numeric, time: .omitted)
            for hole in round.holes where hole.strokes > 0 {
                csv += "\(dateStr),\"\(round.courseName)\",\(hole.holeNumber),\(hole.par),"
                csv += "\(hole.yardage ?? 0),\(hole.strokes),\(hole.putts ?? 0),"
                csv += "\(hole.fairwayHit == true ? "Y" : hole.fairwayHit == false ? "N" : ""),"
                csv += "\(hole.greenInRegulation == true ? "Y" : hole.greenInRegulation == false ? "N" : "")\n"
            }
        }

        // Club distances sheet
        csv += "\n\nCLUB DISTANCES\n"
        csv += "Club,Distance,Shot Count\n"
        var allClubDists: [Club: [Int]] = [:]
        for round in rounds {
            for hole in round.holes {
                for shot in hole.shots where !shot.isPutt {
                    if let club = shot.club, let dist = shot.distanceYards, dist > 0 {
                        allClubDists[club, default: []].append(dist)
                    }
                }
            }
        }
        for (club, dists) in allClubDists.sorted(by: { $0.value.reduce(0, +) / max(1, $0.value.count) > $1.value.reduce(0, +) / max(1, $1.value.count) }) {
            let avg = dists.reduce(0, +) / dists.count
            csv += "\(club.displayName),\(avg),\(dists.count)\n"
        }

        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("AICaddy_Export_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).csv")

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - PDF Export

    static func exportPDF(round: Round) -> URL? {
        let stats = StatsCalculator.calculate(holes: round.holes)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("AICaddy_\(round.courseName)_\(round.date.formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).pdf")

        do {
            try renderer.writePDF(to: fileURL) { context in
                context.beginPage()
                let pageRect = context.pdfContextBounds

                // Title
                let title = "\(round.courseName) — \(round.teeName) Tees"
                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 18)
                ]
                title.draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttr)

                // Date and score
                let subtitle = "\(round.date.formatted(date: .long, time: .omitted))   Score: \(stats.totalStrokes)  (\(stats.scoreToPar >= 0 ? "+" : "")\(stats.scoreToPar))"
                let subAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.darkGray
                ]
                subtitle.draw(at: CGPoint(x: 40, y: 65), withAttributes: subAttr)

                // Stats summary
                var y: CGFloat = 100
                let statLines = [
                    "Putts: \(stats.totalPutts) (\(String(format: "%.1f", stats.puttsPerHole))/hole)",
                    "GIR: \(stats.greensInRegulation)/\(stats.girHoles) (\(String(format: "%.0f", stats.greensInRegulationPct))%)",
                    "Fairways: \(stats.fairwaysHit)/\(stats.fairwayHoles) (\(String(format: "%.0f", stats.fairwaysPct))%)",
                    "Front 9: \(stats.frontNine)  Back 9: \(stats.backNine)",
                    "Birdies: \(stats.birdies)  Pars: \(stats.pars)  Bogeys: \(stats.bogeys)  Doubles+: \(stats.doubleBogeys + stats.triplePlus)"
                ]

                let bodyAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
                for line in statLines {
                    line.draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                    y += 18
                }

                // Hole-by-hole table
                y += 20
                let headerAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 10)]
                let cellAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]

                let headers = ["Hole", "Par", "Yds", "Score", "Putts", "FIR", "GIR"]
                let colWidths: [CGFloat] = [40, 35, 45, 45, 40, 35, 35]
                var x: CGFloat = 40

                for (i, header) in headers.enumerated() {
                    header.draw(at: CGPoint(x: x, y: y), withAttributes: headerAttr)
                    x += colWidths[i]
                }
                y += 16

                for hole in round.holes where hole.strokes > 0 {
                    x = 40
                    let values = [
                        "\(hole.holeNumber)",
                        "\(hole.par)",
                        "\(hole.yardage ?? 0)",
                        "\(hole.strokes)",
                        "\(hole.putts ?? 0)",
                        hole.fairwayHit == true ? "Y" : hole.fairwayHit == false ? "N" : "-",
                        hole.greenInRegulation == true ? "Y" : hole.greenInRegulation == false ? "N" : "-"
                    ]
                    for (i, val) in values.enumerated() {
                        val.draw(at: CGPoint(x: x, y: y), withAttributes: cellAttr)
                        x += colWidths[i]
                    }
                    y += 14
                }
            }
            return fileURL
        } catch {
            return nil
        }
    }
}
