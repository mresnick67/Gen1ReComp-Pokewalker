# Changelog

All notable changes to this mod are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
