import Foundation

/// A real public course in the Phoenix metro area with a realistic scorecard.
/// Coordinates are the (approximate) real course locations; hole GPS layouts are
/// generated deterministically around them by `CourseLayoutBuilder`.
struct SimCourse: Sendable, CustomStringConvertible {
    let name: String
    let city: String
    let lat: Double
    let lng: Double
    let teeName: String
    let rating: Double
    let slope: Int
    let pars: [Int]
    let yardages: [Int]
    let seed: UInt64

    var par: Int { pars.reduce(0, +) }
    var yardage: Int { yardages.reduce(0, +) }
    var holeCount: Int { pars.count }
    var description: String { "\(name) (\(city), par \(par), \(holeCount) holes)" }
}

enum SimCourses {

    // MARK: - Gilbert

    static let westernSkies = SimCourse(
        name: "Western Skies Golf Club", city: "Gilbert", lat: 33.3529, lng: -111.7286,
        teeName: "White", rating: 69.9, slope: 123,
        pars: [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5],
        yardages: [385, 410, 165, 520, 400, 375, 180, 395, 505, 390, 155, 420, 530, 385, 405, 170, 380, 510],
        seed: 101)

    static let kokopelli = SimCourse(
        name: "Kokopelli Golf Club", city: "Gilbert", lat: 33.3204, lng: -111.7053,
        teeName: "White", rating: 70.6, slope: 127,
        pars: [4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 3, 4, 4, 5],
        yardages: [395, 175, 410, 515, 385, 420, 160, 390, 525, 400, 380, 170, 535, 395, 185, 410, 375, 500],
        seed: 102)

    static let greenfieldLakes = SimCourse(
        name: "Greenfield Lakes Golf Course", city: "Gilbert", lat: 33.3362, lng: -111.7351,
        teeName: "White", rating: 58.2, slope: 93,
        pars: [4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3],  // executive, par 60
        yardages: [310, 140, 155, 320, 130, 165, 300, 120, 150, 315, 145, 135, 330, 125, 160, 305, 140, 130],
        seed: 103)

    static let tokaSticks = SimCourse(
        name: "Toka Sticks Golf Club", city: "Mesa", lat: 33.3052, lng: -111.6663,
        teeName: "White", rating: 70.1, slope: 118,
        pars: [4, 4, 3, 5, 4, 3, 4, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5],
        yardages: [400, 380, 170, 510, 395, 160, 405, 385, 520, 390, 410, 175, 525, 380, 400, 165, 395, 515],
        seed: 104)

    // MARK: - Chandler

    static let ocotillo = SimCourse(
        name: "Ocotillo Golf Club", city: "Chandler", lat: 33.2469, lng: -111.8622,
        teeName: "Blue", rating: 71.6, slope: 131,
        pars: [4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 5, 3, 4, 4, 3, 5, 4, 4],
        yardages: [400, 175, 530, 410, 385, 165, 420, 545, 395, 405, 520, 180, 390, 415, 170, 535, 400, 385],
        seed: 201)

    static let bearCreek = SimCourse(
        name: "Bear Creek Golf Complex", city: "Chandler", lat: 33.2103, lng: -111.9207,
        teeName: "White", rating: 70.8, slope: 125,
        pars: [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4],
        yardages: [395, 525, 170, 400, 385, 160, 540, 410, 390, 385, 175, 515, 395, 420, 165, 380, 530, 400],
        seed: 202)

    static let loneTree = SimCourse(
        name: "Lone Tree Golf Club", city: "Chandler", lat: 33.2554, lng: -111.8831,
        teeName: "White", rating: 69.4, slope: 121,
        pars: [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 3, 4, 4, 4],  // par 71
        yardages: [380, 395, 160, 505, 385, 150, 400, 510, 375, 390, 165, 385, 495, 400, 155, 370, 395, 380],
        seed: 203)

