import Foundation

struct RoundStats {
    let totalStrokes: Int
    let totalPar: Int
    var scoreToPar: Int { totalStrokes - totalPar }
    let frontNine: Int
    let backNine: Int

    // Putting
    let totalPutts: Int
    let puttsPerHole: Double
    let oneputts: Int
    let threeputts: Int

    // Greens
    let greensInRegulation: Int
    let girHoles: Int
    var greensInRegulationPct: Double { girHoles > 0 ? Double(greensInRegulation) / Double(girHoles) * 100 : 0 }

    // Fairways
    let fairwaysHit: Int
    let fairwayHoles: Int
    var fairwaysPct: Double { fairwayHoles > 0 ? Double(fairwaysHit) / Double(fairwayHoles) * 100 : 0 }

    // Short game
    let upAndDowns: Int
    let upAndDownAttempts: Int
    var upAndDownPct: Double { upAndDownAttempts > 0 ? Double(upAndDowns) / Double(upAndDownAttempts) * 100 : 0 }
    let sandSaves: Int
    let sandSaveAttempts: Int
    var sandSavePct: Double { sandSaveAttempts > 0 ? Double(sandSaves) / Double(sandSaveAttempts) * 100 : 0 }
    var scramblingPct: Double

    // Scoring distribution
    let eagles: Int
    let birdies: Int
    let pars: Int
    let bogeys: Int
    let doubleBogeys: Int
    let triplePlus: Int

    // Driving
    let avgDrivingDistance: Int
    let driveCount: Int

    // Par performance
    let par3Avg: Double
    let par4Avg: Double
    let par5Avg: Double

    // Club distances
    let clubDistances: [Club: ClubDistanceStats]
}

struct ClubDistanceStats {
    let avg: Int
    let count: Int
    let distances: [Int]
}

// MARK: - Calculator

enum StatsCalculator {

    static func calculate(holes: [HoleScore]) -> RoundStats {
        let played = holes.filter { $0.strokes > 0 }

        let totalStrokes = played.reduce(0) { $0 + $1.strokes }
        let totalPar = played.reduce(0) { $0 + $1.par }

        let front = played.filter { $0.holeNumber <= 9 }
        let back = played.filter { $0.holeNumber > 9 }

        // Putting
        let holesWithPutts = played.filter { $0.putts != nil }
        let totalPutts = holesWithPutts.reduce(0) { $0 + ($1.putts ?? 0) }
        let oneputts = holesWithPutts.filter { $0.putts == 1 }.count
        let threeputts = holesWithPutts.filter { ($0.putts ?? 0) >= 3 }.count

        // GIR
        let girHoles = played.filter { $0.greenInRegulation != nil }
        let gir = girHoles.filter { $0.greenInRegulation == true }.count

        // Fairways (par 4+)
        let fairwayHoles = played.filter { $0.par >= 4 && $0.fairwayHit != nil }
        let fairwaysHit = fairwayHoles.filter { $0.fairwayHit == true }.count

        // Up and downs
        let upDownHoles = played.filter { $0.upAndDown != nil }
        let upAndDowns = upDownHoles.filter { $0.upAndDown == true }.count

        // Sand saves
        let sandHoles = played.filter { $0.sandSave != nil }
        let sandSaves = sandHoles.filter { $0.sandSave == true }.count

        // Scoring distribution
        let diffs = played.compactMap { $0.scoreToPar }

        // Driving distance
        let drives = played.flatMap { hole in
            hole.shots.filter { $0.shotNumber == 1 && hole.par >= 4 && ($0.distanceYards ?? 0) > 0 }
        }
        let avgDriving = drives.isEmpty ? 0 :
            drives.reduce(0) { $0 + ($1.distanceYards ?? 0) } / drives.count

        // Par performance
        let par3s = played.filter { $0.par == 3 }
        let par4s = played.filter { $0.par == 4 }
        let par5s = played.filter { $0.par == 5 }

        // Club distances
        var clubDists: [Club: [Int]] = [:]
        for hole in played {
            for shot in hole.shots where !shot.isPutt {
                if let club = shot.club, let dist = shot.distanceYards, dist > 0 {
                    clubDists[club, default: []].append(dist)
                }
            }
        }
        let clubDistances = clubDists.mapValues { dists in
            ClubDistanceStats(
                avg: dists.reduce(0, +) / dists.count,
                count: dists.count,
                distances: dists
            )
        }

        // Scrambling
        let scramblingAttempts = played.filter { $0.greenInRegulation == false }.count
        let scramblingSuccesses = played.filter { $0.greenInRegulation == false && $0.strokes <= $0.par }.count
        let scramblingPct = scramblingAttempts > 0 ? Double(scramblingSuccesses) / Double(scramblingAttempts) * 100 : 0

        return RoundStats(
            totalStrokes: totalStrokes,
            totalPar: totalPar,
            frontNine: front.reduce(0) { $0 + $1.strokes },
            backNine: back.reduce(0) { $0 + $1.strokes },
            totalPutts: totalPutts,
            puttsPerHole: holesWithPutts.isEmpty ? 0 : Double(totalPutts) / Double(holesWithPutts.count),
            oneputts: oneputts,
            threeputts: threeputts,
            greensInRegulation: gir,
            girHoles: girHoles.count,
            fairwaysHit: fairwaysHit,
            fairwayHoles: fairwayHoles.count,
            upAndDowns: upAndDowns,
            upAndDownAttempts: upDownHoles.count,
            sandSaves: sandSaves,
            sandSaveAttempts: sandHoles.count,
            scramblingPct: scramblingPct,
            eagles: diffs.filter { $0 <= -2 }.count,
            birdies: diffs.filter { $0 == -1 }.count,
            pars: diffs.filter { $0 == 0 }.count,
            bogeys: diffs.filter { $0 == 1 }.count,
            doubleBogeys: diffs.filter { $0 == 2 }.count,
            triplePlus: diffs.filter { $0 >= 3 }.count,
            avgDrivingDistance: avgDriving,
            driveCount: drives.count,
            par3Avg: par3s.isEmpty ? 0 : Double(par3s.reduce(0) { $0 + $1.strokes }) / Double(par3s.count),
            par4Avg: par4s.isEmpty ? 0 : Double(par4s.reduce(0) { $0 + $1.strokes }) / Double(par4s.count),
            par5Avg: par5s.isEmpty ? 0 : Double(par5s.reduce(0) { $0 + $1.strokes }) / Double(par5s.count),
            clubDistances: clubDistances
        )
    }

