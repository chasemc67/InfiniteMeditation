# Infinite Meditation

A calm, open-ended **count-up** meditation timer for iPhone and Apple Watch.

- Start, pause and end a session; the clock counts up for as long as you sit.
- A mark every *interval* (1, 2, 3, 5, 10, 15, 20 or 30 min; default **5 min**).
- Every Nth mark is a **major mark** (default every 2nd mark = **10 min**; can be off, 2, 3, 4 or 6).
- **Apple Watch:** a haptic at every mark, with a different pattern for major marks (default single tap / double tap, both configurable). Keeps tapping **with your wrist down and the screen off**.
- **iPhone:** an optional synthesized singing-bowl chime at every mark (on by default), with a deeper, longer bowl for major marks. Keeps chiming **with the phone locked**.
- Works phone-only. With a watch, settings sync and start/pause/end are mirrored while both apps are open.
- No analytics, no accounts, no third-party dependencies.

## Why the old version stopped tapping, and what this one does

The previous watch app created a `WKExtendedRuntimeSession` but never declared a session type (`WKBackgroundModes` was missing from the Info.plist). watchOS therefore refused the session, the failure was only `print`ed, and the app was suspended as soon as the wrist went down. Haptics were also driven from a 100 Hz `Timer` inside a SwiftUI view.

This version:

1. **Declares the session types** in `Config/InfiniteMeditationWatch-Info.plist` (`WKBackgroundModes` = `mindfulness`, `workout-processing`, `audio`).
2. Offers **two background modes on the watch** (Settings › Background › Mode):
   - **Standard (default):** a `WKExtendedRuntimeSession` with the *mindfulness* type. No permissions needed and nothing is recorded. watchOS keeps the app frontmost with the screen off and lets it play haptics, **for up to 1 hour**. When time is nearly up the watch plays a double "retry" haptic; raising your wrist renews the session automatically.
   - **Long session:** an `HKWorkoutSession` (Mind & Body). Runs for as long as you meditate. Asks for Health permission once, shows the workout indicator, and only saves a workout if you turn on *Save to Health* (otherwise it is discarded).
3. **Shows the background status on screen**: "Wrist-down taps on until 10:42", "Background time ending", or the exact reason watchOS stopped the session (expired, you left the app, Low Power Mode, start error…). If Long mode can't get Health permission it falls back to Standard and says so.
4. **Schedules marks robustly**: elapsed time comes from wall-clock anchors, and the scheduler sleeps once until the next mark instead of polling. It never drifts, never double-fires, and skips (rather than plays late) a mark discovered long after it was due. The clock itself is drawn by `Text(timerInterval:)`, so nothing ticks at 100 Hz.
5. **iPhone:** holds a background audio session (`UIBackgroundModes` = `audio`, category `.playback` + `.mixWithOthers`) with an `AVAudioEngine` running for the whole session, so the app keeps running locked and plays the chime at each mark. It recovers from interruptions (calls, Siri, alarms), route changes and media-server resets.

The iPhone never "pushes" taps to the watch. Each device runs its own timer and alerts locally, so the watch doesn't depend on the phone being awake (or present).

### Known limitations

- **Standard mode is capped at 1 hour by watchOS.** If you keep your wrist down past the hour, taps stop until you raise your wrist (which renews the session automatically). For sessions over an hour, use **Long session** mode.
- In Standard mode, **leaving the app** (pressing the Digital Crown or opening another app) ends the session. Reopen the app to resume taps; the timer itself keeps counting.
- **Low Power Mode** on the watch can suppress extended runtime sessions. The status line says so when it happens.
- Long session mode shows the green workout indicator, and Apple Watch may count heart-rate readings during it. It asks for permission to *write workouts* only.
- **iPhone chime off** means the phone has nothing keeping it awake while locked, so it won't alert. The timer is still correct when you come back.
- The iPhone chime ignores the ring/silent switch (playback audio). Use the volume buttons.
- If a phone call or another app takes exclusive audio, chimes pause until the interruption ends.
- **Mirroring** only works while the other app is open or reachable. Starting on the phone starts the watch only if the watch app is in the foreground. Starting on the watch usually wakes the phone app in the background, but iOS may not let a background-woken app start audio, so open the phone app if you want both. Each device alerts independently; if both are running you'll get a tap *and* a chime.
- Apple's review guidelines discourage keeping audio sessions open purely to stay alive. Here the audio is the feature (audible chimes), but App Store review, unlike TestFlight, could still question it.

