import Testing
import Foundation
@testable import AICaddy

@Suite("Shot parser — local voice/text parsing")
struct ShotParserTests {
    private let parser = ShotParserService(apiKey: nil)

    private func parse(_ input: String, par: Int = 4, shotNum: Int = 1) -> ParsedShotInput {
        parser.localParse(input: input, par: par, currentShotNumber: shotNum)
    }

    // MARK: - Simple scores

    @Test func numericScore() {
        #expect(parse("4").totalStrokes == 4)
        #expect(parse("7").totalStrokes == 7)
    }

    @Test func namedScores() {
        #expect(parse("par").totalStrokes == 4)
        #expect(parse("par", par: 3).totalStrokes == 3)
        #expect(parse("birdie").totalStrokes == 3)
        #expect(parse("bogey").totalStrokes == 5)
        #expect(parse("double bogey").totalStrokes == 6)
        #expect(parse("double").totalStrokes == 6)
        #expect(parse("triple").totalStrokes == 7)
        #expect(parse("eagle", par: 5).totalStrokes == 3)
        #expect(parse("hole in one", par: 3).totalStrokes == 1)
        #expect(parse("ace", par: 3).totalStrokes == 1)
    }

    @Test func scoreWithPutts() {
        let r = parse("bogey 2 putts")
        #expect(r.totalStrokes == 5)
        #expect(r.putts == 2)
    }

    @Test("Regression: punctuation/filler between score and putts must not eat the score")
    func scoreWithPuttsPunctuated() {
        let r1 = parse("par, 2 putts")
        #expect(r1.totalStrokes == 4)
        #expect(r1.putts == 2)

        let r2 = parse("par with 2 putts")
        #expect(r2.totalStrokes == 4)
        #expect(r2.putts == 2)

        let r3 = parse("1 putt birdie")
        #expect(r3.totalStrokes == 3)
        #expect(r3.putts == 1)
    }

    // MARK: - Putts

    @Test func puttsOnly() {
        #expect(parse("2 putts").putts == 2)
        #expect(parse("one putt").putts == 1)
        #expect(parse("3 putt").putts == 3)
        #expect(parse("I had 3 putts").putts == 3)
        // Putts-only inputs must not invent a total score
        #expect(parse("2 putts").totalStrokes == nil)
    }

    // MARK: - Club/distance disambiguation (the "152 yards → gap wedge" bugs)

    @Test("Regression: a distance containing 52/56/60 is not a wedge")
    func distanceIsNotAClub() {
        let r = parse("152 yards to the green", shotNum: 2)
        #expect(r.shots.count == 1)
        #expect(r.shots[0].club == nil)
        #expect(r.shots[0].distanceYards == 152)
        #expect(r.shots[0].result == .green)

        let r2 = parse("hit it 156 into the rough", shotNum: 2)
        #expect(r2.shots.first?.club == nil)
        #expect(r2.shots.first?.distanceYards == 156)
        #expect(r2.shots.first?.result == .rough)
    }

    @Test("Regression: 'drove it 260' is a driver, not a 260-yard lob wedge")
    func droveIt260() {
        let r = parse("drove it 260 down the middle of the fairway")
        #expect(r.shots.count == 1)
        #expect(r.shots[0].club == .driver)
        #expect(r.shots[0].distanceYards == 260)
        #expect(r.shots[0].result == .fairway)
        #expect(r.fairwayHit == true)
    }

    @Test func wedgeByDegreeWithSeparateDistance() {
        let r = parse("56 degree from 120", shotNum: 3)
        #expect(r.shots.first?.club == .sw)
        #expect(r.shots.first?.distanceYards == 120)

        let r2 = parse("60 degree 80 on the green", shotNum: 3)
        #expect(r2.shots.first?.club == .lw)
        #expect(r2.shots.first?.distanceYards == 80)
        #expect(r2.shots.first?.result == .green)
    }

    @Test("Regression: 'sand wedge' is a club, not a bunker result")
    func sandWedgeIsNotBunker() {
        let r = parse("sand wedge 40 on the green", shotNum: 3)
        #expect(r.shots.first?.club == .sw)
        #expect(r.shots.first?.result == .green)
        #expect(r.shots.first?.isPenalty == false)
    }

