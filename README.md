# Pokéwalker (Step Sync) — a Gen1Recomp mod

Disclaimer: This project was 100% created by AI, under my super-vision. 

Your real-world steps become EXP for your Pokémon party — the HeartGold/
SoulSilver Pokéwalker, except it's the phone already in your pocket.

A mod for [gen1recomp](https://github.com/bryanthaboi/gen1recomp)
(the Gen 1 Recompilation Project). Works on **iOS and Android** builds
that ship the native step bridge. Opt-in, data-safe, and dormant on any
platform without the bridge (see [Requirements](#requirements)).

## Install

Everything lives on the
[Releases page](https://github.com/mresnick67/Gen1ReComp-Pokewalker/releases).
Which file you need:

| File | Who it's for |
|---|---|
| `pokewalker-<version>.zip` | The mod itself (all platforms) — everyone needs this one. |
| `gen1recomp-android.apk` | **Android**: the full game app with the step bridge. Sideload it, then import the mod zip (mods ship separately so the mod manager can delete and upgrade them). Or build it yourself (below). |

**iOS** follows the same convention as the original project — no
prebuilt app is distributed; you build it yourself (it's two commands
once Xcode is installed):

```sh
git clone -b pokewalker-bridges https://github.com/mresnick67/gen1recomp
cd gen1recomp
scripts/build_ios.sh --fetch                # first time: fetch LÖVE + build
scripts/build_ios.sh --device --install     # sign + install to your iPhone
```

Full zero-knowledge walkthrough: [`docs/ios-install.md`](https://github.com/mresnick67/gen1recomp/blob/pokewalker-bridges/docs/ios-install.md)
on that branch. Android builders: same branch,
[`docs/android-install.md`](https://github.com/mresnick67/gen1recomp/blob/pokewalker-bridges/docs/android-install.md)
(`scripts/build_android.sh`).

Installing just the mod into an existing app or desktop build:

- **In the launcher:** MODS tab → **Import mod .zip** → pick the zip,
  or drag it onto the window on desktop.
- **iOS:** you can also drop the zip into the app's folder in the Files
  app; it installs on next launch.

Then, in the **mod manager → POKEWALKER → options**, turn on **SYNC
STEPS** and approve the system prompt that appears the first time.

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

| Option | Values | Default |
|---|---|---|
| SYNC STEPS | on / off | **off** |
| STEPS PER EXP | 10 / 20 / 50 | 20 |
| GIVE EXP TO | lead mon / whole party (split) | lead mon |

## Mechanics & guardrails

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

## Requirements

The Lua mod is platform-neutral, but it feeds on a **native step
bridge** that ships in iOS and Android builds of the fork this mod comes
from. Without the bridge the mod loads and stays dormant — safe to
install anywhere.

**Upstream status:** the iOS bridge (with the rest of the fork's iOS
support) has been proposed to mainline gen1recomp in
[bryanthaboi/gen1recomp#452](https://github.com/bryanthaboi/gen1recomp/pull/452).
If that lands, official upstream iOS builds will run this mod as-is.

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

Two reference implementations exist:

- **iOS** — a small Swift class (HealthKit `HKStatisticsQuery` over
  `stepCount`) reached from `wrap_System.cpp` via the ObjC runtime.
- **Android** — a `GameActivity` method reading the hardware
  `TYPE_STEP_COUNTER` sensor (cumulative since boot, anchored in
  SharedPreferences; reboot detection re-anchors without crediting),
  reached over JNI like love-android's existing SAF picker.

Open an issue here if you're porting the bridge to another platform.

## Known limitations

- Level evolutions wait for the next in-battle or rare-candy level —
  walking never evolves a mon out from under you.
- Steps sync on launch/activation; no background delivery yet.

## Developing

From a gen1recomp checkout with this mod at `mods/pokewalker` and an
imported data cache:

```sh
luajit mods/pokewalker/tests/pokewalker_test.lua
python3 tools/modkit.py validate mods/pokewalker --base imported
python3 tools/modkit.py pack mods/pokewalker -o pokewalker-<version>.zip
```

(`pack` defaults to a `.modpkg` extension; releases here use `-o` to
ship the community-standard `.zip`, which is also what the game's
drag-and-drop and Files/USB drop-in scans accept — they match `*.zip`
only.)

## Source & provenance

The buildable source for both app builds is the
[`pokewalker-bridges`](https://github.com/mresnick67/gen1recomp/tree/pokewalker-bridges)
branch of [mresnick67/gen1recomp](https://github.com/mresnick67/gen1recomp),
**forked from [bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp)
`dev` @ [`eef6d8a`](https://github.com/bryanthaboi/gen1recomp/commit/eef6d8a368164f610d13303b2418811781eb2654)**
(2026-07-30). It adds only: the iOS native bridge + build fixes (also
proposed upstream as
[#452](https://github.com/bryanthaboi/gen1recomp/pull/452)), the Android
step bridge, this mod, and the two install guides. Everything else is
untouched upstream code.

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Nintendo, Game Freak,
or The Pokémon Company. This mod contains no ROM-derived content
(`modkit lint` clean).
