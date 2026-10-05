# Boundless Meditation

A calm, open-ended **count-up** meditation timer for iPhone and Apple Watch.

- Start, pause and end a session; the clock counts up for as long as you sit.
- A mark every *interval* (1, 2, 3, 5, 10, 15, 20 or 30 min; default **5 min**).
- Every Nth mark is a **major mark** (default every 2nd mark = **10 min**; can be off, 2, 3, 4 or 6).
- **Apple Watch:** a haptic at every mark, with a different pattern for major marks (default single tap / double tap, both configurable). Keeps tapping **with your wrist down and the screen off**.
- **iPhone:** an optional synthesized singing-bowl chime at every mark (on by default), with a deeper, longer bowl for major marks. Keeps chiming **with the phone locked**.
- Works phone-only. With a watch, settings sync, and start/pause/end catch up when the two apps reconnect — including a pause made on the iPhone while the watch was asleep with your wrist down.
- **Mindful Minutes** (on by default): ending a session saves the time you actually meditated to Apple Health. Pauses are left out. If the phone and watch shared the session, only the device you tap End on writes it.
- **History**: the clock button (top left on iPhone, top left on the watch) lists completed sessions, newest first. Swipe left to delete a row. A session ended on the watch shows up on the phone too, once, even if both devices were in it. Deleting a row does not remove the Health sample.
- No analytics, no accounts, no third-party dependencies.

## Why the old version stopped tapping, and what this one does

The previous watch app created a `WKExtendedRuntimeSession` but never declared a session type (`WKBackgroundModes` was missing from the Info.plist). watchOS therefore refused the session, the failure was only `print`ed, and the app was suspended as soon as the wrist went down. Haptics were also driven from a 100 Hz `Timer` inside a SwiftUI view.

This version:

1. **Declares the session types** in `Config/InfiniteMeditationWatch-Info.plist` (`WKBackgroundModes` = `mindfulness`, `workout-processing`; the Audio background mode is `UIBackgroundModes` = `audio`, since `audio` is not a valid `WKBackgroundModes` value).
2. Offers **two background modes on the watch** (Settings › Background › Mode):
   - **Standard (default):** a `WKExtendedRuntimeSession` with the *mindfulness* type. No permissions needed and nothing is recorded. watchOS keeps the app frontmost with the screen off and lets it play haptics, **for up to 1 hour**. When time is nearly up the watch plays a double "retry" haptic; raising your wrist renews the session automatically.
   - **Long session:** an `HKWorkoutSession` (Mind & Body). Runs for as long as you meditate. Asks for Health permission once, shows the workout indicator, and only saves a workout if you turn on *Save workout to Health* (otherwise it is discarded). That workout is separate from Mindful Minutes: a Mind & Body workout is not a Mindful Minutes entry, and Mindful Minutes are still saved when the workout is discarded.
3. **Shows the background status on screen**: "Wrist-down taps on until 10:42", "Background time ending", or the exact reason watchOS stopped the session (expired, you left the app, Low Power Mode, start error…). If Long mode can't get Health permission it falls back to Standard and says so.
4. **Schedules marks robustly**: elapsed time comes from wall-clock anchors, and the scheduler sleeps once until the next mark instead of polling. It never drifts, never double-fires, and skips (rather than plays late) a mark discovered long after it was due. The clock itself is drawn by `Text(timerInterval:)`, so nothing ticks at 100 Hz.
5. **iPhone:** holds a background audio session (`UIBackgroundModes` = `audio`, category `.playback` + `.mixWithOthers`) with an `AVAudioEngine` running for the whole session, so the app keeps running locked and plays the chime at each mark. It recovers from interruptions (calls, Siri, alarms), route changes and media-server resets.

The iPhone never "pushes" taps to the watch. Each device runs its own timer and alerts locally, so the watch doesn't depend on the phone being awake (or present).

### Known limitations

