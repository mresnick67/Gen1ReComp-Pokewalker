# Changelog

All notable changes to this mod are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
