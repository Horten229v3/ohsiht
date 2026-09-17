# Moto Hazard Alert — POC

An iPhone app that speaks a warning into your helmet intercom before you reach a
reported hazard, and lets you report one with a single gloved tap. It exists to
answer two questions on real roads:

1. **Timing** — does the warning arrive at a moment you can use?
2. **Reporting** — can you report without taking attention off the road?

It is a throwaway proof of concept. Hazards are hand-seeded. There is no map,
no backend, no account, and no third-party code. The logs it produces are the
product; the app is the instrument.

> Experimental software. Hazard data may be wrong or out of date. You are
> responsible for riding to the conditions you can see.

---

## Contents

- [What you need](#what-you-need)
- [First-time setup (once, ~20 minutes)](#first-time-setup-once-20-minutes)
- [Weekly reinstall (every 7 days, ~3 minutes)](#weekly-reinstall-every-7-days-3-minutes)
- [Using the app](#using-the-app)
- [Milestone 0: the background-location check](#milestone-0-the-background-location-check)
- [Getting the data off the phone](#getting-the-data-off-the-phone)
- [Your own hazard file](#your-own-hazard-file)
- [Settings](#settings)
- [Audio](#audio)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [For developers](#for-developers)

---

## What you need

- A Mac with **Xcode 16 or newer** (free, Mac App Store). Older Xcode cannot open this project.
- An iPhone on **iOS 17 or newer**, and a cable that connects it to the Mac.
- A free Apple ID. No paid developer membership is needed. (With a free account
  the app stops launching after 7 days and has to be reinstalled — see
  [Weekly reinstall](#weekly-reinstall-every-7-days-3-minutes).)
- A Bluetooth helmet intercom (Sena, Cardo, …) paired to the phone as a normal
  audio device. Nothing special to configure.

## First-time setup (once, ~20 minutes)

### 1. Get the code onto the Mac

Either download the repository as a ZIP from GitHub (green **Code** button →
**Download ZIP**) and unzip it somewhere permanent (e.g. `~/HazardPOC`), or if
you have Git:

```sh
git clone <repository URL> ~/HazardPOC
```

### 2. Sign in to Xcode

Open Xcode → menu **Xcode → Settings… → Accounts** → **+** → **Apple ID** → sign in.
You will see a team called *"Your Name (Personal Team)"*.

### 3. Open the project and pick your team

1. Double-click `MotoHazardAlert.xcodeproj`.
2. In the left sidebar click the blue **MotoHazardAlert** project icon at the very top.
3. In the middle pane, under **TARGETS**, select **MotoHazardAlert**.
4. Open the **Signing & Capabilities** tab.
5. Tick **Automatically manage signing** if it isn't, and choose your **Personal Team** under **Team**.
6. Repeat step 5 for the **MotoHazardAlertTests** target (only needed to run tests).

The bundle identifier is `at.picaro.hazardpoc`. Leave it. If Xcode says the
identifier is taken, change it once in `Config/App.xcconfig` (e.g. add your
initials) and never again — changing it later makes iOS treat it as a
different app.

### 4. Prepare the iPhone

1. Plug the iPhone into the Mac. On the phone tap **Trust This Computer** and enter the passcode.
2. On the phone: **Settings → Privacy & Security → Developer Mode → on**. The phone restarts. Confirm again after restart.
3. Back in Xcode, in the toolbar at the top, click the device selector (it says
   something like *"iPhone 16"* next to the *MotoHazardAlert* scheme) and pick
   **your** iPhone under *iOS Devices*. Wait for Xcode to finish "preparing" it
   (a progress bar in the toolbar; first time can take a few minutes).

### 5. Install

Press the **▶ Run** button (or ⌘R). Xcode builds and installs the app. The first
time the phone will refuse to open it:

- On the phone: **Settings → General → VPN & Device Management → Developer App
  → your Apple ID → Trust**.

Now the *Hazard POC* icon on the home screen launches.

### 6. Optional: cable-free reinstalls

In Xcode: **Window → Devices and Simulators** → select your iPhone → tick
**Connect via network**. From now on Xcode can install over Wi‑Fi when the
phone and Mac are on the same network.

### 7. Optional: one-command reinstall from Terminal

Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put your
Team ID in it (Xcode shows it in the Signing tab after step 3, a 10-character
code). Then:

```sh
sh Scripts/reinstall.sh "Eugene's iPhone"
```

(Use your phone's name as shown in Xcode's device list.) This does the same as
pressing Run.

## Weekly reinstall (every 7 days, ~3 minutes)

With a free Apple ID the app is signed for 7 days. After that the icon still
shows, but tapping it does nothing or says the app is no longer available.
**Nothing is lost** — your rides, settings and hazard file stay on the phone.

To refresh:

1. Connect the phone (cable, or Wi‑Fi if you set that up).
2. Open `MotoHazardAlert.xcodeproj` in Xcode.
3. Make sure your iPhone is selected in the toolbar.
4. Press **▶ Run**.

Or, from Terminal: `sh Scripts/reinstall.sh "Eugene's iPhone"`.

If you updated the code from GitHub in between, do that first (download the new
ZIP over the old folder, or `git pull`), then run.

Two more free-account limits worth knowing: at most **3** such apps can be on the
phone at once, and at most **10** new bundle identifiers can be created per week.
Reinstalling this app does not count as a new identifier.

## Using the app

### Before the ride (Home screen)

- On first launch, read and accept the disclaimer.
- Tap **Allow location access (Always)**. iOS first asks *While Using*; accept.
  A few minutes or a day later iOS asks again whether to keep *Always* — say yes.
  If the Home screen says *"While Using only"*, tap **Open iOS Settings** and set
  Location to **Always** with **Precise Location** on. Without *Always* the app
  stops recording when the phone locks.
- Connect the helmet. In **Settings → Audio → Play test alert**, check you hear it
  in the helmet and note the latency numbers.
- The Home screen shows how many hazards are loaded and from which file.
- Tap **Start Ride**.

### During the ride (Riding screen)

- Black screen, big speed, hazard count. You never need to read it.
- **Tap anywhere** to report a hazard you just passed. You hear two rising blips
  and feel a haptic. That is the whole report. Categorising happens after the ride.
- Alerts play as a short tone followed by the phrase ("Gravel ahead"). They cut
  through music and intercom audio.
- The screen stays on; the app keeps recording and alerting with the phone
  locked or in a pocket (only the tap needs the screen).
- To end the ride, **press and hold the bar at the bottom for 1.5 seconds**. Do
  this at a standstill.

### After the ride (Ride finished screen)

- A summary you can judge at the roadside: alerts fired, mean time-to-hazard at
  trigger, reports, longest GPS gap, and so on.
- Each report you tapped is listed with five large buttons — **Gravel, Cattle,
  Accident, Surface, Other** — and **Discard**. Choose one per report.
  A categorised report becomes a hazard that can alert on your next lap.
- If you quit before categorising, the reports are kept as *Other* and offered
  again on the next launch. Nothing is lost.
- **Share ride log** sends the JSON and GPX via AirDrop, Mail, Files, etc.

## Milestone 0: the background-location check

Do this before any riding. It answers whether a free-account install keeps
recording with the screen off.

1. Set Location to **Always** (see above).
2. Tap **Start Ride**, lock the phone, put it in a pocket.
3. Walk or drive for **45 minutes**.
4. Hold the bottom bar to end the ride.
5. On the summary read **Longest GPS gap** and **Gaps over 5 s**.

**Pass:** longest gap under 5 s and zero gaps over 5 s across the whole 45 minutes.

**Fail:** report the numbers, the *GPS fixes* count, the *Duration*, and share
the ride JSON. Do not try to work around it; the fix is a paid Apple Developer
membership, after which the same test is repeated.

Also once: switch on **Airplane Mode** (leaving Location Services on), start a
ride, walk five minutes, stop. The fix count should be about one per second.
Alerts and recording need no network at any point.

## Getting the data off the phone

Every ride produces two files, named like `hazardpoc_ride_20260917-064400.json`
and `.gpx`.

- **Share sheet:** Ride finished screen (or Home → Previous rides → a ride) →
  **Share ride log**. AirDrop to the Mac is the quickest.
- **Files app:** *On My iPhone → Hazard POC → rides → (ride folder)*. You can also
  see them in Finder when the phone is connected (select the phone → Files tab).
- **Diagnostics:** Settings → Logs → **Share diagnostics log** (errors, audio
  route changes, permission changes, across all rides).

### What is in the ride JSON

| Key | Meaning |
| --- | --- |
| `settings` | The constants in effect for this ride (lead time, minimum distance, reaction time, heading tolerance, plus the fixed ones). Compare rides only when you know these. |
| `hazards` | Every active hazard at ride start, with heading and expiry. |
| `track` | One fix per second: `timestamp`, `lat`, `lon`, `speed` (m/s, −1 = unknown), `course` (degrees, −1 = unknown), `horizontalAccuracy` (m). |
| `alerts` | Every alert: `triggeredAt` (decision), `playbackStartedAt` (sound started), `outputLatencySeconds` (extra Bluetooth delay the OS reports), rider position/speed/course, `distanceMeters`, `timeToHazardSeconds`, `triggerDistanceMeters`, `dropped` + `dropReason` if the queue overflow rule dropped it. |
| `nearMisses` | Hazards that were **within trigger distance but silent** — one record per approach with the closest distance and `rejectedBy`: the gate(s) that blocked it (`expired`, `notAhead`, `headingMismatch`, `noCourse`). `outcome` is `leftRange` (stayed silent), `fired` (alerted late — the record shows how close it got before the gate released it) or `rideEnded`. Passing a hazard meant for the other direction produces exactly one of these; that is the heading filter working. |
| `reports` | Every tap: `raw` (where you were when you tapped), `offset` (where you were `reactionTimeSeconds` earlier — the recorded hazard position), category assigned afterwards, `status`. |
| `diagnostics` | Errors and notable events during the ride. |
| `summary` | The roadside numbers. `maxGapSeconds` is the Milestone 0 criterion. |

The **GPX** contains the track plus waypoints for every hazard (`HAZARD …`),
alert trigger point (`ALERT …`), raw tap (`TAP raw`) and offset report position
(`REPORT …`), so one file in any GPX viewer shows the whole ride.

## Your own hazard file

The app ships with a template of 18 hazards on the **Kühtai west ramp (L237,
Ochsengarten → Kühtai)**, on the real road centre line. Replace it with your road:

1. Settings → Hazard file → **Copy bundled template to Documents for editing**.
2. Open the Files app → *On My iPhone → Hazard POC → `seed_hazards.json`*.
   Edit it on the phone or move it to the Mac (AirDrop/Finder), edit, and put it back with the same name.
3. Start a ride — hazards are reloaded on every start. The Home screen shows the
   count and which file is in use.

If the file is unreadable the app logs the reason, falls back to the bundled
template and says so in red on the Home screen. It never alerts on doubtful data.

Format:

```json
{
  "name": "My road",
  "hazards": [
    { "lat": 47.2295, "lon": 10.9466, "heading": 68, "category": "gravel", "note": "hairpin exit" },
    { "lat": 47.2293, "lon": 10.9556, "heading": null, "category": "cattle", "note": "both directions" },
    { "lat": 47.2238, "lon": 10.9807, "heading": 129, "headingTolerance": 30, "category": "surface" }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `lat`, `lon` | yes | WGS84 decimal degrees. |
| `heading` | yes | Direction of travel (0–359, 0 = north) the hazard applies to, or `null` for all directions. Give most hazards a heading — the direction filter is one of the things under test. |
| `category` | yes | `gravel`, `cattle`, `accident`, `surface`, `other`. |
| `headingTolerance` | no | ± degrees. Default is the Settings value (60). |
| `createdAt`, `expiresAt` | no | ISO 8601. Without `createdAt` the hazard counts as created when loaded, so it never expires between launches. Without `expiresAt` it is computed: accident 3 h, cattle 7 d, other 7 d, gravel 14 d, surface 90 d. |
| `note` | no | Free text for you; appears in exports, never spoken or shown while riding. |

Hazards created from your categorised reports live in `reported_hazards.json`
next to it and are loaded as well. Settings can delete them.

**Placing hazards on hairpins.** The heading is compared with your direction of
travel about 11 seconds *before* the hazard. On a hairpin apex the road points
somewhere else entirely at that moment, so a hazard placed right on the apex
alerts late (or, with a wide tolerance, in both directions). Place the hazard on
the straight or gentle bend leading into the corner and give it the heading of
that approach. The template does this; simulating a ride over it gives 19 alerts
in the right directions, plus two "fired late" near-miss records on the twistiest
approaches, which is what to expect on a real pass.

## Settings

Four constants, editable without rebuilding, all recorded in every ride log:

| Constant | Default | What it does |
| --- | --- | --- |
| Lead time | 11 s | Alert fires when you are this many seconds from the hazard at your current (smoothed) speed. |
| Minimum distance | 80 m | The alert distance never drops below this, however slow you go. |
| Reaction time | 2.5 s | A report is placed where you were this long before the tap. |
| Heading tolerance | 60° | Default ± window for hazards without their own. |

Settings shows the resulting trigger distance at 60/100/130 km/h as you change
them. Change **one** thing between rides on the **same** road.

Fixed for this build but also logged: ahead-cone ±45°, re-arm after 1 km,
speed smoothed over 5 fixes, 2 s silence between alerts, at most 3 queued
(more → only the nearest plays, the rest are logged as dropped).

## Audio

Five phrases, pre-recorded (no text-to-speech at ride time, so latency is
constant): *Gravel ahead · Cattle ahead · Accident ahead · Rough surface ahead ·
Hazard ahead*. Each is a 0.2 s tone followed by the words, 0.9–1.2 s total.

The committed clips are machine voices. For a nicer voice, on the Mac:

```sh
sh Scripts/generate_audio.sh
```

then reinstall. It uses the Mac's built-in voice and only Python 3 (already on
every Mac with Xcode). `say -v '?'` lists voices; `python3 Scripts/generate_audio.py --engine say --voice Daniel` picks one.

**Volume:** iOS does not let an app override the media volume. Set the phone's
volume (or the intercom's) before riding. Alerts duck other audio while they play.

**Latency:** *Settings → Play test alert* shows how long the play call took and
the output latency iOS reports for the current route. Bluetooth typically adds
100–300 ms; some intercoms take longer to wake if nothing has played for a while.
Both numbers are also written into every alert record.

## Known limitations

- **Straight-line distance, no road network.** A hazard on a parallel road or on
  the valley road below a switchback can trigger a false alert. Deliberately not
  solved; count them in the logs — that count decides whether map-matching is
  needed later.
- **No tapping with the screen locked.** Recording and alerts continue; only the
  report tap needs the screen. The app keeps the screen awake during a ride.
- **Volume** as above.
- **Free account: 7-day expiry, 3 apps, 10 identifiers/week.**
- **Precise Location must be on**, otherwise fixes are hundreds of metres off and
  the app is useless. The Home screen warns if it is off.
- **Heading is unknown when stationary.** Alerts need a valid course, so nothing
  fires until you are moving. Silence over guessing.
- **Accident hazards in the template expire 3 h after the app loads them** —
  intentional, it demonstrates expiry. Set `expiresAt` explicitly if you want one
  to persist.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| Xcode: *"Signing for MotoHazardAlert requires a development team"* | Signing & Capabilities → Team → pick your Personal Team ([step 3](#3-open-the-project-and-pick-your-team)). |
| Xcode: *"Failed to register bundle identifier"* / identifier not available | Change `PRODUCT_BUNDLE_IDENTIFIER` in `Config/App.xcconfig` once (e.g. `at.picaro.hazardpoc.eh`). |
| Phone: *"Untrusted Developer"* | Settings → General → VPN & Device Management → trust your Apple ID. |
| Phone: app icon does nothing / *"no longer available"* | The 7 days are over. [Weekly reinstall](#weekly-reinstall-every-7-days-3-minutes). |
| Xcode: iPhone not in the device list | Unlock the phone, tap Trust, enable Developer Mode, try another cable/port. |
| Xcode: *"iPhone is busy: Preparing…"* | Wait; first time can take several minutes. |
| Home screen: Start Ride greyed out | Grant location access first. |
| Big GPS gaps in the summary | Check Location is **Always** + Precise. If it is and gaps persist under a free account, that is the Milestone 0 fail case — report it. |
| No sound in the helmet | Is the helmet the active output? Play music from another app to check. Settings → Play test alert shows the current output route. |
| Hazard count is 0 or "bundled template (Documents file broken)" | Your `seed_hazards.json` has a syntax error; the Home screen and diagnostics log say where. |
| App crashed / phone died mid-ride | Start the app; it reassembles the ride from what was written and lists it as *recovered*. |

## For developers

Structure:

```
MotoHazardAlert/
  Core/          pure Swift, no UIKit/CoreLocation: models, trigger engine, exporters
    Models/      Hazard, TrackPoint, TunableSettings, events, RideLog, expiry table
    Engine/      Geo, SpeedSmoother, TriggerEngine (5 gates → Verdict), FiredHazardTracker,
                 AlertScheduler, ReactionOffset, NearMissTracker
    Export/      RideEventRecord (JSONL line), RideLogAssembler, GPXWriter
  Services/      LocationService, AudioService, HazardStore, RideStore, ReportStore,
                 SettingsStore, DiagnosticsLog
  App/           AppModel (navigation, test alert), RideSession (the per-fix loop)
  Views/         Disclaimer, Home, Riding, PostRide, RideList, Settings
  Resources/     seed_hazards.json, Audio/*.wav
MotoHazardAlertTests/   XCTest, runs in Xcode (⌘U) and via SwiftPM
Config/                 App.xcconfig (bundle id), Local.xcconfig (team, uncommitted)
Scripts/                generate_audio.*, reinstall.sh
Package.swift           SwiftPM harness for Core + tests on any platform
```

- Zero third-party dependencies, runtime or build-time.
- Trigger logic is `TriggerEngine.evaluate(...)`; it evaluates all five gates
  without short-circuiting and returns every failing gate, which is what makes
  near-miss records legible. `shouldAlert(rider:hazard:alreadyFired:)` is the
  spec's Boolean wrapper.
- During a ride, fixes and events are appended to `track.jsonl` / `events.jsonl`;
  the single ride JSON and GPX are assembled on stop. `RideStore.recoverOrphans()`
  finishes any ride the app did not stop.
- Core tests run without Xcode: `swift test` (Swift 5.9+; verified on Linux with
  Swift 6.1). Test files use `#if canImport(HazardCore)` to import the right module.
- Safety rules from the spec are load-bearing: no imperative audio, no modal UI
  during a ride, fail silent in the UI and loud in the log, expired data never fires.
- Out of scope and not to be added: police/speed-camera/radar categories in any
  form (legal constraint), backend, accounts, maps, routing, pace notes,
  moderation, push, Android, hardware buttons, App Store, analytics, crash
  reporting.

Map data in the seed template © OpenStreetMap contributors, ODbL.