- **Standard mode is capped at 1 hour by watchOS.** If you keep your wrist down past the hour, taps stop until you raise your wrist (which renews the session automatically). For sessions over an hour, use **Long session** mode.
- In Standard mode, **leaving the app** (pressing the Digital Crown or opening another app) ends the session. Reopen the app to resume taps; the timer itself keeps counting.
- **Low Power Mode** on the watch can suppress extended runtime sessions. The status line says so when it happens.
- Long session mode shows the green workout indicator, and Apple Watch may count heart-rate readings during it. Starting a long session asks for permission to *write workouts*. Ending any session, with Mindful Minutes on, asks for permission to *write mindful sessions* on the device where you tap End.
- **iPhone chime off** means the phone has nothing keeping it awake while locked, so it won't alert. The timer is still correct when you come back.
- The iPhone chime ignores the ring/silent switch (playback audio). Use the volume buttons.
- If a phone call or another app takes exclusive audio, chimes pause until the interruption ends.
- **Mirroring** delivers immediately while the other app is reachable. If it isn't (the usual case with your wrist down), the pause, resume, or end is queued and applied when that app activates, becomes reachable, or comes to the foreground. A live message is still sent when it can be. Starting on the phone starts the watch only if the watch app is in the foreground, because watchOS only lets a background session begin while the app is open. Starting on the watch usually wakes the phone app in the background, but iOS may not let a background-woken app start audio, so open the phone app if you want both. Each device alerts independently; if both are running you'll get a tap *and* a chime.
- Apple's review guidelines discourage keeping audio sessions open purely to stay alive. Here the audio is the feature (audible chimes), but App Store review, unlike TestFlight, could still question it.

## Project layout

| Path | What it is |
| --- | --- |
| `HapticMeditation.xcodeproj` | Single project with the iOS app target **HapticMeditation** and the embedded watchOS target **HapticMeditation Watch App** (plus test targets). Shared scheme `HapticMeditation`. |
| `Shared/` | Code compiled into **both** apps: settings, the count-up timer and mark scheduler, session sync, Mindful Minutes planning, session history, and shared timer views. |
| `InfiniteMeditation/` | iPhone app: UI, `ChimePlayer` (background audio), `PhoneSessionController`, and `Sounds/chime_*.wav`. |
| `InfiniteMeditation Watch App/` | Watch app: UI, `BackgroundRuntime` (extended runtime and workout sessions), `HapticPlayer`, `WatchSessionController`. |
| `Config/` | Info.plist fragments (background modes), HealthKit entitlements for both apps, `ExportOptions.plist`. Not in any target; referenced by build settings. |
| `Tools/generate_chimes.py` | Regenerates the chime sounds. |
| `Tools/testflight.sh` | One-command archive + upload. |

### Identifiers and signing

| | iOS app | watchOS app |
| --- | --- | --- |
| Target | `HapticMeditation` | `HapticMeditation Watch App` |
| Bundle ID | `com.AnomalousResearch.MeditationTimer` | `com.AnomalousResearch.MeditationTimer.watchkitapp` |
| Display name | Boundless Meditation | Boundless Meditation |
| Version / build | 2.0 / `CURRENT_PROJECT_VERSION` | 2.0 / same (must match the iOS app) |
| Deployment target | iOS 26.0 | watchOS 26.0 |
| Team | Anomalous Research LLC (`XPU32D9V4J`), automatic signing | same |
| Capabilities | Background Modes: Audio; HealthKit | Background Modes: Mindfulness session, Workout processing, Audio; HealthKit |

The bundle IDs were renamed from `com.AnomalousResearch.HapticMeditation` (and `com.AnomalousResearch.InfiniteMeditation`) because those identifiers are registered to other teams.

### Where these settings live in Xcode

You don't need to change anything; this is so you can see it and change it later.

1. Click the blue **HapticMeditation** project icon at the top of the Project navigator (left sidebar), then pick a target under **TARGETS**.
2. **Signing & Capabilities** tab:
   - *Signing:* "Automatically manage signing" is checked; Team = Anomalous Research LLC.
   - **HapticMeditation** (iOS) → **Background Modes** → *Audio, AirPlay, and Picture in Picture* is checked. → **HealthKit** is present (no Clinical Records or Background Delivery). The entitlement file is `Config/InfiniteMeditation.entitlements`.
   - **HapticMeditation Watch App** → **Background Modes** → *Session Type: Mindfulness*, plus *Workout processing* and *Audio* checked. → **HealthKit** capability is present (no Clinical Records or Background Delivery). The entitlement file is `Config/InfiniteMeditationWatch.entitlements`.
   - If a capability ever goes missing, click **+ Capability** (top-left of that tab) and add **HealthKit** (or **Background Modes**) back. Xcode writes into the same `Config/` files this repo uses. The first device build after HealthKit was added to the iPhone target may ask automatic signing to enable HealthKit on the App ID `com.AnomalousResearch.MeditationTimer`. Accept that.
