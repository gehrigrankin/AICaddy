# AI Caddy — agent notes

Voice-first golf GPS / scorecard iOS app (SwiftUI, SwiftData, MapKit,
OpenStreetMap course data). **This repo (`~/coding/AICaddy`) is the ONE true
codebase** — a stale parallel copy once lived in `~/coding/ai-golf-caddy` and
an entire session's fixes went into the wrong one before it was archived
(2026-07-19). If something seems missing, check `git log` here first, not
other folders.

## Build & test

```bash
# Build (scheme AICaddy, simulator)
xcodebuild -project AICaddy.xcodeproj -scheme AICaddy \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Unit tests — 125 tests incl. 40 full-round course simulations (all green as of 2026-07-19)
xcodebuild test -project AICaddy.xcodeproj -scheme AICaddy \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AICaddyTests
```

Tests are Swift Testing (`import Testing`), app-hosted. The test folders are
attached to their targets via `fileSystemSynchronizedGroups` in the pbxproj
(they were NOT for the project's first months — every test run failed with
"executable couldn't be located" until 2026-07-19). New files dropped into
`AICaddyTests/` join the target automatically.

## Environment gotchas (verified, don't re-debug)

- **Intel Mac simulator renders MapKit vector styles as SOLID RED**
  (.standard/.hybrid/.mutedStandard/flyover). Apple's own Maps app does it
  too. Satellite (raster) is fine. Correct on real devices. Don't chase it.
- **Overpass API rate-limits per IP** (free service). CourseSearchService
  falls back overpass-api.de → overpass.kumi.systems and surfaces a
  "service busy" error for 429/504. Don't hammer it in loops.
- Simulator GPS can be pointed at a course:
  `xcrun simctl location "iPhone 16" set 33.3282,-111.7601` (Western Skies).
- Many courses have NO hole data in OSM (Western Skies included — verified).
  That's what the in-app "MAP THIS HOLE" two-tap flow is for; user-mapped
  holes persist on the Course AND the round's stored tee. **Never refetch a
  saved course from OSM — it would clobber user-mapped holes** (this is why
  "recent courses" reuses saved data).

## Architecture crib sheet

- `RoundView` owns round state/phases (search → setup → play → summary),
  passes `currentHoleGps` (from `round.courseTee ?? activeCourse`) down.
- `HolePlayView` (~1.6k lines) = the on-course screen: full-screen
  `HoleMapView` + overlays. Voice input → `ShotParserService.localParse`
  (Claude API optional via ANTHROPIC_API_KEY) → `HoleScoreUpdater.apply`
  (strokes = swings + putts + penalties; heavily tested — change it only
  with the tests).
- `HoleMapView`/`NativeMapView` (MKMapView wrapper): hole-overview framing
  (`fitHole()` — frames the hole, not the player, when player >1km away;
  course center when no hole GPS), continuous re-frame every ~15m of
  movement (paused during gestures), flyover on hole change, long-press =
  "mark my ball", MAP THIS HOLE tap flow.
- `LocationService`: GPS fix filtering in `ingest()` (rejects accuracy <0
  or >50m, age >15s), `simulatedLocation` override + `simulateDrive(to:)`
  (animated cart ride) for the DEBUG-only `DebugLocationBar` sim.
- `CourseSearchService`: Nominatim name search + Overpass details.
  `parseHoles`/`normalizedHoles` are static for tests. Gap-fills partial
  courses (playability), dedupes adjacent-course holes by course center.
- Tests: `AICaddyTests/Support/RoundSimEngine.swift` simulates full rounds
  (GPS track, dispersion, utterances) over `SimCourses` (40 real
  Phoenix-metro courses); assertions cover score integrity vs ground truth.

## Known gaps / sensible next steps

- **Escape-hatch UI not ported**: `HoleScoreUpdater` has removeShot/reset
  (tested), but the redesigned HolePlayView has no Undo button, per-shot
  delete, or Reset Hole UI yet. Discard-round UI also absent here.
- **AutoAdvanceService is unwired** — fixed & tested (lastHole/scored-gate/
  injectable clock) but no view calls `checkForAdvance`.
- Watch app / Live Activities / CarPlay scaffolding exists but is unwired.
- `redesign/pga2k-vibe` branch is fully merged into main; work on main.
- Sim "Drive to Ball" uses the last long-press/drag mark (falls back to the
  AI caddy target); the reskin session may want a dedicated "I hit it here"
  affordance in the bottom panel.

## History context

Reskin passes 1–3 ("PGA 2K vibe") landed 2026-07-19 alongside: course-loading
fix (way-type OSM courses loaded zero holes), hole-overview camera, live
distances (was frozen at tee), MAP THIS HOLE, ball marking + sim drive,
Overpass mirrors, recent courses, ported logic fixes (parser corruption,
strokes undercount, handicap crash, GPS filtering), and the 125-test suite.