    static let sanMarcos = SimCourse(
        name: "San Marcos Golf Resort", city: "Chandler", lat: 33.3033, lng: -111.8442,
        teeName: "White", rating: 70.2, slope: 119,
        pars: [4, 4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5],
        yardages: [390, 375, 500, 165, 400, 385, 155, 515, 380, 395, 405, 170, 505, 385, 375, 160, 390, 495],
        seed: 204)

    static let springfield = SimCourse(
        name: "Springfield Golf Resort", city: "Chandler", lat: 33.2232, lng: -111.7921,
        teeName: "White", rating: 60.1, slope: 96,
        pars: [4, 3, 3, 4, 3, 3, 4, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4],  // executive, par 61
        yardages: [320, 150, 135, 310, 145, 160, 330, 125, 300, 140, 155, 315, 130, 165, 325, 120, 145, 310],
        seed: 205)

    // MARK: - Mesa

    static let longbow = SimCourse(
        name: "Longbow Golf Club", city: "Mesa", lat: 33.4553, lng: -111.7146,
        teeName: "Player", rating: 71.2, slope: 129,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 4, 4, 5, 3, 4, 4, 4],  // par 71
        yardages: [410, 395, 180, 535, 400, 420, 165, 545, 390, 405, 175, 415, 385, 530, 190, 400, 410, 395],
        seed: 301)

    static let lasSendas = SimCourse(
        name: "Las Sendas Golf Club", city: "Mesa", lat: 33.4621, lng: -111.6373,
        teeName: "White", rating: 70.9, slope: 133,
        pars: [4, 5, 3, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 3],  // par 70... adjust to 71
        yardages: [395, 520, 165, 405, 385, 175, 410, 530, 390, 400, 160, 515, 395, 415, 170, 385, 525, 180],
        seed: 302)

    static let dobsonRanch = SimCourse(
        name: "Dobson Ranch Golf Course", city: "Mesa", lat: 33.3868, lng: -111.8763,
        teeName: "White", rating: 69.8, slope: 117,
        pars: [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5],
        yardages: [385, 400, 160, 505, 390, 375, 170, 395, 515, 380, 405, 155, 520, 385, 395, 165, 380, 500],
        seed: 303)

    static let superstitionSprings = SimCourse(
        name: "Superstition Springs Golf Club", city: "Mesa", lat: 33.3882, lng: -111.6072,
        teeName: "White", rating: 71.4, slope: 135,
        pars: [4, 4, 5, 3, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 4, 5],
        yardages: [405, 390, 525, 175, 410, 395, 165, 540, 400, 385, 180, 420, 530, 395, 170, 405, 390, 515],
        seed: 304)

    static let augustaRanch = SimCourse(
        name: "Augusta Ranch Golf Club", city: "Mesa", lat: 33.3479, lng: -111.6318,
        teeName: "White", rating: 58.9, slope: 94,
        pars: [3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3],  // executive, par 60... 61
        yardages: [145, 315, 130, 160, 320, 125, 150, 305, 140, 135, 325, 155, 120, 310, 145, 130, 315, 150],
        seed: 305)

    // MARK: - Tempe

    static let kenMcDonald = SimCourse(
        name: "Ken McDonald Golf Course", city: "Tempe", lat: 33.3662, lng: -111.9238,
        teeName: "White", rating: 70.0, slope: 120,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 3, 4, 4, 5],
        yardages: [390, 405, 165, 510, 385, 400, 175, 525, 395, 380, 410, 160, 515, 390, 170, 385, 400, 505],
        seed: 401)

    static let rollingHills = SimCourse(
        name: "Rolling Hills Golf Course", city: "Tempe", lat: 33.3861, lng: -111.9082,
        teeName: "White", rating: 58.5, slope: 95,
        pars: [3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3],  // executive
        yardages: [150, 310, 135, 145, 320, 130, 160, 315, 140, 155, 305, 125, 150, 325, 135, 145, 310, 155],
        seed: 402)

    /// 9-hole course — regression coverage for the hardcoded-18 bugs.
    static let shalimar = SimCourse(
        name: "Shalimar Golf Club", city: "Tempe", lat: 33.4062, lng: -111.9214,
        teeName: "White", rating: 32.4, slope: 108,
        pars: [4, 3, 4, 4, 3, 4, 5, 3, 4],  // 9 holes, par 34
        yardages: [370, 155, 385, 360, 140, 375, 490, 165, 380],
        seed: 403)

    // MARK: - Scottsdale

    static let tpcStadium = SimCourse(
        name: "TPC Scottsdale Stadium Course", city: "Scottsdale", lat: 33.6392, lng: -111.9109,
        teeName: "Player", rating: 72.6, slope: 138,
        pars: [4, 4, 5, 3, 4, 4, 3, 4, 4, 4, 4, 3, 5, 4, 5, 3, 4, 4],  // par 71
        yardages: [410, 415, 555, 185, 450, 390, 200, 440, 415, 400, 460, 195, 550, 425, 540, 160, 430, 435],
        seed: 501)

    static let tpcChampions = SimCourse(
        name: "TPC Scottsdale Champions Course", city: "Scottsdale", lat: 33.6318, lng: -111.9162,
        teeName: "White", rating: 70.5, slope: 127,
        pars: [4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 4, 5],
        yardages: [400, 170, 415, 530, 395, 410, 180, 540, 400, 390, 165, 420, 525, 405, 175, 395, 410, 520],
        seed: 502)

    static let grayhawkRaptor = SimCourse(
        name: "Grayhawk Golf Club Raptor", city: "Scottsdale", lat: 33.6779, lng: -111.9012,
        teeName: "Talon", rating: 72.1, slope: 136,
        pars: [4, 5, 4, 3, 4, 4, 5, 3, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4],
        yardages: [420, 545, 415, 185, 435, 400, 555, 175, 425, 410, 190, 430, 540, 415, 405, 180, 550, 420],
        seed: 503)

    static let grayhawkTalon = SimCourse(
        name: "Grayhawk Golf Club Talon", city: "Scottsdale", lat: 33.6801, lng: -111.8983,
        teeName: "White", rating: 71.3, slope: 133,
        pars: [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 4, 3, 4, 5],  // par 71... 72
        yardages: [405, 420, 175, 535, 410, 165, 425, 545, 400, 395, 180, 415, 530, 405, 420, 170, 410, 525],
        seed: 504)

    static let troonNorthMonument = SimCourse(
        name: "Troon North Monument", city: "Scottsdale", lat: 33.7582, lng: -111.8938,
        teeName: "Gold", rating: 72.3, slope: 139,
        pars: [4, 4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 3, 5, 4, 4],
        yardages: [420, 410, 550, 190, 430, 415, 175, 560, 425, 405, 435, 185, 545, 420, 195, 555, 410, 430],
        seed: 505)

    static let troonNorthPinnacle = SimCourse(
        name: "Troon North Pinnacle", city: "Scottsdale", lat: 33.7601, lng: -111.8969,
        teeName: "Gold", rating: 71.9, slope: 137,
        pars: [4, 5, 3, 4, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4],
        yardages: [415, 545, 180, 425, 405, 170, 430, 550, 410, 400, 190, 540, 415, 425, 175, 405, 535, 420],
        seed: 506)

    static let mccormickPalm = SimCourse(
        name: "McCormick Ranch Palm Course", city: "Scottsdale", lat: 33.5478, lng: -111.8934,
        teeName: "White", rating: 70.7, slope: 128,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 4, 5],
        yardages: [400, 415, 170, 525, 405, 390, 180, 535, 410, 395, 165, 420, 530, 400, 415, 175, 405, 520],
        seed: 507)

    static let mccormickPine = SimCourse(
        name: "McCormick Ranch Pine Course", city: "Scottsdale", lat: 33.5469, lng: -111.8901,
        teeName: "White", rating: 71.0, slope: 130,
        pars: [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4],
        yardages: [410, 530, 175, 420, 400, 185, 540, 415, 405, 395, 170, 535, 410, 425, 180, 400, 525, 415],
        seed: 508)

    static let camelbackPadre = SimCourse(
        name: "Camelback Golf Club Padre", city: "Scottsdale", lat: 33.5512, lng: -111.9131,
        teeName: "White", rating: 70.4, slope: 126,
        pars: [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 4, 3, 5, 4, 3, 4, 4, 5],
        yardages: [395, 410, 165, 520, 400, 175, 415, 530, 390, 405, 385, 170, 525, 395, 160, 410, 400, 515],
        seed: 509)

    static let silverado = SimCourse(
        name: "Silverado Golf Club", city: "Scottsdale", lat: 33.4979, lng: -111.9068,
        teeName: "White", rating: 68.9, slope: 115,
        pars: [4, 4, 3, 4, 4, 3, 5, 4, 4, 4, 3, 4, 5, 4, 3, 4, 4, 4],  // par 70
        yardages: [375, 390, 155, 380, 395, 145, 500, 385, 370, 380, 160, 390, 495, 375, 150, 385, 395, 380],
        seed: 510)

    static let continental = SimCourse(
        name: "Continental Golf Club", city: "Scottsdale", lat: 33.5048, lng: -111.9184,
        teeName: "White", rating: 57.8, slope: 92,
        pars: [3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3],  // executive
        yardages: [140, 310, 150, 135, 320, 125, 155, 315, 145, 130, 305, 160, 140, 325, 135, 150, 310, 145],
        seed: 511)

    static let starfire = SimCourse(
        name: "Starfire Golf Club", city: "Scottsdale", lat: 33.5172, lng: -111.8990,
        teeName: "White", rating: 69.9, slope: 124,
        pars: [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 4],  // par 71
        yardages: [385, 400, 160, 510, 390, 405, 170, 395, 520, 380, 165, 410, 505, 395, 385, 155, 400, 390],
        seed: 512)

    static let orangeTree = SimCourse(
        name: "Orange Tree Golf Club", city: "Scottsdale", lat: 33.5957, lng: -111.9071,
        teeName: "White", rating: 70.3, slope: 122,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 3, 4, 4, 5],
        yardages: [395, 410, 170, 515, 400, 385, 160, 525, 405, 390, 415, 175, 520, 395, 165, 405, 390, 510],
        seed: 513)

    // MARK: - Phoenix

    static let papago = SimCourse(
        name: "Papago Golf Course", city: "Phoenix", lat: 33.4530, lng: -111.9528,
        teeName: "White", rating: 71.8, slope: 132,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 5, 4, 3, 4, 4, 3, 4, 4, 5],
        yardages: [415, 430, 180, 545, 420, 405, 190, 555, 410, 540, 425, 175, 435, 415, 185, 420, 410, 530],
        seed: 601)

    static let encanto = SimCourse(
        name: "Encanto Golf Course", city: "Phoenix", lat: 33.4772, lng: -112.0873,
        teeName: "White", rating: 68.9, slope: 111,
        pars: [4, 4, 3, 5, 4, 4, 3, 4, 4, 4, 4, 3, 5, 4, 3, 4, 4, 4],  // par 70
        yardages: [380, 395, 155, 500, 385, 370, 165, 390, 375, 380, 395, 150, 505, 385, 160, 375, 390, 380],
        seed: 602)

    static let aguila = SimCourse(
        name: "Aguila Golf Course", city: "Phoenix", lat: 33.3481, lng: -112.1772,
        teeName: "White", rating: 71.1, slope: 128,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 4, 5],
        yardages: [405, 420, 175, 530, 410, 395, 185, 540, 400, 415, 170, 425, 535, 405, 395, 180, 410, 525],
        seed: 603)

    static let caveCreek = SimCourse(
        name: "Cave Creek Golf Course", city: "Phoenix", lat: 33.6224, lng: -112.0996,
        teeName: "White", rating: 70.5, slope: 123,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 3, 4, 4, 5],
        yardages: [395, 410, 165, 520, 400, 385, 175, 530, 395, 405, 390, 160, 525, 400, 170, 385, 410, 515],
        seed: 604)

    static let gcuChampionship = SimCourse(
        name: "GCU Golf Course", city: "Phoenix", lat: 33.4918, lng: -112.1748,
        teeName: "White", rating: 71.5, slope: 131,
        pars: [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 4, 3, 5, 4, 3, 4, 4, 5],
        yardages: [410, 425, 180, 535, 415, 170, 430, 545, 405, 420, 400, 185, 540, 410, 175, 415, 405, 530],
        seed: 605)

    static let wildfirePalmer = SimCourse(
        name: "Wildfire Golf Club Palmer", city: "Phoenix", lat: 33.6866, lng: -111.9443,
        teeName: "White", rating: 71.7, slope: 134,
        pars: [4, 4, 5, 3, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 5, 4, 4],
        yardages: [415, 400, 540, 185, 425, 410, 175, 550, 405, 395, 190, 420, 545, 415, 180, 535, 400, 425],
        seed: 606)

    static let lookoutMountain = SimCourse(
        name: "Lookout Mountain Golf Club", city: "Phoenix", lat: 33.6102, lng: -112.0227,
        teeName: "White", rating: 70.6, slope: 129,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 4, 4],  // par 71
        yardages: [400, 385, 170, 525, 405, 390, 160, 535, 395, 385, 175, 410, 520, 400, 390, 165, 405, 395],
        seed: 607)

    static let legacy = SimCourse(
        name: "The Legacy Golf Club", city: "Phoenix", lat: 33.3812, lng: -112.0428,
        teeName: "White", rating: 70.8, slope: 127,
        pars: [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 4, 3, 5, 4, 3, 4, 4, 4],  // par 71
        yardages: [405, 390, 165, 520, 410, 175, 415, 530, 400, 395, 405, 170, 525, 400, 160, 410, 395, 405],
        seed: 608)

    static let stonecreek = SimCourse(
        name: "Stonecreek Golf Club", city: "Phoenix", lat: 33.5962, lng: -111.9843,
        teeName: "White", rating: 70.4, slope: 128,
        pars: [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 4, 3, 4, 4],  // par 71
        yardages: [395, 410, 160, 515, 400, 385, 170, 525, 390, 400, 165, 415, 520, 395, 385, 155, 405, 390],
        seed: 609)

    static let arizonaGrand = SimCourse(
        name: "Arizona Grand Golf Course", city: "Phoenix", lat: 33.3898, lng: -111.9718,
        teeName: "White", rating: 69.7, slope: 125,
        pars: [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 3, 4, 4, 4],  // par 71
        yardages: [385, 400, 155, 505, 390, 165, 405, 515, 380, 395, 160, 410, 510, 385, 150, 400, 390, 385],
        seed: 610)

    /// Every course in the simulation fleet.
    static let all: [SimCourse] = [
        // Gilbert
        westernSkies, kokopelli, greenfieldLakes, tokaSticks,
        // Chandler
        ocotillo, bearCreek, loneTree, sanMarcos, springfield,
        // Mesa
        longbow, lasSendas, dobsonRanch, superstitionSprings, augustaRanch,
        // Tempe
        kenMcDonald, rollingHills, shalimar,
        // Scottsdale
        tpcStadium, tpcChampions, grayhawkRaptor, grayhawkTalon,
        troonNorthMonument, troonNorthPinnacle, mccormickPalm, mccormickPine,
        camelbackPadre, silverado, continental, starfire, orangeTree,
        // Phoenix
        papago, encanto, aguila, caveCreek, gcuChampionship, wildfirePalmer,
        lookoutMountain, legacy, stonecreek, arizonaGrand,
    ]
}
