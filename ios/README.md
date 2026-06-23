# ParkingBoss iOS

SwiftUI + MapKit app for Warsaw parking, EV chargers and gas stations.
Covers ROADMAP steps 7–9, 11–13, 15. Min deployment: iOS 17.

## Project is generated, not committed

The `.xcodeproj` is produced by [XcodeGen](https://github.com/yonatanp/XcodeGen)
from `project.yml`, so the project file stays out of git and merge conflicts.

```bash
brew install xcodegen      # once
cd ios
xcodegen generate          # creates ParkingBoss.xcodeproj
open ParkingBoss.xcodeproj
```

> Building requires the iOS platform/simulator runtime installed in
> Xcode (Settings → Components). The sources type-check against the iOS SDK.

## Pointing at the backend

By default the app calls `http://localhost:3000` (works from the iOS Simulator,
which shares the host network). To override on a device, set the
`PARKINGBOSS_API` environment variable in the scheme's Run arguments, e.g.
`http://192.168.1.10:3000`.

Start the backend first (see `../backend/README.md`).

## Structure

```
ParkingBoss/
├── App/            ParkingBossApp (entry), ContentView (tab shell)
├── Models/         Location, LocationType (match backend JSON)
├── Services/       APIClient (async), LocationManager (CoreLocation)
└── Features/
    ├── Map/        MapScreen, MapViewModel, FilterChips, LocationDetailSheet
    └── List/       ListScreen
```

## Implemented vs. next

Done: map centered on Warsaw, user location, color-coded markers, **marker
clustering (MKClusterAnnotation)**, filter chips, tap → bottom sheet,
"Nawiguj" (opens Apple Maps), nearby list, **search (places + address
autocomplete)**, **favorites**, **settings** (radius/appearance/notifications),
**onboarding**.

Next (later roadmap steps): in-app turn-by-turn directions (12), geofenced
push notifications (17), Home Screen widget, CarPlay, crowdsourced reports.
