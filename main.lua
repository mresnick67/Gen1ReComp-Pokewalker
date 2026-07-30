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
-- Known v1 limits (documented in README.md): level-ups applied here do not
-- prompt for new moves (like over-leveling past a learnset entry with rare
-- candies) and do not trigger level evolutions until the next battle candy
-- or level gained in battle.

local PENDING = "steps_pending.json"

return function(mod)
  mod.options:define({
    { key = "enabled", label = "SYNC STEPS", type = "toggle", default = false },
    { key = "rate", label = "STEPS PER EXP", type = "choice", default = "20",
      choices = { { "10", "10" }, { "20", "20" }, { "50", "50" } } },
    { key = "target", label = "GIVE EXP TO", type = "choice", default = "lead",
      choices = { { "LEAD MON", "lead" }, { "WHOLE PARTY", "party" } } },
  })

  local Json = require("src.link.Json")
  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  local game

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
  local function runLearnQueue(queue, data)
    local Strings = require("src.core.Strings")
    local TextBox = require("src.render.TextBox")
    local i = 0
    local function nextStep()
      i = i + 1
      local entry = queue[i]
      if not entry then return end
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

    local party = game.save and game.save.party
    if not party or #party == 0 then return end
    local rate = tonumber(mod.options:get("rate")) or 20
    local xp = math.floor(steps / rate)
    if xp <= 0 then return end

    local data = game.data
    local total, pages, learnQueue = 0, {}, {}
    local Strings = require("src.core.Strings")
    local Experience = require("src.battle.Experience")
    local targets = {}
    local toParty = mod.options:get("target") == "party"
    if toParty then
      for _, mon in ipairs(party) do targets[#targets + 1] = mon end
    else
      targets[1] = party[1]
    end
    local share = math.max(1, math.floor(xp / #targets))
    for _, mon in ipairs(targets) do
      local fromLevel = mon.level
      local absorbed, levels = applyToMon(mon, share, data)
      total = total + absorbed
      if #levels > 0 then
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
    if total <= 0 then return end
    mod.log:info("credited %d steps -> %d EXP (%d level-up pages, %d learnable)",
                 steps, total, #pages, #learnQueue)

    -- Every \n line must stay within the TextBox's 18-column budget: wrapped
    -- continuations scroll through without waiting for A, so an over-wide
    -- report reads as "auto-scrolled to the end" on boot.
    local gained = toParty
      and Strings("Your party gained\n%d EXP.", total)
      or  Strings("%s gained\n%d EXP.", monName(targets[1], data), total)
    table.insert(pages, 1, gained)
    table.insert(pages, 1, Strings("You walked\n%d steps!", steps))
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, table.concat(pages, "\f"), function()
      runLearnQueue(learnQueue, data)
    end))
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
