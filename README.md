# Stride

A private, single-user, Strava-style iOS app focused on **workout analysis**, built on Apple Health.
SwiftUI · SwiftData · HealthKit · MapKit · Swift Charts · iOS 17+.

## Run
1. `xcodegen generate` (project.yml → Stride.xcodeproj)
2. Open `Stride.xcodeproj`, set your Team in Signing & Capabilities (HealthKit + background delivery are preconfigured).
3. Real iPhone for Health data. In the Simulator use **Try with demo data** (onboarding) or **You → Load demo data**.
   Debug launch args: `-demoData`, `-tab training|explore|records|you`, `-openActivity 1 -detailTab analysis`.

Analysis math lives in the `StrideCore` Swift package: `cd StrideCore && swift test`.

## Features
- **Import:** workouts, GPS, heart rate, running dynamics (power, stride, vertical oscillation, ground contact), cadence, cycling power/cadence, laps, pauses, weather, VO₂max and resting HR. Runs off the main thread and auto-syncs via HealthKit background delivery.
- **Activity screen** (Overview · Analysis · Splits · Efforts)
  - Overview: moving vs elapsed time, GAP, Relative Effort with zones, automatic insights (negative split, pacing consistency, aerobic decoupling, route history, PRs), RPE & feel, gear, notes
  - Analysis: stacked lanes (pace + GAP, HR with zone bands, grade-coloured elevation, cadence, power) with one shared scrub cursor that moves a marker on the map. Supports distance/time axis, zoom and pan, comparison with a previous run of the same route, and a two-finger range selection that shows stats and can be saved as a segment.
  - Splits: Watch laps or auto splits, colour-coded vs average, table with pace/GAP/HR/elev/cadence; tap a row to highlight it on the map, or tap Analyze to jump to that split in Analysis
  - Efforts: best efforts with medals, segment efforts
- **Training:** Fitness & Freshness (CTL/ATL/TSB), weekly load vs usual range, training calendar, trends (incl. pace, HR, load, VO₂max, resting HR) with moving average, goals with projections
- **Explore:** personal heatmap; personal segments with leaderboards and history
- **Records:** year in review, race predictor (Riegel + VO₂max/VDOT), best efforts with PR progression and best-per-month charts
- **You:** HR profile & zones, units (km/mi), gear mileage with replacement alerts, CSV export (GPX per activity), onboarding
