# Changelog

All notable changes to this mod are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.0] - 2026-08-15

### Added

- **Step insurance.** Every credit is journaled to the engine's durable
  per-playthrough mod storage *before* it is applied. Quitting without
  an in-game SAVE no longer loses steps: the next load detects the
  shortfall and replays it through the normal flow — EXP, watts,
  streaks, and gift milestones included — announced with a
  "Recovered N steps!" page. (Fixes the lost-100,000-step-milestone
  report from Discord.)
- Recovery also runs after a checkpoint restore, which rewinds mod
  state without a normal save load.

### Notes

- Each save slot has its own journal, so recovery never crosses slots
  or generations.
- Recovered steps count toward the daily goal on the day they are
  recovered, not the days they were walked.
- The journal is device-local: copying a save file to another device
  cannot carry that device's unsaved steps with it.
- If mod storage is ever unavailable, the mod logs one warning and
  behaves exactly like 1.1.0. Engine requirement unchanged (v0.1.84+).

## [1.1.0] - 2026-08-13

### Added

- **Step sync on sandboxed engines.** The engine grew a permission-gated
  steps API (`mod.steps`, RFC 0009 — proposed in
  [#1186](https://github.com/bryanthaboi/gen1recomp/issues/1186), merged
  in [#1226](https://github.com/bryanthaboi/gen1recomp/pull/1226)), and
  the mod now syncs through it: the manifest declares the `steps`
  permission (visible in the mod manager), the engine owns the pending
  file, and the mod only ever sees `{ steps, from, to }`. Behavior is
  otherwise identical — same throttle, same quiet-moment credits, same
  guardrails.

### Changed

- **Requires the 2026-08 sandbox engine release or later.** Older
  engines don't know the `steps` permission and refuse the manifest —
  install [v1.0.1](https://github.com/mresnick67/Gen1ReComp-Pokewalker/releases/tag/v1.0.1)
  there instead (Gen 1 + Gold support, sync included on pre-sandbox
  builds).

## [1.0.1] - 2026-08-12

### Fixed

- **Clean dormancy under the upcoming mod sandbox.** The engine's next
  release runs mods in a sandbox that blocks `love.system` and
  `love.filesystem` — the two seams the native step bridge lives behind.
  v1.0.0 threw an error on every save-load, map change and battle end
  there (on every platform, desktop included). v1.0.1 probes the bridge
  safely and goes fully dormant when it is unreachable: no errors, no
  sync, and the watt economy keeps running on your banked steps.
  Behavior on all current and older engine releases is unchanged.
- **Step sync itself is paused on sandboxed engines** until the engine
  grows a scoped, permission-gated steps API — the sandbox has no
  replacement for the bridge yet. Tracked upstream in
  [bryanthaboi/gen1recomp#1183](https://github.com/bryanthaboi/gen1recomp/issues/1183);
  a follow-up release will restore sync the moment that seam ships.

## [1.0.0] - 2026-08-11

### Added

- **Gen 2 (Gold) support** for gen1recomp's new Gold beta engine
  (v0.1.78+). The manifest declares `"games": ["gen1", "gen2"]`; on a
  Gold save the whole mod runs — steps→EXP, watts, shop, streaks, radar,
  gifts, trainer card — through the Gen 2 engine's own primitives
  (`mon.experience`, Gold's stat builder, its move-teaching choke point,
  and the real evolution movie).
- **Johto content on Gold.** Radar pools go Johto (Dunsparce line
  uncommons; Misdreavus/Skarmory/Heracross/Larvitar plus the three Johto
  starters), the GOLD radar holds **all six** birds AND beasts
  (terrain-flavored: surf rolls Articuno or Suicune, caves Moltres or
  Entei), and the DIAMOND radar is a five-way apex pool — Celebi, Ho-Oh,
  Lugia, Mew, Mewtwo. The milestone ladder walks Johto (Togepi at 10k,
  Elekid-or-Magby, Smeargle, Shuckle, Miltank, Larvitar, Celebi at
  300k), and the stone shop adds the SUN STONE. Gen 1 saves keep every
  original table.
- **Content-id audit.** At boot the active generation's radar pools,
  milestone ladder and shop catalog are checked against the running
  game's data; anything missing degrades to a logged warning instead of
  a silent no-op.

### Notes

- Gold fires the radar's encounter hook from grass and surf steps only
  (no headbutt/rock-smash/roamer hooks yet, an engine limitation).
- Gold has no move-learn screen, so a full moveset opens the mod's own
  "forget a move?" picker; the same flow otherwise.
- Needs a gen1recomp build at v0.1.78 or later for Gold; Gen 1 behavior
  is unchanged on any engine version.

## [0.3.2] - 2026-08-01

### Added

- **In-app updates.** The manifest now declares its GitHub repository
  (`"github": "mresnick67/Gen1ReComp-Pokewalker"`), so the launcher's
  MODS panel can offer **Update** and **Versions** for installed copies,
  and the community mod index tracks new releases automatically. No
  gameplay changes.

## [0.3.1] - 2026-08-01

### Fixed

- **Step double-crediting on iOS.** Sync requests are now throttled to
  one per 30 seconds. iOS app builds (v0.1.51 as of this writing) can
  double-credit steps when two native syncs overlap: the bridge
  re-reads the same
  HealthKit anchor while an earlier query is still in flight, and its
  pending-file merge adds the duplicated window together. The mod used
  to request a sync from several events that land seconds apart (boot,
  then save load; every option toggle), which is exactly that overlap
  pattern. Skipped requests lose no steps — the native anchor only
  advances when a sync runs, so the next allowed sync covers the whole
  gap. Flipping SYNC STEPS on still syncs immediately (the permission
  sheet appears the moment you enable it). Already-inflated totals are
  not retroactively corrected.

## [0.3.0] - 2026-07-30

### Added

All three systems are **opt-in and default off** — an untouched install
behaves exactly like 0.2.x. Balance targets a ~1-month arc at 10,000
steps/day.

- **Watts.** Steps earn a currency (20 steps = 1W) spent in a new
  START-menu WALKER entry: a watt shop (balls, Nugget, PP Up, Rare
  Candy, a pick-your-stone evolution stone row, Master Ball at 2,500W)
  and a Pokéwalker trainer card (watts, lifetime steps, streak, armed
  gear, next milestone).
- **Radar charges.** Shop rows that arm a one-shot forced encounter on
  your next steps through grass or water: BLUE 500W (uncommons), SILVER
  1,500W (Safari Zone exclusives and the three starters), GOLD 5,000W
  (the legendary birds, terrain-flavored), DIAMOND 10,000W (Mewtwo — or
  Mew).
  One charge at a time; spent when the battle fires, win or lose.
- **Gift milestones.** Pokémon granted at journey-step thresholds
  counted from when you enable the option (never retroactive): Eevee at
  10k through Mew at 300k.
- **Streaks.** Hitting a configurable daily step goal on consecutive
  days multiplies EXP and watt earnings (up to ×2 at 30 days), pays a
  weekly watt bonus, and day 30 hands you a free Master Ball. A Streak
  Shield (250W) auto-bridges exactly one missed day.

### Fixed

- Level-ups from steps now trigger level evolutions, exactly like a
  rare candy (previously deferred to the next in-battle level).

## [0.2.1] - 2026-07-30

### Fixed

- The walk report really stops auto-scrolling now: its lines were wider
  than the textbox's 18 columns, and wrapped continuation lines scroll
  through without waiting for A. The report is now two short pages
  ("You walked / N steps!" then the EXP page), each waiting for input.
- The EXP page names your lead Pokemon ("PIKACHU gained 500 EXP.") when
  GIVE EXP TO is set to LEAD MON — the default — instead of always
  saying "Your party gained".

## [0.2.0] - 2026-07-30

### Added

- **Move learning.** Level-up moves crossed while walking are no longer
  skipped: the credit now runs the same flow as a rare candy — a free
  slot auto-learns with a "learned!" box, a full moveset opens the
  engine's own "forget which move?" menu. Nothing is ever forgotten
  without asking.
- **Credit dialog on app open.** The walk report now presents as proper
  engine textbox pages the moment a continued save lands in the
  overworld (each page waits for the A button), followed by any move
  learning.

### Fixed

- The walk report no longer auto-scrolls past its first box: pages are
  now form-feed-separated engine TextBox pages, each waiting for input,
  instead of one overflowing box.
- The credit now waits for a quiet overworld moment (overworld on top of
  the stack, no script running) instead of firing into menus or battle
  teardown; pending steps simply retry at the next opportunity.

## [0.1.0] - 2026-07-30

Initial public release, for iOS and Android builds that ship the native
step bridge (`love.system.syncHealthSteps`).

### Added

- Opt-in SYNC STEPS option (off by default): real-world step counts
  convert to EXP. iOS reads Apple Health (read-only Steps); Android reads
  the hardware step counter (`TYPE_STEP_COUNTER`) — no Health app needed.
- STEPS PER EXP option (10 / 20 / 50, default 20).
- GIVE EXP TO option: lead mon (default) or whole party split.
- Level-ups applied with the engine's growth curves and rare-candy stat
  math; walk-report textbox at quiet moments (save load, map change,
  battle end).
- Guardrails: steps anchored to the last sync (never credited twice),
  50,000-step clamp per sync, engine `levelCap` respected. On Android,
  steps between a phone reboot and the next sync are not credited (the
  hardware counter resets; the bridge re-anchors honestly).
