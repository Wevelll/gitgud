# CLAUDE.md — Working guide for Day-Dial

Operational guide for coding agents in this repo. **`SPEC.md` is the source of truth for product and design decisions** — read it before any non-trivial change. This file governs *how* we build, not *what*.

Day-Dial is a cross-platform (Win/Mac/Linux/iOS/Android), **local-first**, **agent-controllable** 24-hour time planner + tracker, built in Flutter.

---

## Golden rules (never violate)

These are load-bearing. If a change would break one, stop and flag it instead.

1. **Logic lives in `core`, never in widgets.** The UI and the MCP server are both thin clients of the shared `core` package. No business logic, schema knowledge, or time math in the Flutter widget tree.
2. **`core` is platform-agnostic.** No `dart:io`, no Flutter imports, no platform paths in `core`. It must compile for web. Enforced by package boundaries (see Architecture).
3. **Local-first is absolute.** The app must be fully functional with **no network and no account**. Sync is optional and **off by default**. Never introduce a mandatory server, cloud call, or login on any critical path.
4. **MCP writes require consent; never bypass it.** Every mutating MCP tool goes through the host consent layer. Destructive tools (`delete_block`, etc.) carry `destructiveHint`. No tool silently mutates state.
5. **MCP binds to `127.0.0.1` by default.** LAN exposure is opt-in, **token-gated**, and validates the `Origin` header (DNS-rebinding). Never default-bind to `0.0.0.0`.
6. **No phone-home telemetry.** No analytics/ads without explicit consent, and **none at all on desktop/web**. Nothing about the user's day leaves the device unless the user turned on sync.
7. **Time representation is fixed.** Time-of-day = **minutes since midnight (int)**. Timestamps = ISO 8601. Dates = `YYYY-MM-DD`. Never mix these or pass a `DateTime` where a minute-int is expected.
8. **Segments can wrap midnight** (`end_min < start_min`). Every function that reads, draws, resizes, or queries segments **must** handle the wrap case. Durations within a profile sum to a constant; enforce a 15-min minimum segment length.
9. **Dial labels stay upright.** In compass mode, counter-rotate every label/numeral by the negative of the disc rotation. (Reference behavior is in the React prototype.)

---

## Architecture

Enforce the core/UI/MCP seam with **package boundaries**, not discipline:

```
/lib                  Flutter UI app (thin; wiring + rendering only)
  /painters           CustomPainter for the dial (both compass + clock modes)
  /screens /widgets
/packages/core        Platform-agnostic Dart: models, schema, segment math,
                      recurrence, plan-vs-actual stats, CRDT doc. NO Flutter, NO dart:io.
/packages/mcp         MCP server over core (stdio + Streamable HTTP). Consent-gated writes.
/native/ios           WidgetKit / watchOS complication (SwiftUI)
/native/android       Home-screen widget / Wear tile (Jetpack Glance)
/test                 Tests — core logic is the priority
```

- Consider `melos` for the monorepo (optional).
- `core` is a pure Dart package so it *cannot* import Flutter — the invariant is structural.
- The dial in `/native/*` is a **separate, simpler native re-implementation** (a static arc fed by shared data via `home_widget`); it does not reuse the Flutter painter.

---

## Conventions

- **Dart null-safety**, `dart format` (default 80-col off is fine — match repo), `flutter analyze` clean. Lints: `flutter_lints` (or `very_good_analysis` if we want stricter — pick one, don't mix).
- **State management: keep it minimal.** provider/Riverpod-level is the ceiling. Since all real logic is in `core`, the UI layer is just wiring — do not reach for a heavyweight DI/state framework.
- **Dependencies: minimal, and justify additions.** Before adding a package, prefer stdlib/existing deps; if adding, note *why* in the PR/commit and confirm it doesn't pull `core` off platform-agnostic. Flag heavy or abandoned deps.
- Small, focused commits with clear messages. Prefer editing existing files over creating parallel ones.
- No secrets, keys, or tokens in code or history.
- No `localStorage`/`sessionStorage` assumptions — persistence is SQLite (native) / IndexedDB (web fallback) via the store layer, never ad-hoc.

---

## Testing

Core logic is where bugs hurt most — it must have unit tests:
- Segment resize + **midnight-wrap** edge cases; min-length enforcement; boundary shared-edge math.
- Recurrence rule evaluation + completion-per-date.
- Plan-vs-actual variance math.
- CRDT merge (concurrent edits converge).
- MCP tool handlers: consent gate is exercised; destructive tools flagged.

UI/painter changes: a golden test for the dial at a few times of day is worth it (catches label-rotation and wrap regressions).

**Definition of done:** compiles on desktop + web targets, `flutter analyze` clean, new/changed core logic covered by tests, invariants above upheld.

---

## Commands

```
flutter run -d macos|windows|linux|chrome     # dev
flutter test                                  # all tests
dart format . && flutter analyze              # before commit
dart test packages/core                       # core-only
# Build per platform: flutter build <target> — fill in signing/native steps as they land
```
(Project-specific build/signing/MCP-launch commands go here as they're set up.)

---

## Known risks / open decisions (see SPEC §11)

- **CRDT-in-Dart is the shakiest assumption.** Dart's CRDT ecosystem is thinner than JS's. **Spike this early** on a throwaway branch (prove two devices converge) before building sync into the app. Be ready to fall back to last-write-wins with vector clocks per record if a full CRDT lib isn't ergonomic. Don't let this block the local-only MVP.
- Native widget seam (Phase 2): budget real native work; the dial-as-widget is authored per-platform.
- Undecided: midnight-top vs noon-top; CRDT library choice; whether mobile hosts its own MCP server or stays client-only in v1; RuStore-first vs direct-desktop-first for revenue.

---

## Working with the human

- Give **honest tradeoffs, including recommending against something** — do not rubber-stamp. Direct technical depth is preferred over hand-holding.
- **Ask before large refactors** or architecture changes; propose, don't surprise.
- Favor low-maintenance, low-dependency solutions. When unsure between "clever" and "simple," pick simple and say why.