    /// Auto-derive GIR, fairway hit, up-and-down from shot data.
    /// Putts/fairway/GIR are fill-only (the user can set them manually);
    /// up-and-down and sand save are always recomputed — no UI sets them
    /// directly, and fill-only left them stale after score edits.
    static func deriveHoleStats(_ hole: inout HoleScore) {
        let shots = hole.shots

        if !shots.isEmpty {
            // Auto-detect putts
            let puttCount = shots.filter(\.isPutt).count
            if puttCount > 0 && hole.putts == nil {
                hole.putts = puttCount
            }

            // Auto-detect fairway hit (first shot on par 4+)
            if hole.par >= 4 && hole.fairwayHit == nil {
                if let teeShot = shots.first(where: { $0.shotNumber == 1 }), let result = teeShot.result {
                    hole.fairwayHit = result == .fairway
                }
            }

            // Auto-detect GIR
            if hole.greenInRegulation == nil {
                let girTarget = hole.par - 2
                let hitGreen = shots.first { s in
                    (s.result == .green || s.result == .holed) && s.shotNumber <= girTarget
                }
                if hitGreen != nil {
                    hole.greenInRegulation = true
                } else if shots.count >= girTarget {
                    let anyGreen = shots.filter { $0.shotNumber <= girTarget }
                        .contains { $0.result == .green || $0.result == .holed }
                    if !anyGreen { hole.greenInRegulation = false }
                }
            }
        }

        // Up-and-down / sand save: recompute from the current score every time.
        if hole.greenInRegulation == false && hole.strokes > 0 {
            hole.upAndDown = hole.strokes <= hole.par
            let hitBunker = shots.contains { $0.result == .bunker && !$0.isPutt }
            hole.sandSave = hitBunker ? (hole.strokes <= hole.par) : nil
        } else {
            hole.upAndDown = nil
            hole.sandSave = nil
        }
    }
}
