# Day-Dial

A cross-platform, **local-first**, **agent-controllable** 24-hour day planner
and tracker built around a rotating dial. Plan your day as a ring of segments,
track what actually happened, and let agents read/edit the day over MCP —
all with no account, no cloud, and no telemetry.

See `SPEC.md` for the full product/technical spec and `CLAUDE.md` for the
working conventions in this repo.

## Highlights

- **The dial:** a 24-hour ring of segments. *Compass mode* rotates the day so
  “now” stays pinned at the top (labels counter-rotate to stay upright);
  *clock mode* keeps midnight at top with a sweeping hand.
- **Plan vs. actual:** segments are the plan; append-only time logs are the
  truth. Variance per category over day/week/month, plus a periodic review
  screen with streaks and calendar load.
- **Recurring tasks & habits** in a “must-do today” tray, with streaks.
- **Read-only calendar overlay** from ICS/CalDAV subscription URLs.
- **Focus timer** that logs an actual for its segment on completion.
- **Export** to CSV / ICS / JSON. Local files only, no upload.
- **MCP server** embedded in the desktop app (loopback by default,
  consent-gated writes, destructive tools flagged) so Claude Desktop/Code and
  other agents can operate on your day.
- **Web companion** that syncs to the desktop hub on localhost and falls back
  to a local in-browser day when no hub is reachable. Fully self-contained
  bundle — no CDN fetches (fonts and CanvasKit ship with the build).
- **Light & dark themes.** Follows the OS by default; cycle
  system → light → dark from the dial toolbar (persisted per device).

## Platforms

| Platform | Status |
| --- | --- |
| Linux | Full desktop hub (SQLite + MCP + web-companion server). Build-verified. |
| Windows | Full desktop hub. Runner scaffolded and configured; build on a Windows machine. |
| macOS | Full desktop hub. Sandbox entitlements for loopback server + calendar fetch included; build on a Mac. |
| Web | Companion client (syncs to a desktop hub; local fallback otherwise). Build-verified. |
| Android | Local store + MCP client (no embedded server in v1). Runner scaffolded and configured; build with the Android SDK. |
| iOS | Local store + MCP client (no embedded server in v1). Runner scaffolded and configured; build on a Mac. |

Native home-screen widgets (WidgetKit / Jetpack Glance) are the next mobile
step and are authored separately per platform (SPEC §8, Phase 2).

## Layout

```
lib/                 Flutter UI (thin; wiring + rendering only)
packages/core        Platform-agnostic Dart: models, segment math, recurrence,
                     stats. No Flutter, no dart:io.
packages/store       SQLite persistence over core's repository interface.
packages/mcp         MCP server + consent layer + localhost data API.
android/ ios/ ...    Per-platform runners.
```

All business logic lives in `packages/core`; the UI and the MCP server are
both thin clients of it.

## Building

```sh
flutter pub get
flutter test                          # widget + golden tests
dart test packages/core               # core logic tests
dart test packages/mcp packages/store

flutter run -d linux|windows|macos|chrome
flutter build linux|windows|macos|web|apk|ios
```

Notes:

- **SQLite:** `package:sqlite3` 3.x bundles its native library through Dart
  build hooks — the first build downloads a hash-pinned prebuilt binary from
  the sqlite3.dart GitHub releases. In offline/sandboxed environments you can
  link the system SQLite instead by adding to the *app's* `pubspec.yaml`:

  ```yaml
  hooks:
    user_defines:
      sqlite3:
        source: system
  ```

  (The `packages/store` and `packages/mcp` test suites already do this for
  their own runs.)
- **Android:** requires core-library desugaring (already configured in
  `android/app/build.gradle.kts`) for `flutter_local_notifications`.
- **Notifications** are local-only on every platform (no push service). On
  Linux delivery uses the session D-Bus and degrades to a log line when no
  bus is available (e.g. headless).
- **App icons** are generated, not hand-maintained: `tool/icons/` renders the
  dial mark into every platform format (Android adaptive + themed monochrome,
  iOS light/dark/tinted, macOS, Windows ICO, web PWA + theme-aware SVG
  favicon, Linux). See `tool/icons/generate.py` for the pipeline.
