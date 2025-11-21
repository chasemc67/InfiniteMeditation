# InfiniteMeditation

InfiniteMeditation is an Apple Watch and iPhone app designed to provide a haptic-based stopwatch experience, primarily for meditation and mindfulness sessions. The app starts a stopwatch and delivers distinct haptic feedback at customizable intervals. The iOS companion app allows you to adjust settings that sync seamlessly with your Apple Watch.

## Features

- **Apple Watch First**: The primary experience is on Apple Watch, with iPhone support as a companion app.
- **Customizable Haptic Feedback**: Receive haptic cues at intervals you define (1-60 minutes), synced between iPhone and Watch.
- **iOS Companion App**: Configure haptic interval settings on your iPhone, with automatic sync to your Apple Watch via WatchConnectivity.
- **Extended Runtime**: Uses extended runtime sessions to keep meditation stopwatchs running even when your wrist is down.
- **Simple UI**: Minimal, distraction-free interface designed for focus and mindfulness.

## Development Workflow

- **Code in Cursor**: Most development and code editing is done in Cursor for rapid iteration and AI assistance.
- **Build & Run in Xcode**: Use Xcode for building, running, and deploying to simulators or devices.
- **Project Structure**:
  - `InfiniteMeditation/`: iPhone companion app code
  - `InfiniteMeditation Watch App/`: Apple Watch app code
  - `InfiniteMeditationTests/`, `InfiniteMeditationUITests/`: iPhone tests
  - `InfiniteMeditation Watch AppTests/`, `InfiniteMeditation Watch AppUITests/`: Watch app tests

## Architecture

- **ConnectivityManager**: Shared singleton that manages WatchConnectivity sessions and syncs haptic interval settings between iPhone and Apple Watch.
- **TimerViewModel**: Handles stopwatch logic, extended runtime sessions, and triggers haptic feedback based on customizable intervals.
- **ContentView**: SwiftUI-based UI for both iPhone and Apple Watch platforms.

## Contributing

- Follow best practices when using AI assistance.
- Keep code modular and well-documented.
- Prefer Swift and SwiftUI for UI and logic.
- Test on both Apple Watch and iPhone when possible.
- Use Xcode for interface design, provisioning, and deployment.

## Getting Started

1. Clone the repository.
2. Open the project in Cursor for code editing.
3. Use Xcode to build and run the app on your device or simulator.
4. The iPhone and Apple Watch apps will automatically sync settings via WatchConnectivity.