## Project layout

| Path | What it is |
| --- | --- |
| `HapticMeditation.xcodeproj` | Single project with the iOS app target **HapticMeditation** and the embedded watchOS target **HapticMeditation Watch App** (plus test targets). Shared scheme `HapticMeditation`. |
| `Shared/` | Code compiled into **both** apps: settings, the count-up timer and mark scheduler, the WatchConnectivity sync, and shared timer views. |
| `InfiniteMeditation/` | iPhone app: UI, `ChimePlayer` (background audio), `PhoneSessionController`, and `Sounds/chime_*.wav`. |
| `InfiniteMeditation Watch App/` | Watch app: UI, `BackgroundRuntime` (extended runtime and workout sessions), `HapticPlayer`, `WatchSessionController`. |
| `Config/` | Info.plist fragments (background modes), watch entitlements (HealthKit), `ExportOptions.plist`. Not in any target; referenced by build settings. |
| `Tools/generate_chimes.py` | Regenerates the chime sounds. |
| `Tools/testflight.sh` | One-command archive + upload. |

### Identifiers and signing

| | iOS app | watchOS app |
| --- | --- | --- |
| Target | `HapticMeditation` | `HapticMeditation Watch App` |
| Bundle ID | `com.AnomalousResearch.HapticMeditation` | `com.AnomalousResearch.HapticMeditation.watchkitapp` |
| Display name | Infinite Meditation | Infinite Meditation |
| Version / build | 2.0 / `CURRENT_PROJECT_VERSION` | 2.0 / same (must match the iOS app) |
| Deployment target | iOS 26.0 | watchOS 26.0 |
| Team | Anomalous Research LLC (`5QLYWR2R9M`), automatic signing | same |
| Capabilities | Background Modes: Audio | Background Modes: Mindfulness session, Workout processing, Audio; HealthKit |

The existing bundle IDs were kept so any App IDs you already registered still apply.

### Where these settings live in Xcode

You don't need to change anything; this is so you can see it and change it later.

1. Click the blue **HapticMeditation** project icon at the top of the Project navigator (left sidebar), then pick a target under **TARGETS**.
2. **Signing & Capabilities** tab:
   - *Signing:* "Automatically manage signing" is checked; Team = Anomalous Research LLC.
   - **HapticMeditation** (iOS) → **Background Modes** → *Audio, AirPlay, and Picture in Picture* is checked.
   - **HapticMeditation Watch App** → **Background Modes** → *Session Type: Mindfulness*, plus *Workout processing* and *Audio* checked. → **HealthKit** capability is present (no Clinical Records or Background Delivery).
   - If a capability ever goes missing, click **+ Capability** (top-left of that tab) and add it back. Xcode writes into the same `Config/` files this repo uses.
3. **Info** tab (watch target): *Privacy – Health Share/Update Usage Description* are the texts shown in the Health permission prompt.
4. **General** tab: Display Name, Version (2.0) and Build. Bump **Build** for every TestFlight upload, or let `Tools/testflight.sh` do it.
5. The scheme is shared (**Product › Scheme › Manage Schemes…**, "Shared" checked), so `xcodebuild` works from a fresh clone.

## Building and running in Xcode