    // MARK: - Clubs

    @Test func clubAliases() {
        #expect(parse("driver 250 fairway").shots.first?.club == .driver)
        #expect(parse("3 wood 230 fairway").shots.first?.club == .wood3)
        #expect(parse("seven iron on the green", shotNum: 2).shots.first?.club == .iron7)
        #expect(parse("hybrid 210 in the rough").shots.first?.club == .hybrid4)
        #expect(parse("pitching wedge 130 green", shotNum: 2).shots.first?.club == .pw)
        #expect(parse("gap wedge to the fringe", shotNum: 3).shots.first?.club == .gw)
        #expect(parse("big dog 270 fairway").shots.first?.club == .driver)
    }

    // MARK: - Multi-shot sequences

    @Test func multiShotSequence() {
        let r = parse("driver 250 fairway then 8 iron 155 on the green")
        #expect(r.shots.count == 2)
        #expect(r.shots[0].club == .driver)
        #expect(r.shots[0].distanceYards == 250)
        #expect(r.shots[0].result == .fairway)
        #expect(r.shots[1].club == .iron8)
        #expect(r.shots[1].distanceYards == 155)
        #expect(r.shots[1].result == .green)
        #expect(r.fairwayHit == true)
    }

    @Test func commaSeparatedSequence() {
        let r = parse("driver 240 rough, 9 iron 140 bunker, sand wedge on the green")
        #expect(r.shots.count == 3)
        #expect(r.shots[1].result == .bunker)
        #expect(r.shots[2].club == .sw)
        #expect(r.shots[2].result == .green)
    }

    // MARK: - Penalties

    @Test func penaltyDetection() {
        let water = parse("7 iron in the water")
        #expect(water.shots.first?.isPenalty == true)
        #expect(water.shots.first?.result == .water)

        let ob = parse("driver out of bounds")
        #expect(ob.shots.first?.isPenalty == true)
        #expect(ob.shots.first?.result == .ob)

        let clean = parse("driver 250 fairway")
        #expect(clean.shots.first?.isPenalty == false)
    }

    // MARK: - Short-game phrases

    @Test func chipAndAPutt() {
        let r = parse("chip and a putt", shotNum: 3)
        #expect(r.shots.count == 2)
        #expect(r.putts == 1)
        #expect(r.shots[0].isPutt == false)
        #expect(r.shots[1].isPutt == true)
        #expect(r.shots[1].result == .holed)
    }

    @Test func chipAndTwoPutts() {
        let r = parse("chip and 2 putts", shotNum: 3)
        #expect(r.shots.count == 3)
        #expect(r.putts == 2)
    }

    @Test func upAndDown() {
        let r = parse("up and down", shotNum: 4)
        #expect(r.shots.count == 2)
        #expect(r.putts == 1)
    }

    // MARK: - Flags

    @Test func fairwayAndGIRFlags() {
        #expect(parse("missed the fairway").fairwayHit == false)
        #expect(parse("split the fairway").fairwayHit == true)
        #expect(parse("green in regulation", shotNum: 2).greenInRegulation == true)
        #expect(parse("missed the green", shotNum: 2).greenInRegulation == false)
    }

    @Test("Regression (found by simulation): a layup in the fairway is not FIR")
    func layupDoesNotSetFairwayHit() {
        // FIR is a tee-shot stat — shot #2 finding the fairway must not set it
        let r = parse("3 wood 230 fairway", shotNum: 2)
        #expect(r.fairwayHit == nil)
        #expect(r.shots.first?.result == .fairway)
        // But the same words on the tee shot do set it
        #expect(parse("3 wood 230 fairway", shotNum: 1).fairwayHit == true)
    }

    // MARK: - Garbage in

    @Test func nonsenseProducesNothing() {
        let r = parse("hello world how are you")
        #expect(r.totalStrokes == nil)
        #expect(r.shots.isEmpty)
        #expect(r.putts == nil)
        #expect(r.confidence < 0.5)
    }

    @Test func emptyInput() {
        let r = parse("")
        #expect(r.totalStrokes == nil)
        #expect(r.shots.isEmpty)
    }
}
