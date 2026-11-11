# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Stride is a private, single-user iOS app for workout analysis built on Apple Health. SwiftUI · SwiftData · HealthKit · MapKit · Swift Charts · iOS 17+, iPhone only, portrait.

## Commands

```sh
xcodegen generate                         # regenerate Stride.xcodeproj from project.yml (the .xcodeproj is gitignored)
cd StrideCore && swift test               # run analysis-math unit tests (runs on macOS, no simulator needed)
cd StrideCore && swift test --filter RouteMathTests/testSplits   # single test
xcodebuild -project Stride.xcodeproj -scheme Stride -destination 'platform=iOS Simulator,name=iPhone 16' build
```

- `project.yml` is the source of truth for targets, Info.plist keys and entitlements. Edit it, not the generated project, then re-run `xcodegen generate`. New Swift files under `Stride/` are picked up automatically after regenerating.
- `DEVELOPMENT_TEAM` in `project.yml` is empty; a real device (needed for Health data) requires setting a team.
- The Simulator has no Health data. Use demo data via debug launch args (DEBUG builds only):
  - `-demoData` seeds demo activities and skips onboarding
  - `-tab training|explore|records|you` picks the starting tab
  - `-openActivity N` pushes the Nth feed activity; `-detailTab overview|analysis|splits|efforts` picks its tab

## Architecture

Two parts:

- **`StrideCore/`** is a Swift package with pure, `Sendable`, platform-independent analysis math (no SwiftUI/SwiftData/HealthKit). Route math and best efforts, `ActivityAnalysis` (GAP via Minetti cost, splits, lanes, range stats, decoupling, moving time), training load (TRIMP, CTL/ATL/TSB), route signatures and segment matching, race prediction (Riegel, VDOT), GPX. All tests live here. Put new computation here when it can be tested without the app.
- **`Stride/`** is the app: `Models/` (SwiftData schema + extensions), `Services/` (HealthKit import, maintenance, records, export, demo data), `Views/` (one folder per tab plus `Activity/` for the activity detail screen), `DesignSystem/` (`DS` tokens in `Theme.swift`; use them instead of literal spacing/colors).

### Data model and persistence

- `Models/Schema.swift` uses versioned SwiftData schemas (`SchemaV1`, `SchemaV2`) with `StrideMigrationPlan`. App code uses the typealiases (`Activity = SchemaV2.Activity`, etc.). **`SchemaV1` must never change.** A schema change means adding a new `SchemaVn` and a migration stage, then moving the typealiases.
- Bulky per-activity data (route, HR, other series, laps, pauses, best efforts) is stored as JSON `Data` blobs on `Activity` and decoded through computed properties in `Activity+Data.swift`, memoized by `DecodeCache` (an `NSCache` keyed by healthID + data size). StrideCore types like `RoutePoint` are persisted this way, so their coding keys must stay stable.
- `DataVersion.health` / `DataVersion.derived` (in `Activity+Data.swift`) control re-processing. Bumping `health` makes the importer re-fetch existing workouts from HealthKit (`enrich`). Bumping `derived` makes `Maintenance.backfill` recompute derived metrics (moving time, Relative Effort, efforts, insight) at launch.
- The athlete profile (max/rest HR, birth year, units, etc.) lives in `UserDefaults` under the `Keys` enum in `Profile.swift`; views bind with `@AppStorage` using the same keys. Changing HR settings should call `Maintenance.recomputeLoads`.

### Import pipeline

`HealthImporter` (`@MainActor @Observable`, injected via `.environment`) drives the UI state and SwiftData writes. `HealthFetcher` does the HealthKit queries off the main thread and returns a plain `WorkoutPayload` that already includes `DerivedMetrics` (computed by `Derive.compute`). The importer inserts new workouts, enriches stale ones (`dataVersion < DataVersion.health`), auto-assigns default gear, then runs `Maintenance.matchSegments`. An `HKObserverQuery` with background delivery triggers quiet re-imports.

The pattern throughout is to convert SwiftData models into `Sendable` value bundles (`AnalysisInput`, `WorkoutPayload`) before heavy computation, because `@Model` objects can't cross actors.

### Activity screen

`Views/Activity/ActivityViewModel` is the shared state for the four detail tabs (Overview, Analysis, Splits, Efforts): the computed `ActivityAnalysis`, chart lanes, splits/laps, insights, similar-route comparison, and the cross-tab selection (scrub cursor, range selection, split highlight, zoom/pan). Selections are stored in display-x units (km/mi or minutes, depending on `XAxis`). Tabs read and write this one model, which is how a scrub on the charts moves the map marker and a tapped split highlights on the map.

### Other notes

- `RecordStore` caches `RecordBook`s (best efforts ranked per sport + distance) with `@ObservationIgnored` storage, so reading it from a view body doesn't cause re-render loops. Keep that property if you change it.
- The app icon is `Stride/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (single 1024px size, no alpha). Source logo files live in `Branding/` (orange `#FF8A00`).
- `RootView` applies `.id(units)` so changing km/mi re-renders every formatted value. Formatting helpers are in `Views/Shared/Formatters.swift`.
