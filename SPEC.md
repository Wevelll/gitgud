# Day-Dial — Product & Technical Spec (v0.1)

A cross-platform, local-first, agent-controllable time planner + tracker built around a rotating 24-hour dial. This is a living design doc / handoff document. Decisions marked **[assumed]** were made on the builder's behalf and can be overridden.

---

## 1. Principles

1. **Local-first.** Each device owns its data (SQLite). The app is fully functional with no account and no network. Sync and cloud are optional add-ons, never requirements.
2. **Plan *and* track.** You have a day, you have a plan for it, you record what actually happened, and you see the variance. Both halves are first-class.
3. **Agent-native.** The day is exposed over MCP so any agent (Claude Desktop/Code, etc.) can read and edit it. This is a primary differentiator, not an add-on.
4. **Cross-platform, desktop included.** Windows, macOS, Linux, iOS, Android. Desktop/Linux support is a headline feature, not an afterthought — every strong competitor is single-platform.
5. **Honest monetization.** Free mobile tier carries ads; paid mobile tier removes them; desktop/web are ad-free. No paywalled "killer features."

---

## 2. Core mechanic — the dial

### 2.1 Layout
A 24-hour dial. Time increases **clockwise** from the top. **[assumed]** Midnight (00:00) at top, noon (12:00) at bottom — pairs naturally with a subtle night→day plate shading; A/B against noon-top later. One full rotation = one day.

The day is a ring of contiguous **segments** (e.g. Sleep / Work / Free + custom). A fixed **now-marker** and a fixed **center hub** (readout) sit above the ring.

### 2.2 Two modes (user toggle)
- **Compass mode (the signature):** the entire day-disc rotates so *now* stays pinned to the fixed top marker. "What's next" is the segment just **clockwise of the marker**, rotating up toward it as time passes. This is the novel interaction — most competitors do the opposite.
- **Clock mode:** the disc is static (midnight fixed at top) and a **hand** sweeps to the current time. Familiar, matches the category norm. Offered for users who prefer it.

Both read from the same model; only the rendering differs.

### 2.3 Non-obvious rules (get these right)
- **Rotation is a slow drift, not a spin.** 0.25°/min is imperceptible in real time. The value is the *snapshot*: one glance = where I am + what's next + time remaining. Do not market "watch it rotate."
- **Labels must stay upright.** In compass mode, counter-rotate every text label/numeral by the negative of the disc rotation so text never tumbles. (This is implemented in the prototype.)
- **Time remaining / next** live in the fixed center hub, not on the moving ring.

### 2.4 Segments
- **Rescalable** by dragging a shared boundary; adjusting one segment's edge moves its neighbor's start (durations always sum to a constant per profile). Enforce a minimum segment length (e.g. 15 min).
- **Custom segments** with name + color, arbitrary count.
- Segments may **wrap midnight** (e.g. Sleep 23:00–07:00): stored as `end_min < start_min`.
- **Day profiles:** distinct segment layouts per profile (e.g. Weekday / Weekend / Deep-work day), each assignable to weekdays. Switching profile swaps the ring.

---

## 3. Recurring untimed tasks
Tasks that must get done but aren't tied to a clock slot ("take meds", "20 min stretch").

- Live in a **"must-do today" tray**, not on the dial.
- Modeled as **unplaced tokens** that can *optionally be dragged onto a free segment* when the user commits to a time — bridging "has to happen" and "when" without forcing calendar-style scheduling.
- **Recurrence rules:** daily / weekly (days-of-week) / interval / specific dates. Completion is tracked per date.

---

## 4. Plan vs. actual (tracking + stats)
- **Planned:** the segments of the active profile = the intended day.
- **Actual:** append-only **time logs** recording what actually happened (start/end + category). Sources: manual, "start/stop now" on a segment, or agent-logged via MCP.
- **Variance:** per-category planned-vs-actual over a range (day/week/month) — e.g. "planned 8h sleep, averaging 6h20 (−1h40)". Simple, honest numbers; charts optional.
- **History:** browse past days, see drift trends over weeks.

---

## 5. Data model (SQLite)

```
profiles(id, name, active_days_mask, is_default)
segments(id, profile_id, start_min, end_min, name, color, sort_order)   -- end_min < start_min = wraps midnight
recurring_tasks(id, label, color, recurrence_rule, created_at, archived)
task_completions(id, task_id, date, completed_at)
time_logs(id, date, start_ts, end_ts, category, segment_id NULL, note, source)   -- actuals, append-only
settings(key, value)
sync_meta(doc_id, clock, ...)   -- CRDT state (see §7)
```

- Times of day: minutes-since-midnight (int). Timestamps: ISO 8601. Dates: `YYYY-MM-DD`.
- **CRDT boundary:** the mutable document (`profiles` + `segments` + `recurring_tasks`) is wrapped in an Automerge/Yjs-style CRDT doc per user so concurrent edits (phone, desktop, agent) merge cleanly. `time_logs` are append-only and merge trivially.

---

## 6. MCP interface

### 6.1 Hosting model
The **desktop app embeds the MCP server** over the shared core (§10).
- **Same machine** (Claude Desktop/Code → app): **stdio** or localhost Streamable HTTP. Zero-config; the common case.
- **LAN** (phone / other agents): **Streamable HTTP** bound to the LAN, advertised via **mDNS/Zeroconf** (`_mcp._tcp`-style, e.g. `daydial.local`), gated by a **pairing token**. Opt-in only — default bind is `127.0.0.1`, and the server validates the `Origin` header (DNS-rebinding protection).
- **Mobile:** acts as an MCP *client* to the hub; may later host its own on-device server.

