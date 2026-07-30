# Changelog

All notable changes to this mod are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.1] - 2026-07-30

### Added

- Android support documentation: the Android build's step bridge counts
  steps with the hardware step counter (`TYPE_STEP_COUNTER`) — no Health
  app required. The mod's Lua is unchanged; it simply lights up wherever
  `love.system.syncHealthSteps` exists.

### Changed

- Renamed to "Pokewalker (Step Sync)"; metadata no longer implies the mod
  is Apple-only.

## [1.0.0] - 2026-07-30

### Added

- Opt-in SYNC STEPS option: Apple Health step counts (delivered by the iOS
  build's native bridge as `steps_pending.json`) convert to EXP.
- STEPS PER EXP option (10 / 20 / 50, default 20).
- GIVE EXP TO option: lead mon (default) or whole party split.
- Level-ups applied with the engine's growth curves and rare-candy stat
  math; walk-report textbox at quiet moments.
- Guardrails: steps anchored to the last sync (never credited twice),
  50,000-step clamp per sync, engine `levelCap` respected.