1. Open `HapticMeditation.xcodeproj` in Xcode 26 or later.
2. In the toolbar, choose the **HapticMeditation** scheme and your iPhone as the run destination. Run (⌘R). The watch app installs alongside it on your paired watch (Watch app on iPhone › My Watch › Available Apps if it doesn't appear).
3. To debug the watch app directly, choose the **HapticMeditation Watch App** scheme (Xcode creates it automatically) and your watch as destination.
4. Unit tests: choose the **HapticMeditation** scheme and press ⌘U (or `xcodebuild test -scheme HapticMeditation -destination 'platform=iOS Simulator,name=iPhone 17'`).

The first time, Xcode may ask to register your devices and create provisioning profiles. Accept; automatic signing handles it.

## TestFlight release

### One-time App Store Connect setup

1. **App IDs** (developer.apple.com › Certificates, IDs & Profiles › Identifiers). Automatic signing registers `com.AnomalousResearch.HapticMeditation` and `…HapticMeditation.watchkitapp` the first time you build for a device. Confirm the **watchkitapp** identifier has **HealthKit** enabled; automatic signing turns it on because of the entitlement, but check if signing fails.
2. **App record** (appstoreconnect.apple.com › Apps › **+** › New App): Platform **iOS**, Name "Infinite Meditation" (must be unique on the App Store; tweak if taken), Primary language English, Bundle ID `com.AnomalousResearch.HapticMeditation`, SKU e.g. `infinite-meditation`, Full Access. The watch app ships inside the iOS app, so it needs no separate record.
3. **API key** (App Store Connect › Users and Access › Integrations › App Store Connect API › Team Keys › **+**): give it the **Admin** role. Admin lets `xcodebuild` create the cloud-managed distribution certificate; App Manager works if a distribution certificate already exists. Download the `.p8` (you can only download it once) and note the **Key ID** and the **Issuer ID** shown above the list.

   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_ABC123DEFG.p8 ~/.appstoreconnect/private_keys/
   ```
4. **TestFlight group**: App Store Connect › your app › TestFlight › Internal Testing › **+**, add yourself. Internal testers get builds without Beta App Review.
5. The build declares `ITSAppUsesNonExemptEncryption = NO`, so you won't be asked the export-compliance question for each build.

### Archive and upload (command line)

The easy way:

```bash
export ASC_KEY_ID=ABC123DEFG
export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
./Tools/testflight.sh
```

This is equivalent to:

```bash
BUILD=$(date -u +%Y%m%d%H%M)
KEY=(-allowProvisioningUpdates
     -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
     -authenticationKeyID $ASC_KEY_ID
     -authenticationKeyIssuerID $ASC_ISSUER_ID)

# 1. Archive (builds the iOS app with the watch app embedded)
xcodebuild -project HapticMeditation.xcodeproj -scheme HapticMeditation \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/InfiniteMeditation.xcarchive \
  "${KEY[@]}" CURRENT_PROJECT_VERSION=$BUILD archive

# 2. Export with App Store Connect distribution and upload (destination=upload in ExportOptions.plist)
xcodebuild -exportArchive -archivePath build/InfiniteMeditation.xcarchive \
  -exportOptionsPlist Config/ExportOptions.plist -exportPath build/export "${KEY[@]}"
```

To export an `.ipa` without uploading, change `destination` to `export` in `Config/ExportOptions.plist`, then upload with `xcrun altool --upload-app -f build/export/HapticMeditation.ipa -t ios --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID` or with the Transporter app.

The build number must increase with every upload; the script uses a UTC timestamp. Uploads appear under **TestFlight** after processing (usually 5–30 minutes). Then install from the TestFlight app on the iPhone; the watch app installs automatically if "Automatic App Install" is on (Watch app › General), or from Watch app › Available Apps.

### Archive and upload (Xcode UI alternative)

**Product › Archive** with destination "Any iOS Device (arm64)". When the Organizer opens, click **Distribute App › App Store Connect › Upload** and keep the defaults.

## Manual test plan

Before testing, on the watch: Settings › Sounds & Haptics › **Haptic Alerts** on (Prominent is easier to feel). Make sure the watch is not in Low Power Mode, and disable Wrist Detection only if you want to test with the watch off-wrist.

**Watch, Standard mode (the original bug)**
1. On the watch, open Settings (gear) › Interval **1 min**, Major mark **Every 2 marks**. Tap *Try regular* and *Try major* and confirm they feel different.
2. Back on the main screen, tap **Begin**. Within a second or two the status line should turn green: "Wrist-down taps on until hh:mm" (about one hour from now). If it shows red text instead, note the message; that's the failure reason.
3. Lower your wrist and let the screen turn off. Don't touch the watch.
4. Confirm a single tap at 1:00, a double tap at 2:00, single at 3:00, double at 4:00.
5. Raise your wrist: the clock shows the correct elapsed time and the status is still green.
6. Repeat with the defaults (**5 min / every 2 marks**): wrist down for at least 11 minutes, and confirm a single tap at 5:00 and a double tap at 10:00.
7. Pause, wait past a mark, and confirm no tap; Resume and confirm the next mark lands on schedule (e.g. paused at 3:30 for 2 min with 1-min marks → next tap at clock 4:00).
8. Press the Digital Crown to leave the app mid-session, then reopen it. The status should explain that the session stopped, then turn green again (it renews automatically).
9. Optional, for the 1-hour cap: run a Standard session past 60 min with the wrist down. Expect the double "retry" haptic shortly before the hour, then no taps until you raise your wrist; raising it renews the session (status goes green with a new end time).

**Watch, Long session mode**
1. Settings › Background › Mode **Long session (workout)**. Leave *Save to Health* off.
2. Begin. Allow the Health prompt (workouts only). The status shows "Long session · wrist-down taps on" and the workout indicator appears.
3. Wrist down for over 60 minutes (or at least 15 to sanity-check it); taps continue at every mark.
4. End. With *Save to Health* off, no workout appears in the Fitness app. Turn it on, run a short session, end, and confirm a Mind & Body workout appears.
5. Deny Health permission (Settings › Health › Data Access on the watch, or reinstall) and Begin. Expect a yellow note that it fell back to Standard mode, with taps still working.

**iPhone chime with the phone locked**
1. On the iPhone, tap the sliders icon › Interval **1 min**, Major **Every 2 marks**, *Play chime* on. Preview both chimes; the major one is deeper and rings longer.
2. Begin, then lock the phone (side button) and put it face down.
3. Confirm the soft bowl at 1:00, the deeper bowl at 2:00, and so on, while the phone stays locked.
4. Start music in another app, then start a session: music keeps playing and chimes mix over it.
5. During a session, call the phone (or trigger Siri). After the interruption ends, chimes resume at the next mark.
6. Turn *Play chime* off and Begin: the status says the iPhone won't alert while locked.

**Phone-only (no watch)**
1. On an iPhone with no paired watch (or with the watch app deleted), all controls work and Settings shows no Apple Watch section.

**Mirroring (nice-to-have)**
1. Open both apps. Begin on the phone: the watch starts too (green status). Pause, Resume and End on either device and the other follows.
2. Change the interval on the phone; the watch's Settings shows the new value (it syncs even if the watch app is closed).

## Chime sounds (provenance)

`InfiniteMeditation/Sounds/chime_minor.wav` and `chime_major.wav` were **synthesized from scratch** for this project by `Tools/generate_chimes.py`. It uses additive synthesis of inharmonic singing-bowl modes with slow beating and exponential decay, written against the Python standard library only. They contain no samples or third-party material, so there is nothing to license or attribute. Re-run `python3 Tools/generate_chimes.py` to regenerate them (deterministic output).

- Regular mark: small bowl around G4 (392 Hz), 7 s.
- Major mark: larger bowl around C4 (262 Hz), 11 s.

## Architecture notes

- `MeditationTimer` (Shared) is the count-up clock and mark scheduler. It stores `accumulated` time plus a `runningSince` date. A single `Task.sleep(..., clock: .continuous)` waits until the next mark, and `handleDueMarks()` decides what fired from wall-clock elapsed time, so late or duplicate wake-ups are harmless.
- `BackgroundRuntime` (watch) owns the extended runtime or workout session and publishes a `status` the UI always shows.
- `ChimePlayer` (iPhone) owns the audio session and engine.
- `ConnectivityService` (Shared) uses the WatchConnectivity *application context* for settings (newest-wins, delivered when possible) and live messages for start/pause/resume/end. Commands carry the sender's elapsed time, so the receiver snaps to the same clock.
- The project uses Swift's *default MainActor isolation*. Delegate callbacks from WatchKit, HealthKit and WatchConnectivity are `nonisolated` and hop to the main actor with only `Sendable` values.