MCP itself provides **no service discovery** — the mDNS layer is ours to add.

### 6.2 Tool contract
Times accept `"HH:MM"` or minutes-since-midnight; dates ISO; all writes require host-side user consent; destructive tools carry `destructiveHint`.

```
# Read
get_current_block()                          -> { name, color, startsAt, endsAt, minutesRemaining, profile }
get_day(date?)                               -> { date, profile, blocks:[{id,name,color,start,end}], tasks:[...] }
list_upcoming(count=3, from?)                -> [{ name, start, end, inMinutes }]
get_recurring_tasks(status="all", date?)     -> [{ id, label, recurrence, doneToday }]
get_stats(range="week", metric="plan_vs_actual")
                                             -> { perCategory:[{category, plannedMin, actualMin, deltaMin}] }

# Write (consent-gated)
add_block(name, start, end, color?, profile?)          -> block
update_block(id, {name?, start?, end?, color?})        -> block     # move / resize / rename / recolor
delete_block(id)                                       -> ok        # destructive
add_recurring_task(label, recurrence, color?)          -> task
complete_task(id, date?)                               -> ok
switch_profile(profile)                                -> ok
log_actual(category|blockId, start, end, note?)        -> log       # record what actually happened
```

---

## 7. Sync & local-network architecture
- **Off by default.** Standalone local-only works fully.
- **Per-device SQLite** = source of truth; the mutable doc syncs as a **CRDT**.
- **Hub-and-spoke over LAN:** the desktop app runs a sync service; other devices discover it via mDNS + pairing and sync when on the same network ("phone syncs to desktop when home").
- **Optional self-hosted relay:** point devices at the builder's own VPS endpoint for sync-anywhere with no vendor cloud.
- No mandatory central server, ever.

---

## 8. Platform plan & sequencing

**Phase 1 — Desktop (+ web companion).** Flutter desktop on Win/Mac/Linux = the full local-first hub, embedding the MCP server. This is where local-first + MCP + Linux all shine and where the builder dogfoods full functionality. **Web** ships as a *companion client* to the hub (LAN/relay), with a limited **IndexedDB** fallback for view/light-edit when no hub is reachable — a pure web app cannot be truly local-first or host a local MCP server.

**Phase 2 — Mobile (iOS/Android).** Flutter app as an MCP client + local store. **Native widget seam:** home-screen widgets (WidgetKit / Jetpack Glance) and watch complications (WidgetKit-watchOS / Wear Tiles) must be authored natively — the dial-as-widget is re-implemented as a simple native arc fed by shared data (`home_widget` bridges the data). Budget for this; the widget is arguably the primary mobile surface.

---

## 9. Monetization
- **Free mobile tier:** ads, placed on secondary screens (stats/settings), never obstructing the glanceable dial.
- **Paid mobile tier:** removes ads. No feature gating.
- **Desktop/web:** ad-free; distributed directly (own site / package repos); charge directly.

**Regional payout constraints (builder is Russia-based):**
- Google Play blocks payouts to Russian bank accounts (paid/IAP/subscriptions fail; free apps still publish). AdMob/AdSense monetization is paused for Russia-based publishers.
- **Realistic rails:** RuStore (preinstalled on RU Android since Sep 2025; MIR/SBP payments; cross-store payment tool), Yandex ad network for the free tier, or an entity/account in a friendly CIS country. Desktop/web distribution bypasses store gatekeepers — charge via crypto or a foreign processor (as already done on LaborX). Reinforces desktop-first commercially.
- Ad SDKs are tracking-heavy and clash with the local-first/private ethos → prefer a privacy-conscious/regional network and clear consent.

---

## 10. Tech stack
- **UI:** Flutter (all 5 platforms; `CustomPainter`/Canvas for the dial; Impeller for smooth animation; identical rendering everywhere).
- **Core:** a shared data+logic module (schema, segment math, stats) that **both the UI and the MCP server call** — the UI never owns the logic.
- **MCP server:** thin layer over the core (Dart, or a separate Rust/TS process) hosting stdio + Streamable HTTP.
- **Store:** SQLite per device; CRDT lib (Automerge/Yjs-style) for the mutable doc.
- **Native extensions:** SwiftUI/WidgetKit (iOS/watchOS), Jetpack Glance (Android/Wear) for widgets/complications.

---

## 11. MVP scope & roadmap
**MVP (ship this):** dial in both modes • rescalable + custom segments • recurring untimed tasks (tray) • segment-transition notifications • local-only SQLite, no account • embedded stdio MCP server (same-machine) • desktop (Win/Mac/Linux) + one native widget.

**v1:** plan-vs-actual tracking + stats • day profiles • CRDT sync (LAN hub + mDNS pairing) • web companion • Streamable HTTP MCP over LAN.

**Later:** mobile apps + native widgets/complications • self-hosted relay • optional read-only calendar overlay • richer analytics.

**Open decisions / risks:**
- Midnight-top vs noon-top (A/B).
- Which native ad/payment stack per region.
- CRDT library choice (Automerge vs Yjs vs custom LWW).
- Whether mobile hosts its own MCP server or stays client-only in v1.
- Store strategy: RuStore-first vs direct-desktop-first for revenue.
