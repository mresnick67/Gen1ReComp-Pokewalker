-- Pokéwalker: Apple Health steps become party EXP (iOS builds).
--
-- The Swift side (mobile/ios/native/GRHealthBridge.swift) owns HealthKit:
-- love.system.syncHealthSteps() requests read access on first use, counts
-- steps since the last sync anchor, and drops steps_pending.json in the
-- save dir.  This mod consumes that file at quiet moments (save loaded, map
-- transitions, battle end), converts steps to EXP, and applies level-ups
-- with the same stat math the engine uses.
--
-- Opt-in: everything is inert until SYNC STEPS is enabled in this mod's
-- options (the HealthKit permission sheet appears on first enable).  On
-- non-iOS platforms love.system.syncHealthSteps does not exist and the mod
-- stays dormant.  Sandboxed engines (mods 2026-08+) block love.system
-- entirely; the mod is dormant there too -- see bridge() below and
-- upstream issue #1183 for the scoped seam that will restore sync.
--
-- v0.3.0 adds three systems that are ALSO opt-in and default off, so an
-- untouched install behaves exactly like v0.2.x:
--   WATTS       steps earn a currency (economy.lua) spent in a START-menu
--               shop (shop.lua) on items and radar charges (radar.lua)
--   STREAKS     consecutive daily-goal days multiply EXP+watt rates
--   STEP GIFTS  pokémon granted at journey-step milestones (gifts.lua)
-- Watts and steps banked mid-session are written with the game save, so
-- quitting without saving loses them (same as this mod's EXP credit).

local PENDING = "steps_pending.json"

return function(mod)
  mod.options:define({
    { key = "enabled", label = "SYNC STEPS", type = "toggle", default = false },
    { key = "rate", label = "STEPS PER EXP", type = "choice", default = "20",
      choices = { { "10", "10" }, { "20", "20" }, { "50", "50" } } },
    { key = "target", label = "GIVE EXP TO", type = "choice", default = "lead",
      choices = { { "LEAD MON", "lead" }, { "WHOLE PARTY", "party" } } },
    { key = "watts", label = "WATTS", type = "toggle", default = false },
    { key = "streaks", label = "STREAKS", type = "toggle", default = false },
    { key = "goal", label = "DAILY GOAL", type = "choice", default = "5000",
      choices = { { "3000", "3000" }, { "5000", "5000" },
                  { "10000", "10000" } } },
    { key = "gifts", label = "STEP GIFTS", type = "toggle", default = false },
  })

  local Json = require("src.link.Json")
  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  local game
  -- Which generation the running game is.  Gold's ROM extractor writes
  -- constants.generation = 2; Gen 1 datasets (and older engines) carry
  -- nothing, so the default is 1.  Set in game.ready, before any credit.
  local gen = 1
  local function isGen2() return gen >= 2 end
  -- Clock seam shared with Economy (see mod.exports.setNow): os.time in
  -- production, injectable so tests can drive the sync throttle below and
  -- streak days without sleeping.
  local now = os.time

  -- ------- sibling modules
  -- mod:read + load keeps them addressable through the loader's filesystem
  -- instead of the host package.path, so the mod works the same installed
  -- (zip) as it does in the repo.  A failed sibling logs and degrades to
  -- the base steps->EXP behavior instead of taking the whole mod down.
  local siblings = {}
  local function requireFile(rel)
    if siblings[rel] ~= nil then return siblings[rel] end
    local source = mod:read(rel)
    if not source then
      mod.log:error("%s missing from %s -- reinstall the mod", rel, mod.path)
      return nil
    end
    local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then
      mod.log:error("%s did not compile: %s", rel, tostring(err))
      return nil
    end
    local ok, result = pcall(chunk)
    if not ok then
      mod.log:error("%s failed to load: %s", rel, tostring(result))
      return nil
    end
    siblings[rel] = result
    return result
  end
  local Economy = requireFile("economy.lua")
  local Radar = requireFile("radar.lua")
  local Gifts = requireFile("gifts.lua")
  local Shop = requireFile("shop.lua")
  local Card = requireFile("card.lua")

  local function wattsOn() return Economy ~= nil and mod.options:get("watts") end
  local function streaksOn()
    return Economy ~= nil and mod.options:get("streaks")
  end
  local function giftsOn() return Gifts ~= nil and mod.options:get("gifts") end

  -- v0.2.x buckets predate every v0.3.0 key; keep the step total they
  -- already accumulated and default the rest lazily in code.
  mod.migrations:add("0.3.0", function(bucket)
    bucket.watts = bucket.watts or 0
    bucket.lifetimeSteps = bucket.lifetimeSteps or 0
  end)

  -- Bridge probe.  Three worlds: an engine with the native bridge
  -- (love.system.syncHealthSteps is a function), one without (nil), and a
  -- sandboxed engine (mods 2026-08+) where merely INDEXING love.system
  -- raises.  pcall folds the third into "no bridge", so the mod is
  -- cleanly dormant under the sandbox instead of erroring on every quiet
  -- moment.  Upstream issue #1183 tracks the scoped seam (a
  -- permission-gated steps event) that will re-light sync there.
  local function bridge()
    local ok, fn = pcall(function()
      return love.system and love.system.syncHealthSteps
    end)
    return (ok and fn) or nil
  end

  local function active()
    return bridge() ~= nil and mod.options:get("enabled")
  end

  -- Ask the native side to refresh steps_pending.json.  Async: results are
  -- picked up by a later consume() (next map change / battle end).
  --
  -- Throttled: sync events can land seconds apart (game.ready, then
  -- save.loaded as CONTINUE restores; option toggles in one settings
  -- visit), and iOS app builds (v0.1.51 as of this writing) double-credit
  -- when native syncs overlap -- the bridge re-reads the same anchor while
  -- an earlier query is still in flight, and its pending-file merge adds
  -- the duplicated window.  Keeping requests a cooldown apart keeps them
  -- farther apart than any query's lifetime.  Skipped requests lose
  -- nothing: the native anchor only advances when a sync runs, so the
  -- next allowed sync covers the whole gap.  `force` (flipping SYNC
  -- STEPS on) bypasses the throttle so the permission sheet still
  -- appears the moment the option is enabled.
  local SYNC_COOLDOWN = 30 -- seconds; far beyond any native query's lifetime
  local lastSyncRequest
  local function requestSync(force)
    if not active() then return end
    local t = now()
    -- A negative delta means the wall clock moved backwards (time zone,
    -- manual change): treat it as expired rather than jamming the
    -- throttle shut until the clock catches back up.
    local dt = lastSyncRequest and t - lastSyncRequest
    if not force and dt and dt >= 0 and dt < SYNC_COOLDOWN then return end
    lastSyncRequest = t
    local sync = bridge()
    if sync then sync() end
  end

  -- Add EXP to one mon, bumping levels with the engine's own stat math
  -- (mirrors the rare-candy path in src/inventory/ItemEffects.lua).  On
  -- Gold the field is mon.experience and the stat builder has its own
  -- signature, so src/battle/gen2/Mon.gainExperience owns the whole hop --
  -- cap, stats, HP delta -- and reports the level-up move ids itself.
  -- Returns the EXP actually absorbed, the levels gained, and (Gen 2 only)
  -- the level-up move ids; nil learned means "look them up per level".
  local function applyToMon(mon, xp, data)
    if isGen2() then
      local Mon2 = require("src.battle.gen2.Mon")
      local before = mon.experience or 0
      local res = Mon2.gainExperience(mon, xp, data)
      local levels = {}
      if (res.levels or 0) > 0 then
        for level = res.from + 1, res.to do levels[#levels + 1] = level end
      end
      return (mon.experience or 0) - before, levels, res.learned or {}
    end
    local def = data.pokemon[mon.species]
    if not def or not mon.level then return 0, {} end
    local cap = (data.constants and data.constants.levelCap) or 100
    if mon.level >= cap then return 0, {} end
    local maxExp = Growth.expForLevel(def.growthRate, cap, data.growth_rates)
    local before = mon.exp or 0
    mon.exp = math.min(maxExp, before + xp)
    local absorbed = mon.exp - before
    if absorbed <= 0 then return 0, {} end
    local levels = {}
    local newLevel = Growth.levelForExp(def.growthRate, mon.exp, cap,
                                        data.growth_rates)
    while mon.level < newLevel do
      mon.level = mon.level + 1
      local old = mon.stats
      mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
      mon.hp = math.min(mon.stats.hp,
                        (mon.hp or 0) + (mon.stats.hp - (old and old.hp or 0)))
      levels[#levels + 1] = mon.level
    end
    return absorbed, levels
  end

  -- The credit presents like the rare-candy flow (BagMenu's RARE_CANDY
  -- path): TextBox pages separated by \f (each page waits for A), then a
  -- learn step per level-up move -- auto-learn with a message when a slot
  -- is free, the engine's MoveLearnMenu ("forget which move?") when four
  -- moves are known.  That needs the overworld idle and on top of the
  -- stack, so consume() only fires when it can present; otherwise the
  -- pending file is left alone and the next quiet event retries.
  local function presentable()
    local ow = game and game.overworld
    if not (ow and ow.map and game.stack and game.stack.top) then return false end
    if game.stack:top() ~= ow then return false end
    if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then
      return false
    end
    return true
  end

  local function monName(mon, data)
    local def = data.pokemon[mon.species]
    return mon.nickname or (def and def.name) or mon.species
  end

  -- Gold has no MoveLearnMenu screen (the Gen2* builtins carry no move-learn
  -- picker), so the "forget which move?" choice is recreated from the mod's
  -- own widgets.  B keeps the old moveset, like the vanilla flow's NO.
  local function promptForget(mon, moveId, mdef, data, onDone)
    local Strings = require("src.core.Strings")
    local TextBox = require("src.render.TextBox")
    local entries = {}
    for slot, mv in ipairs(mon.moves) do
      local cur = data.moves[mv.id]
      entries[#entries + 1] = {
        label = (cur and cur.name) or mv.id,
        onSelect = function()
          mon.moves[slot] = { id = moveId, pp = mdef.pp, maxPp = mdef.pp }
          game.stack:push(TextBox.new(game,
            Strings("1, 2 and...\nPoof!\f%s learned\n%s!",
                    monName(mon, data), mdef.name), onDone))
        end,
      }
    end
    game.stack:push(TextBox.new(game,
      Strings("%s wants\nto learn:\f%s!\nForget a move?",
              monName(mon, data), mdef.name), function()
      local menu = mod.ui.Menu.new(game, entries, { tx = 2, ty = 2, tw = 14 })
      menu.onCancel = function()
        game.stack:push(TextBox.new(game,
          Strings("%s was\nnot learned.", mdef.name), onDone))
      end
      game.stack:push(menu)
    end))
  end

  -- One learn step at a time, BagMenu-style: the chain owns its own
  -- continuation so a MoveLearnMenu can sit between two auto-learns.
  -- onDone fires after the last step so evolutions/gifts can follow.
  local function runLearnQueue(queue, data, onDone)
    local Strings = require("src.core.Strings")
    local TextBox = require("src.render.TextBox")
    local i = 0
    local function nextStep()
      i = i + 1
      local entry = queue[i]
      if not entry then
        if onDone then onDone() end
        return
      end
      local mon, moveId = entry.mon, entry.move
      for _, mv in ipairs(mon.moves) do
        if mv.id == moveId then return nextStep() end
      end
      local mdef = data.moves[moveId]
      if not mdef then return nextStep() end
      if #mon.moves < 4 then
        if isGen2() then
          -- the engine's single teaching choke point; emits
          -- pokemon.move_learned like the battle path does
          require("src.battle.gen2.Mon").learnMove(mon, moveId, data)
        else
          table.insert(mon.moves, { id = moveId, pp = mdef.pp })
        end
        game.stack:push(TextBox.new(game,
          Strings("%s learned\n%s!", monName(mon, data), mdef.name), nextStep))
      elseif isGen2() then
        promptForget(mon, moveId, mdef, data, nextStep)
      else
        require("src.ui.Screens").push(game, "MoveLearnMenu", mon, moveId,
                                       nextStep)
      end
    end
    nextStep()
  end

  -- Gold's evolution flow: plan the leveled slots, then chain the engine's
  -- own Gen2EvolutionAnim one slot at a time, exactly as the Gen 2
  -- BattleState:nextEvolution does.  The screen applies the evolution,
  -- writes the party slot back, ticks the pokedex and teaches the new
  -- form's level moves itself.  pcall-guarded: an engine-contract drift
  -- degrades to "no evolution this credit", never a broken credit.
  local function runGen2Evolutions(leveled, onDone)
    local ok, plans = pcall(function()
      local Evolution = require("src.core.gen2.Evolution")
      local flags = {}
      for index, mon in ipairs(game.save.party) do
        if leveled[mon] then flags[index] = true end
      end
      local Palettes = require("src.world.gen2.Palettes")
      return Evolution.plan(game.data, game.save.party, flags,
                            { timeOfDay = Palettes.clockDaytime() })
    end)
    if not ok or type(plans) ~= "table" then
      mod.log:warn("gen2 evolution check unavailable; skipping (%s)",
                   tostring(plans))
      return onDone()
    end
    local Screens = require("src.ui.Screens")
    local i = 0
    local function nextEvolution()
      i = i + 1
      local plan = plans[i]
      if not plan then return onDone() end
      local pushOk, pushErr = pcall(Screens.push, game, "Gen2EvolutionAnim", {
        mon = plan.mon,
        entry = plan.entry,
        index = plan.index,
        party = game.save.party,
        save = game.save,
        onDone = function()
          game.stack:pop()
          nextEvolution()
        end,
      })
      if not pushOk then
        mod.log:warn("gen2 evolution anim failed: %s", tostring(pushErr))
        return onDone()
      end
    end
    nextEvolution()
  end

  local function consume()
    if not (game and active()) then return end
    if not love.filesystem.getInfo(PENDING, "file") then return end
    -- Not a quiet overworld moment: keep the file, retry on the next
    -- event (map.entered fires with via="boot" right as a continued save
    -- lands in the overworld, so an app-open credit shows immediately).
    if not presentable() then return end
    local raw = love.filesystem.read(PENDING)
    if not raw then return end
    local decoded = Json.decode(raw)
    local steps = decoded and tonumber(decoded.steps) or 0
    love.filesystem.remove(PENDING)
    if steps <= 0 then return end

    -- Lifetime steps accrue whenever SYNC STEPS is on: the gift journey
    -- reads it later, so a player who enables STEP GIFTS months in starts
    -- from an honest baseline.
    mod.save:set("lifetimeSteps", mod.save:get("lifetimeSteps", 0) + steps)

    local party = game.save and game.save.party
    if not party or #party == 0 then return end
    local rate = tonumber(mod.options:get("rate")) or 20

    local mult, wattsEarned, bonusPages = 1, 0, {}
    if streaksOn() or wattsOn() then
      mult, wattsEarned, bonusPages = Economy.credit(mod, game, steps, {
        streaks = streaksOn(),
        watts = wattsOn(),
        goal = tonumber(mod.options:get("goal")) or 5000,
      })
    end
    -- with everything off this stays the exact v0.2 arithmetic
    local xp = mult == 1 and math.floor(steps / rate)
      or math.floor(steps / rate * mult)

    local data = game.data
    local total, pages, learnQueue = 0, {}, {}
    local leveled = {}
    local Strings = require("src.core.Strings")
    -- Gen 1 only: Gold has no backing for src.battle.Experience, and its
    -- gainExperience reports the learnable moves itself
    local Experience = not isGen2() and require("src.battle.Experience") or nil
    local targets = {}
    local toParty = mod.options:get("target") == "party"
    if toParty then
      for _, mon in ipairs(party) do targets[#targets + 1] = mon end
    else
      targets[1] = party[1]
    end
    if xp > 0 then
      local share = math.max(1, math.floor(xp / #targets))
      for _, mon in ipairs(targets) do
        local fromLevel = mon.level
        local absorbed, levels, learned = applyToMon(mon, share, data)
        total = total + absorbed
        if #levels > 0 then
          leveled[mon] = true
          pages[#pages + 1] = Strings("%s grew\nto level %d!",
                                      monName(mon, data), mon.level)
          if learned then
            for _, moveId in ipairs(learned) do
              learnQueue[#learnQueue + 1] = { mon = mon, move = moveId }
            end
          else
            local def = data.pokemon[mon.species]
            for level = fromLevel + 1, mon.level do
              for _, moveId in ipairs(Experience.movesLearnedAt(def, level)) do
                learnQueue[#learnQueue + 1] = { mon = mon, move = moveId }
              end
            end
          end
        end
      end
    end

    local giftNext = nil
    if giftsOn() then
      -- first credit with gifts on snapshots the journey base; kept across
      -- toggle cycles so re-enabling never re-baselines (or re-grants)
      if mod.save:get("milestoneBase") == nil then
        mod.save:set("milestoneBase", mod.save:get("lifetimeSteps", 0))
      end
      giftNext = Gifts.pending(mod)
    end

    if total <= 0 and wattsEarned <= 0 and #bonusPages == 0
        and not giftNext then
      return
    end
    mod.log:info("credited %d steps -> %d EXP (%d level-up pages, %d learnable)",
                 steps, total, #pages, #learnQueue)

    -- Every \n line must stay within the TextBox's 18-column budget: wrapped
    -- continuations scroll through without waiting for A, so an over-wide
    -- report reads as "auto-scrolled to the end" on boot.  Pages also stay
    -- at 2 lines -- a third \n line scrolls in silently the same way.
    for i = #bonusPages, 1, -1 do table.insert(pages, 1, bonusPages[i]) end
    if total > 0 then
      local gained = toParty
        and Strings("Your party gained\n%d EXP.", total)
        or  Strings("%s gained\n%d EXP.", monName(targets[1], data), total)
      table.insert(pages, 1, gained)
    end
    table.insert(pages, 1, Strings("You walked\n%d steps!", steps))
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, table.concat(pages, "\f"), function()
      runLearnQueue(learnQueue, data, function()
        -- step level-ups trigger evolutions like any others (closes the
        -- v1 gap; Evolution.checkParty queues one movie at a time and
        -- re-runs the learnset check on the evolved form itself)
        local function afterEvolutions()
          if giftNext then Gifts.grant(mod, game, giftNext) end
        end
        if next(leveled) then
          if isGen2() then
            runGen2Evolutions(leveled, afterEvolutions)
          else
            require("src.pokemon.Evolution").checkParty(game, afterEvolutions,
                                                        leveled)
          end
        else
          afterEvolutions()
        end
      end)
    end))
  end

  -- ------- UI wiring (registered unconditionally; reachable only while
  -- the WATTS option is on, checked per start-menu open)
  if Shop then Shop.register(mod) end
  if Card then Card.register(mod, { gifts = Gifts }) end
  if Shop then
    mod.hooks:wrap("ui.start_menu.items", function(next, g, items)
      local out = next(g, items)
      if type(out) ~= "table" then return out end
      if not mod.options:get("watts") then return out end
      return mod.ui.insertBefore(out, "SAVE", {
        label = "WALKER",
        onSelect = function() mod.ui.push(g, "PokewalkerMenu") end,
      })
    end)
  end
  if Radar then
    Radar.install(mod, function() return mod.options:get("watts") end)
  end

  -- Inter-mod / test surface: the live balance tables and the clock seam.
  mod.exports.milestones = Gifts and Gifts.MILESTONES or nil
  mod.exports.catalog = Shop and Shop.CATALOG or nil
  mod.exports.setNow = function(fn)
    now = fn or os.time
    if Economy then Economy.now = fn end
  end

  -- Per-generation content: swap the Johto tables in on Gold and audit
  -- every content id the active tables name against the running game's
  -- data, so a missing species or item is a logged warning at boot rather
  -- than a silent no-op (or a crash) at grant time.
  local function selectContent()
    local key = isGen2() and "gen2" or "gen1"
    if Radar and Radar.select then Radar.select(key) end
    if Gifts and Gifts.select then Gifts.select(key) end
    if Shop and Shop.select then Shop.select(key) end
    mod.exports.milestones = Gifts and Gifts.MILESTONES or nil
    local data = game and game.data
    if not data then return end
    local function audit(kind, registry, id)
      if id and registry and not registry[id] then
        mod.log:warn("%s id %s missing from this game's data; that entry "
                     .. "cannot be granted", kind, tostring(id))
      end
    end
    if Radar then
      local set = Radar.SETS[key]
      for _, pool in pairs(set.POOLS) do
        for _, e in ipairs(pool) do audit("radar", data.pokemon, e.species) end
      end
      for _, name in ipairs({ "BIRDS", "WATER", "INDOOR", "APEX" }) do
        for _, e in ipairs(set[name] or {}) do
          audit("radar", data.pokemon, e.species)
        end
      end
    end
    if Gifts then
      for _, m in ipairs(Gifts.MILESTONES) do
        audit("gift", data.pokemon, m.species)
        for _, s in ipairs(m.choice or {}) do audit("gift", data.pokemon, s) end
      end
    end
    if Shop then
      for _, row in ipairs(Shop.CATALOG) do audit("shop", data.items, row.item) end
      for _, sid in ipairs(Shop.STONES) do audit("shop", data.items, sid) end
    end
  end

  -- game.ready is the sanctioned way to obtain the Game object; the party
  -- only exists once a save is loaded or created.
  mod.events:on("game.ready", function(payload)
    game = payload.game
    gen = (game.data and game.data.constants
           and game.data.constants.generation) or 1
    selectContent()
    requestSync()
  end)
  mod.events:on("save.loaded", function()
    requestSync()
    consume()
  end)
  mod.events:on("save.created", function() requestSync() end)
  -- Quiet moments where a walk report can safely appear.
  mod.events:on("map.entered", function() consume() end)
  mod.events:on("battle.ended", function() consume() end)
  -- Flipping SYNC STEPS on forces a sync so the HealthKit permission
  -- sheet appears immediately rather than on the next boot; every other
  -- option change goes through the throttle (its sync was only ever a
  -- freshness nicety, and unthrottled toggle bursts are one of the
  -- overlap patterns the throttle exists to prevent).
  mod.events:on("mod.options_changed", function(p)
    local enabledFlippedOn = p ~= nil and p.mod == mod.id
      and p.key == "enabled" and p.value == true
    requestSync(enabledFlippedOn)
  end)
end
