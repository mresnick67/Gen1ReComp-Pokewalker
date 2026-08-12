# Pokéwalker (Step Sync) — a Gen1Recomp mod

Disclaimer: This project was 100% created by AI, under my super-vision. 

Your real-world steps become EXP for your Pokémon party — the HeartGold/
SoulSilver Pokéwalker, except it's the phone already in your pocket.

A mod for [gen1recomp](https://github.com/bryanthaboi/gen1recomp)
(the Gen 1 Recompilation Project). The native step bridges this mod
relies on are **part of the main project** and ship in the official
releases: **v0.1.45 or later on iOS**, **v0.1.51 or later on
Android**. No patched or sideloaded custom builds needed — official
gen1recomp builds run this mod as-is. It's opt-in, data-safe, and
dormant on any platform without a bridge (desktop included — see
[Requirements](#requirements)).

**Gen 2 ready:** as of v1.0.0 the mod declares and supports the
project's **Gold (Gen 2) beta** — on a Gold save the radar pools,
milestone gifts, and stone shop go Johto ([details below](#on-gold-gen-2)),
while Gen 1 saves keep every original table. Gold needs gen1recomp
**v0.1.78 or later**.

## Install

**1. Get the game** from the official
[gen1recomp releases](https://github.com/bryanthaboi/gen1recomp/releases) —
every release attaches an Android APK (`gen1recomp-<version>-android.apk`)
and an iOS IPA (see upstream's
[`docs/ios-sideload.md`](https://github.com/bryanthaboi/gen1recomp/blob/main/docs/ios-sideload.md)
for installing it), alongside the desktop builds. iOS can also be built
from source with your own free Apple ID
([`docs/ios-install.md`](https://github.com/bryanthaboi/gen1recomp/blob/main/docs/ios-install.md)).

**2. Get the mod** — `pokewalker-<version>.zip` from this repo's
[Releases page](https://github.com/mresnick67/Gen1ReComp-Pokewalker/releases)
(the mod ships separately from the app so the mod manager can delete
and upgrade it). Install it into any build:

- **In the launcher:** MODS tab → **Import mod .zip** → pick the zip,
  or drag it onto the window on desktop.
- **iOS:** you can also drop the zip into the app's folder in the Files
  app; it installs on next launch.

**3. Turn it on** — in the **mod manager → POKEWALKER → options**,
enable **SYNC STEPS** and approve the system prompt that appears the
first time.

### What each platform asks for, and how it counts

- **iOS** — a Health Access sheet requesting **read-only** access to
  Steps. Step history comes from Apple Health (`HKStatisticsQuery` over
  `stepCount`), so every step your iPhone or Apple Watch recorded since
  the last sync is credited — including days you didn't open the game.
- **Android** — on Android 10+ a **Physical activity** permission prompt
  (`ACTIVITY_RECOGNITION`); Android 9 and older need no prompt. Steps
  come straight from the phone's **hardware step counter**, which the OS
  runs continuously — no Health/Fit app needed, and steps count whether
  or not the game is running. One caveat: the hardware counter resets
  when the phone reboots, so steps taken between a reboot and your next
  sync are not credited (the bridge re-anchors honestly instead of
  guessing).

## Options

Everything defaults **off** or to the classic experience — enable
exactly as much as you want:

| Option | Values | Default |
|---|---|---|
| SYNC STEPS | on / off | **off** |
| STEPS PER EXP | 10 / 20 / 50 | 20 |
| GIVE EXP TO | lead mon / whole party (split) | lead mon |
| WATTS | on / off | **off** |
| STREAKS | on / off | **off** |
| DAILY GOAL | 3000 / 5000 / 10000 | 5000 |
| STEP GIFTS | on / off | **off** |

SYNC STEPS is the core steps→EXP loop; WATTS, STREAKS, and STEP GIFTS
layer an economy on top of it (below). Leave them off and the mod is
exactly the classic walk-to-level experience.

## Steps → EXP: mechanics & guardrails

- EXP applies through the engine's own growth curves and rare-candy stat
  math, so levels, stats, and HP top-ups are exact.
- Steps are anchored to the last sync — the same walk is never credited
  twice — and any single sync is clamped to 50,000 steps.
- The engine `levelCap` constant is respected.
- Credits land at quiet overworld moments — including the moment you
  open the app and continue your save — as proper engine textbox pages
  (each waits for the A button): the walk report, who grew, and then any
  move learning.
- **Level-up moves are learned, not skipped**: the credit runs the same
  flow as a rare candy. A free slot auto-learns with a "learned!" box; a
  full moveset opens the game's own "forget which move?" menu, so
  nothing is ever forgotten without asking.

## The watt economy

Turn on **WATTS** and steps also charge a currency, 20 steps = 1W,
spent in a **WALKER** entry that appears in the START menu. Balance
targets a full arc in about a month at 10,000 steps/day (~500W/day).

**Watt shop:**

| Row | Watts | | Row | Watts |
|---|---|---|---|---|
| Poké Ball | 50 | | Evo. stone (pick one) | 1,000 |
| Great Ball | 100 | | Rare Candy | 1,250 |
| Streak Shield | 250 | | Silver Radar | 1,500 |
| Ultra Ball | 250 | | Master Ball | 2,500 |
| Nugget | 500 | | Gold Radar | 5,000 |
| Blue Radar | 500 | | Diamond Radar | 10,000 |
| PP Up | 750 | | | |

**Radar charges** arm the moment you buy one (no bag item) and force a
special encounter on your next steps through grass or water — spent when
the battle fires, win, lose, catch, or flee. One charge at a time.

- **BLUE** — uncommons: Ditto, Tangela, Scyther, Pinsir, Onix
- **SILVER** — Safari Zone exclusives in real battles (Chansey,
  Kangaskhan, Tauros, Dratini) plus the three original starters
- **GOLD** — the legendary birds at Lv.50; where you walk matters
  (surfing rolls Articuno, caves roll Moltres)
- **DIAMOND** — Mewtwo Lv.70, or sometimes Mew Lv.30. Bring that
  Master Ball.

Radar legendaries never interfere with the game's own static
encounters — you can still have the Victory Road Moltres too.

### On Gold (Gen 2)

The same shop, Johto flavor:

- **BLUE** — Dunsparce, Yanma, Aipom, Gligar, Phanpy
- **SILVER** — Misdreavus, Skarmory, Heracross, Larvitar, plus the
  three Johto starters
- **GOLD** — **all six**: the legendary birds *and* the legendary
  beasts at Lv.50, terrain-flavored (surfing rolls Articuno or Suicune,
  caves roll Moltres or Entei)
- **DIAMOND** — one of the five apex legendaries: Celebi Lv.30, Ho-Oh
  Lv.70, Lugia Lv.70, Mew Lv.30, or Mewtwo Lv.70

The stone row adds the **SUN STONE**, and the gift ladder walks Johto —
Togepi at 10k, Elekid *or* Magby at 25k, Smeargle, Shuckle, Miltank,
Larvitar, and Celebi at 300k. On Gold the radar fires on grass and surf
steps (the engine's Gold beta has no headbutt/rock-smash/roamer hooks
yet).

**STREAKS**: hit your DAILY GOAL on consecutive days and both EXP and
watt earnings multiply — ×1.1 at 3 days, ×1.25 at 7, ×1.5 at 14, ×2 at
30 (cap). Every completed week pays +500W, and day 30 hands you a free
Master Ball. The **Streak Shield** (250W, hold one) automatically
bridges exactly one missed day; two or more missed days break the
streak and keep the shield.

**STEP GIFTS**: pokémon join you at journey milestones. The journey
starts counting **when you enable the option** — nothing is granted
retroactively.

| Journey steps | Gift (Gen 1) | Gift (Gold) |
|---|---|---|
| 10,000 | Eevee Lv.5 | Togepi Lv.5 |
| 25,000 | Hitmonlee *or* Hitmonchan Lv.20 | Elekid *or* Magby Lv.20 |
| 50,000 | Porygon Lv.15 | Smeargle Lv.15 |
| 100,000 | Lapras Lv.15 | Shuckle Lv.15 |
| 150,000 | Snorlax Lv.30 | Miltank Lv.30 |
| 200,000 | Aerodactyl Lv.30 | Larvitar Lv.30 |
| 300,000 | Mew Lv.5 | Celebi Lv.5 |

Watts, streaks, and journey progress live inside your game save: they
travel with it, and — like the EXP credit itself — anything banked since
your last in-game SAVE is lost if you quit without saving.

## Requirements

The Lua mod is platform-neutral, but it feeds on a **native step
bridge**, part of mainline gen1recomp:

- **iOS** — official release **v0.1.45 or later**.
- **Android** — official release **v0.1.51 or later**.
- **Gold (Gen 2) saves** — official release **v0.1.78 or later** (the
  first with the Gold beta's mod adapter). Gen 1 saves work on all the
  versions above.

Without a bridge (desktop builds, older releases) the mod loads and
stays dormant — safe to install anywhere.

**Why a bridge at all?** A mod alone genuinely cannot do this. Mods are
Lua inside the LÖVE runtime: there is no sensor or HealthKit API exposed
to Lua, and — the hard blocker on Android — reading the step counter on
Android 10+ requires the `ACTIVITY_RECOGNITION` permission to be
declared in the APK's manifest, which only a build-time change can do.
Hence the small native seam, kept to one function so any build can adopt
it.

### The bridge contract (for porters)

Any platform can light this mod up by providing:

- `love.system.syncHealthSteps()` → `boolean` — kick off an async step
  query (requesting OS permission on first use). On completion, write
  **`steps_pending.json`** to the LÖVE save directory:

  ```json
  { "steps": 4312, "from": "2026-07-30T08:00:00Z", "to": "2026-07-30T17:00:00Z" }
  ```

  Count steps from a persisted anchor (last successful sync) so a walk is
  never delivered twice, and **merge** with an unconsumed pending file
  rather than overwriting it. The mod consumes and deletes the file.

Two reference implementations live in mainline gen1recomp:

- **iOS** — a small Swift class (HealthKit `HKStatisticsQuery` over
  `stepCount`) reached from `wrap_System.cpp` via the ObjC runtime
  ([#452](https://github.com/bryanthaboi/gen1recomp/pull/452)).
- **Android** — a `GameActivity` method reading the hardware
  `TYPE_STEP_COUNTER` sensor (cumulative since boot, anchored in
  SharedPreferences; reboot detection re-anchors without crediting),
  reached over JNI like love-android's existing SAF picker
  ([#489](https://github.com/bryanthaboi/gen1recomp/pull/489)).

Open an issue here if you're porting the bridge to another platform.

## Known limitations

- **Engines with the 2026-08 mod sandbox**: the sandbox blocks the
  seams the native step bridge lives behind, so step sync is paused
  there — the mod stays cleanly dormant (the watt economy still runs on
  banked steps). A scoped replacement API is tracked in
  [bryanthaboi/gen1recomp#1183](https://github.com/bryanthaboi/gen1recomp/issues/1183)
  and a release restoring sync will follow it.
- Steps sync on launch/activation; no background delivery yet.
- Progress banked since your last in-game SAVE (EXP, watts, streaks) is
  lost if you quit without saving — the game has no autosave.

## Developing

From a gen1recomp checkout with this mod at `mods/pokewalker` and an
imported data cache:

```sh
luajit mods/pokewalker/tests/pokewalker_test.lua
luajit mods/pokewalker/tests/pokewalker_gen2_test.lua
python3 tools/modkit.py gen2check mods/pokewalker --strict --notes
python3 tools/modkit.py validate mods/pokewalker --base imported
python3 tools/modkit.py pack mods/pokewalker -o pokewalker-<version>.zip
```

(`pack` defaults to a `.modpkg` extension; releases here use `-o` to
ship the community-standard `.zip`, which is also what the game's
drag-and-drop and Files/USB drop-in scans accept — they match `*.zip`
only.)

## Source & provenance

This repo is the mod's canonical home. The native bridges it depends on
were contributed to
[bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp)
directly: iOS support in
[#452](https://github.com/bryanthaboi/gen1recomp/pull/452) (merged
2026-07-30), the Android step bridge in
[#489](https://github.com/bryanthaboi/gen1recomp/pull/489) (merged
2026-08-01), with
[#464](https://github.com/bryanthaboi/gen1recomp/pull/464) moving the
mod itself out of the upstream tree and into this repo. The historical
[`pokewalker-bridges`](https://github.com/mresnick67/gen1recomp/tree/pokewalker-bridges)
branch (this fork's original combined source for both app builds)
remains available; everything on it besides the bridges and this mod is
untouched upstream code.

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Nintendo, Game Freak,
or The Pokémon Company. This mod contains no ROM-derived content
(`modkit lint` clean).