3. **Info** tab, for **both** the iOS target and the watch target: *Privacy – Health Share Usage Description* and *Privacy – Health Update Usage Description* are the texts shown in the Health permission prompt. The iPhone strings are about Mindful Minutes. The watch strings cover Mindful Minutes and the optional long-session workout.
4. **General** tab: Display Name, Version (2.0) and Build. Bump **Build** for every TestFlight upload, or let `Tools/testflight.sh` do it.
5. The scheme is shared (**Product › Scheme › Manage Schemes…**, "Shared" checked), so `xcodebuild` works from a fresh clone.

## Building and running in Xcode

1. Open `HapticMeditation.xcodeproj` in Xcode 26 or later.
2. In the toolbar, choose the **HapticMeditation** scheme and your iPhone as the run destination. Run (⌘R). The watch app installs alongside it on your paired watch (Watch app on iPhone › My Watch › Available Apps if it doesn't appear).
3. To debug the watch app directly, choose the **HapticMeditation Watch App** scheme (Xcode creates it automatically) and your watch as destination.
4. Unit tests: choose the **HapticMeditation** scheme and press ⌘U (or `xcodebuild test -scheme HapticMeditation -destination 'platform=iOS Simulator,name=iPhone 17'`). The session-sync and history tests are also runnable without Xcode, from the repo root: `swift test`.

The first time, Xcode may ask to register your devices and create provisioning profiles. Accept; automatic signing handles it.

## TestFlight release

### One-time App Store Connect setup

1. **App IDs** (developer.apple.com › Certificates, IDs & Profiles › Identifiers). Automatic signing registers `com.AnomalousResearch.MeditationTimer` and `…MeditationTimer.watchkitapp` the first time you build for a device. Confirm **both** identifiers have **HealthKit** enabled; automatic signing turns it on because of the entitlements, but check if signing fails. The iPhone app writes Mindful Minutes, so its App ID needs HealthKit too, not only the watch.
2. **App record** (appstoreconnect.apple.com › Apps › **+** › New App): Platform **iOS**, Name "Boundless Meditation" (must be unique on the App Store; tweak if taken), Primary language English, Bundle ID `com.AnomalousResearch.MeditationTimer`, SKU e.g. `infinite-meditation`, Full Access. The watch app ships inside the iOS app, so it needs no separate record.
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
1. Settings › Background › Mode **Long session (workout)**. Leave *Save workout to Health* off.
2. Begin. Allow the Health prompt (workouts). The status shows "Long session · wrist-down taps on" and the workout indicator appears.
3. Wrist down for over 60 minutes (or at least 15 to sanity-check it); taps continue at every mark.
4. End. With *Save workout to Health* off, no workout appears in the Fitness app. Turn it on, run a short session, end, and confirm a Mind & Body workout appears. Mindful Minutes are a separate entry (see below) and still appear when the workout was discarded.
5. Deny workout permission (Settings › Health › Data Access on the watch, or reinstall) and Begin. Expect a yellow note that it fell back to Standard mode, with taps still working.

**Pause on the iPhone with the wrist down**
1. Open both apps. On the watch, tap **Begin** and confirm the status turns green. On the iPhone, confirm the timer is running too.
2. Lower your wrist and leave it down so the watch screen turns off. Wait until a haptic would still be able to fire (the watch app is backgrounded, not force-quit).
3. On the iPhone, tap **Pause**.
4. Raise your wrist. The watch timer must be paused, not still counting, and it must not tap at the next mark.
5. Tap **Resume** on the iPhone with the wrist down again, then raise the wrist: the watch is running and the elapsed time matches the phone within a second or two.
6. End on the iPhone with the wrist down, then raise the wrist: the watch session is over (no green "taps on" status, haptics stopped).

**Mindful Minutes**
1. On the iPhone, Settings › Health › *Mindful Minutes* is on. Begin, sit for at least a few seconds, optionally Pause for a bit, Resume, then End. Allow the Health prompt the first time (mindful sessions).
2. Open the Health app › Browse › Mental Wellbeing › Mindful Minutes. The session is there. Its length matches time spent meditating, not the pause. A session with one pause shows two stretches (two samples), not one block that includes the pause.
3. Repeat a mirrored session and End on the watch instead. Allow Health on the watch if asked. Health shows one session, not two copies. The phone's last-session line does not also say it saved Mindful Minutes for that same end.
4. Turn *Mindful Minutes* off, run a short session, End. No new Mindful Minutes row.
5. Long session with *Save workout to Health* off and *Mindful Minutes* on: End. Health has Mindful Minutes and the Fitness app has no new workout.

**History**
1. End a session that lasted at least a second. On the iPhone, tap the clock button at the top left. The sheet lists that session with the date and start time, and the duration, at the top.
2. End another one. It appears above the older row.
3. Swipe the top row left and tap Delete. It disappears. The Mindful Minutes entry in the Health app is still there.
4. End a session on the watch only (phone app not in the foreground). Open History on the iPhone. That watch session appears once.
5. Run one mirrored session and End on either device. History on the phone shows a single row for it, not one from each device. The watch's clock button (top left) shows the same session.
6. Delete that row on the phone, then open History on the watch (or bring the watch app forward). The row stays gone.

**iPhone chime with the phone locked**
1. On the iPhone, tap the sliders icon › Interval **1 min**, Major **Every 2 marks**, *Play chime* on. Preview both chimes; the major one is deeper and rings longer.
2. Begin, then lock the phone (side button) and put it face down.
3. Confirm the soft bowl at 1:00, the deeper bowl at 2:00, and so on, while the phone stays locked.
4. Start music in another app, then start a session: music keeps playing and chimes mix over it.
5. During a session, call the phone (or trigger Siri). After the interruption ends, chimes resume at the next mark.
6. Turn *Play chime* off and Begin: the status says the iPhone won't alert while locked.

**Phone-only (no watch)**
1. On an iPhone with no paired watch (or with the watch app deleted), all controls work and Settings shows no Apple Watch section.

**Mirroring**
1. Open both apps. Begin on the phone: the watch starts too (green status). Pause, Resume and End on either device and the other follows while both are open.
2. Change the interval on the phone; the watch's Settings shows the new value (it syncs even if the watch app is closed).
3. The wrist-down pause case above is the one that used to leave the watch running.

## Chime sounds (provenance)

`InfiniteMeditation/Sounds/chime_minor.wav` and `chime_major.wav` were **synthesized from scratch** for this project by `Tools/generate_chimes.py`. It uses additive synthesis of inharmonic singing-bowl modes with slow beating and exponential decay, written against the Python standard library only. They contain no samples or third-party material, so there is nothing to license or attribute. Re-run `python3 Tools/generate_chimes.py` to regenerate them (deterministic output).

- Regular mark: small bowl around G4 (392 Hz), 7 s.
- Major mark: larger bowl around C4 (262 Hz), 11 s.

## Architecture notes

- `MeditationTimer` (Shared) is the count-up clock and mark scheduler. It stores `accumulated` time plus a `runningSince` date. A single `Task.sleep(..., clock: .continuous)` waits until the next mark, and `handleDueMarks()` decides what fired from wall-clock elapsed time, so late or duplicate wake-ups are harmless. `adopt` snaps that clock to a mirrored snapshot and cancels the scheduler when the snapshot is paused or ended.
- `SessionSnapshot` / `SessionReconciler` (Shared) are the authoritative session. Last writer wins by `updatedAt` (revision, then a more terminal phase, breaks ties). Pausing closes a mindful segment; resuming opens another. Mindful Minutes are one Health sample per uninterrupted segment, so a pause is not counted. Samples carry `HKMetadataKeySyncIdentifier` and `HKMetadataKeySyncVersion`, so if both devices do try to save the same segment, HealthKit keeps one.
- `BackgroundRuntime` (watch) owns the extended runtime or workout session and publishes a `status` the UI always shows. A meditation pause pauses the workout session when one is running. The extended runtime session stays up (watchOS cannot pause it) so a later resume or end can still arrive with the wrist down; the haptic scheduler is what stops the taps. The workout is discarded on end unless *Save workout to Health* is on. Mindful Minutes are written separately and do not depend on that switch.
- `ChimePlayer` (iPhone) owns the audio session and engine.
- `SessionHistoryLog` (Shared) turns an ended snapshot into a row (start time and meditation duration) and merges two logs by session id. A delete stores a tombstone so the other device's copy cannot bring the row back. It does not touch HealthKit.
- `ConnectivityService` (Shared) puts settings, the latest session snapshot, and the history log in the application context, so a later settings push cannot wipe them. It also `sendMessage`s when the other app is reachable and `transferUserInfo`s so a backgrounded watch or phone still receives the pause, end, or history row. Each side reads that context on activation, on reachability changes, and when the scene becomes active.
- The project uses Swift's *default MainActor isolation*. Delegate callbacks from WatchKit, HealthKit and WatchConnectivity are `nonisolated` and hop to the main actor with only `Sendable` values. `swift test` runs the reconciler and history tests on a Linux Swift toolchain; those files import Foundation only.
