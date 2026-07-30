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
-- stays dormant.
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

  local function active()
    return love.system.syncHealthSteps ~= nil and mod.options:get("enabled")
  end

  -- Ask the native side to refresh steps_pending.json.  Async: results are
  -- picked up by a later consume() (next map change / battle end).
  local function requestSync()
    if active() then love.system.syncHealthSteps() end
  end

  -- Add EXP to one mon, bumping levels with the engine's own stat math
  -- (mirrors the rare-candy path in src/inventory/ItemEffects.lua).
  -- Returns the EXP actually absorbed and any levels gained.
  local function applyToMon(mon, xp, data)
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
        table.insert(mon.moves, { id = moveId, pp = mdef.pp })
        game.stack:push(TextBox.new(game,
          Strings("%s learned\n%s!", monName(mon, data), mdef.name), nextStep))
      else
        require("src.ui.Screens").push(game, "MoveLearnMenu", mon, moveId,
                                       nextStep)
      end
    end
    nextStep()
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
    local Experience = require("src.battle.Experience")
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
        local absorbed, levels = applyToMon(mon, share, data)
        total = total + absorbed
        if #levels > 0 then
          leveled[mon] = true
          pages[#pages + 1] = Strings("%s grew\nto level %d!",
                                      monName(mon, data), mon.level)
          local def = data.pokemon[mon.species]
          for level = fromLevel + 1, mon.level do
            for _, moveId in ipairs(Experience.movesLearnedAt(def, level)) do
              learnQueue[#learnQueue + 1] = { mon = mon, move = moveId }
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
          require("src.pokemon.Evolution").checkParty(game, afterEvolutions,
                                                      leveled)
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
    if Economy then Economy.now = fn end
  end

  -- game.ready is the sanctioned way to obtain the Game object; the party
  -- only exists once a save is loaded or created.
  mod.events:on("game.ready", function(payload)
    game = payload.game
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
  -- Flipping SYNC STEPS on triggers the HealthKit permission sheet
  -- immediately rather than on the next boot.
  mod.events:on("mod.options_changed", function() requestSync() end)
end
