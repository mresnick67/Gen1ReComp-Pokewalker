-- Standalone: luajit mods/pokewalker/tests/pokewalker_test.lua
-- Exercises the stated effect: opt-in gating, the native-bridge seam,
-- steps converting to EXP through the engine's own growth math, and the
-- rare-candy-style credit presentation (paged report + move learning).
-- v0.3.0 sections cover the opt-in economy: watts, the shop, radar
-- charges, gift milestones, streaks, and the out-of-battle evolution fix.
--
-- Shipped-mod suites are auto-run by the ROM-free T4 tier, so this runs
-- against the committed fixture dataset (T.fixtures), never data/generated.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

-- The native step bridge only exists inside the iOS/Android apps; stand it
-- in so the mod sees the same surface it does on device.
local syncCalls = 0
love.system = love.system or {}
love.system.syncHealthSteps = function()
  syncCalls = syncCalls + 1
  return true
end

-- The credit presents through TextBox pushes and the MoveLearnMenu screen;
-- fake both seams so the chain can be driven headlessly.  Originals are
-- restored at the end -- T4 suites share one process.
local savedTextBox = package.loaded["src.render.TextBox"]
local savedScreens = package.loaded["src.ui.Screens"]
local savedMusic = package.loaded["src.core.Music"]
local shown, menuCalls, pushed = {}, {}, {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone)
    return { __text = text, __onDone = onDone }
  end,
}
package.loaded["src.ui.Screens"] = {
  push = function(_, id, mon, moveId, cb)
    menuCalls[#menuCalls + 1] = { id = id, mon = mon, move = moveId }
    if cb then cb() end
  end,
}
package.loaded["src.core.Music"] = {
  play = function() end,
  stop = function() end,
  restoreMap = function() end,
  special = function() return nil end,
}
-- Modules that capture the fakes above as module-locals when THEY load:
-- evict any prior copy so they rebind to the fakes here, and restore the
-- prior copies on exit so later suites in this process see reality.
local rebindWithFakes = {
  "src.pokemon.Evolution", "src.script.Commands", "src.battle.BattleState",
}
local preloaded = {}
for _, name in ipairs(rebindWithFakes) do
  preloaded[name] = package.loaded[name]
  package.loaded[name] = nil
end
-- force Evolution's headless (text) path instead of the EvolutionState movie
local savedImage = love.image
love.image = nil

local run = T.sdk.loadMod("mods/pokewalker", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local events = run.loader.events
local Growth = require("src.pokemon.Growth")
local Pokemon = require("src.pokemon.Pokemon")
local mon = Pokemon.new(Data, "FIXMON_A", 5)

-- A quiet overworld: idle script runner, overworld on top of the stack.
local ow = { map = {}, runner = { isRunning = function() return false end } }
local stackTop = nil
local game = {
  data = Data,
  save = {
    party = { mon },
    inventory = {},
    player = { name = "RED", id = 1234 },
  },
  overworld = ow,
  stack = {
    top = function() return stackTop end,
    push = function(_, state)
      pushed[#pushed + 1] = state
      shown[#shown + 1] = state.__text
      if state.__onDone then state.__onDone() end
    end,
  },
}

-- Dormant until opted in: seeded steps survive every event untouched and
-- the native bridge is never poked (no permission prompt without consent).
love.filesystem.write("steps_pending.json", '{"steps": 20000}')
events:emit("game.ready", { game = game })
events:emit("map.entered", {})
T.check(love.filesystem.read("steps_pending.json") ~= nil,
  "opt-out leaves pending steps untouched")
T.eq(syncCalls, 0, "opt-out never calls the native bridge")

run.loader.modOptions.pokewalker = { enabled = true }

-- Opted in but NOT presentable (overworld not on top): the credit defers
-- and the pending file survives for the next quiet moment.
events:emit("save.loaded", {})
T.check(love.filesystem.read("steps_pending.json") ~= nil,
  "credit defers while the overworld is not on top")
T.check(syncCalls > 0, "opt-in requests a native sync")

-- Presentable, but the mon already knows four moves: the level-7 learnset
-- move must go through the MoveLearnMenu rather than being force-fed.
stackTop = ow
mon.moves = { { id = "FIX_TACKLE", pp = 35 }, { id = "FIX_SCRATCH", pp = 35 },
              { id = "FIX_CUT", pp = 30 }, { id = "FIX_EMBERISH_NOT", pp = 5 } }
local def = Data.pokemon[mon.species]
local expBefore = mon.exp
events:emit("map.entered", {})
T.eq(mon.exp, expBefore + 1000, "20000 steps at 20 steps/EXP = +1000 EXP")
local expectedLevel = Growth.levelForExp(def.growthRate, mon.exp, 100,
                                         Data.growth_rates)
T.check(mon.level > 7, "enough EXP to cross the level-7 learnset entry")
T.eq(mon.level, expectedLevel, "level matches the engine growth curve")
T.check(mon.stats.hp > 0 and mon.hp <= mon.stats.hp,
  "stat recalc keeps HP within the new maximum")
T.check(love.filesystem.read("steps_pending.json") == nil,
  "pending file is consumed exactly once")
T.check(shown[1] ~= nil and shown[1]:find("You walked\n20000 steps!", 1, true) ~= nil,
  "walk report opens the credit")
local leadName = mon.nickname or Data.pokemon[mon.species].name or mon.species
T.check(shown[1]:find(leadName .. " gained", 1, true) ~= nil,
  "lead target names the lead mon, not the party")
T.check(shown[1]:find("\f", 1, true) ~= nil,
  "report pages are \\f-separated so each box waits for A")
T.eq(#menuCalls, 1, "a full moveset routes through the learn menu")
T.eq(menuCalls[1].id, "MoveLearnMenu", "the engine's own menu is used")
T.eq(menuCalls[1].move, "FIX_EMBERISH", "offering the level-7 learnset move")
T.eq(#mon.moves, 4, "nothing is force-forgotten")

-- A fresh mon with a free slot auto-learns with its own message page.
-- Switch to the party target: the report wording must follow the option.
local mon2 = Pokemon.new(Data, "FIXMON_A", 5)
game.save.party = { mon2 }
run.loader.modOptions.pokewalker = { enabled = true, target = "party" }
local shownBefore = #shown
love.filesystem.write("steps_pending.json", '{"steps": 20000}')
events:emit("battle.ended", {})
T.check(shown[shownBefore + 1] ~= nil
    and shown[shownBefore + 1]:find("Your party gained", 1, true) ~= nil,
  "party target keeps the party wording")
local learned = false
for _, mv in ipairs(mon2.moves) do
  if mv.id == "FIX_EMBERISH" then learned = true end
end
T.check(learned, "a free slot auto-learns the level-up move")
local learnPage = false
for _, text in ipairs(shown) do
  if text:find("learned", 1, true) then learnPage = true end
end
T.check(learnPage, "the auto-learn announces itself in a textbox")

-- A consumed file plus more events must not double-credit.
local expAfter = mon2.exp
events:emit("map.entered", {})
T.eq(mon2.exp, expAfter, "no pending file, no phantom EXP")

-- ------- v0.3.0: all-off leaves no economy footprint

local modSave = run.loader.modSave.pokewalker
local exportsPW = run.loader.exports.pokewalker
T.check(modSave.watts == nil, "all-off: no watts key materializes")
T.eq(modSave.lifetimeSteps, 40000, "lifetime steps accrue with SYNC on")

local function sync(steps, event)
  love.filesystem.write("steps_pending.json",
    ('{"steps": %d}'):format(steps))
  events:emit(event or "battle.ended", {})
end

-- ------- v0.3.0: watts accrual

run.loader.modOptions.pokewalker = { enabled = true, watts = true }
game.save.party = { Pokemon.new(Data, "FIXMON_A", 5) }
sync(20000, "map.entered")
T.eq(modSave.watts, 1000, "20000 steps at 20 steps/W = 1000W")
T.eq(modSave.lifetimeSteps, 60000, "lifetime keeps counting")
local wattsPage = false
for _, text in ipairs(shown) do
  if text:find("You earned\n1000W!", 1, true) then wattsPage = true end
end
T.check(wattsPage, "the watt earn announces itself")

-- ------- v0.3.0: radar charges force the next roll

local Runtime = require("src.mods.Runtime")
local vanillaRoll = function() return nil end
local fixedRng = function(a, _) return a end
modSave.radar = { tier = "GOLD" }
local enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "grass", rng = fixedRng })
T.check(enc ~= nil and (enc.species == "ZAPDOS" or enc.species == "MOLTRES"
    or enc.species == "ARTICUNO"), "gold radar forces a bird")
T.eq(enc and enc.level, 50, "birds come at level 50")
T.eq(modSave.radar, false, "the charge is spent when the battle fires")
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "grass", rng = fixedRng })
T.check(enc == nil, "disarmed radar rolls vanilla")
modSave.radar = { tier = "GOLD" }
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "water", rng = fixedRng })
T.eq(enc and enc.species, "ARTICUNO", "surf-fired gold radar rolls Articuno")
modSave.radar = { tier = "SILVER" }
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "grass",
    rng = function(_, b) return b end })
T.eq(enc and enc.species, "SQUIRTLE",
  "the silver radar pool includes the starters")
modSave.radar = { tier = "BLUE" }
run.loader.modOptions.pokewalker = { enabled = true }
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "grass", rng = fixedRng })
T.check(enc == nil and type(modSave.radar) == "table",
  "an armed radar stays inert (and unspent) while WATTS is off")
modSave.radar = false

-- ------- v0.3.0: the START-menu row follows the WATTS toggle

run.loader.modOptions.pokewalker = { enabled = true, watts = true }
local menuItems = Runtime.call("ui.start_menu.items",
  function(_, items) return items end, game, { { label = "SAVE" } })
T.check(menuItems[1] ~= nil and menuItems[1].label == "WALKER",
  "WALKER row inserted before SAVE")
run.loader.modOptions.pokewalker = { enabled = true }
menuItems = Runtime.call("ui.start_menu.items",
  function(_, items) return items end, game, { { label = "SAVE" } })
T.eq(#menuItems, 1, "no WALKER row while WATTS is off")

-- ------- v0.3.0: the watt shop

run.loader.modOptions.pokewalker = { enabled = true, watts = true }
local Bag = require("src.inventory.Bag")
local factory = Data.screens and Data.screens.PokewalkerShop
T.check(factory ~= nil, "PokewalkerShop screen registered")
local screen = (factory.new or factory)(game)
local list = screen.list
T.check(list ~= nil and #list.items == 13, "the catalog fills the shop")
for _, it in ipairs(list.items) do
  -- label draws from tile 2, price right-aligns to tile 19: past 17
  -- combined chars they collide (the DIAMOND RADAR overlap bug)
  T.check(#it.label + #it.right <= 17, "shop row fits: " .. it.label)
end
local function rowFor(match)
  for _, it in ipairs(list.items) do
    local v = it.value
    if v.item == match or v.radar == match
        or (match == "stones" and v.stones)
        or (match == "shield" and v.shield) then
      return it
    end
  end
end

modSave.watts = 10000
list.onChoose(rowFor("POKE_BALL"))
local qbox = pushed[#pushed]
T.check(qbox.onDone ~= nil, "stackable items open the quantity box")
qbox.onDone(3)
local cbox = pushed[#pushed]
T.check(cbox.onChoose ~= nil, "purchases confirm through YES/NO")
cbox.onChoose(true)
T.eq(game.save.inventory.POKE_BALL, 3, "bought 3 poke balls")
T.eq(modSave.watts, 10000 - 150, "watts debited by quantity x price")

modSave.watts = 10
list.onChoose(rowFor("MASTER_BALL"))
T.check(tostring(list.footer):find("Not enough", 1, true) ~= nil,
  "insufficient watts refuses up front")
T.eq(modSave.watts, 10, "refusal costs nothing")

modSave.watts = 6000
list.onChoose(rowFor("BLUE"))
pushed[#pushed].onChoose(true)
T.check(type(modSave.radar) == "table" and modSave.radar.tier == "BLUE",
  "buying a radar arms it immediately")
T.eq(modSave.watts, 5500, "radar purchase deducts watts")
list.onChoose(rowFor("GOLD"))
T.check(tostring(list.footer):find("already armed", 1, true) ~= nil,
  "one charge at a time")
T.eq(modSave.watts, 5500, "the blocked purchase costs nothing")
modSave.radar = false

list.onChoose(rowFor("shield"))
pushed[#pushed].onChoose(true)
T.eq(modSave.shield, true, "streak shield held after purchase")
T.eq(modSave.watts, 5250, "shield costs 250W")
list.onChoose(rowFor("shield"))
T.check(tostring(list.footer):find("already hold", 1, true) ~= nil,
  "only one shield at a time")

local wattsBefore = modSave.watts
list.onChoose(rowFor("stones"))
local stoneMenu = pushed[#pushed]
T.check(stoneMenu.items ~= nil and #stoneMenu.items == 5,
  "the stone picker offers all five stones")
stoneMenu.items[2].onSelect()
pushed[#pushed].onChoose(true)
T.eq(game.save.inventory.WATER_STONE, 1, "the chosen stone is granted")
T.eq(modSave.watts, wattsBefore - 1000, "stones cost a flat 1000W")

local filler = 1
while Bag.slots(game.save) < Bag.capacity(game.data) do
  Bag.add(game.save, "FILLER_" .. filler, 1)
  filler = filler + 1
end
wattsBefore = modSave.watts
list.onChoose(rowFor("GREAT_BALL"))
pushed[#pushed].onDone(1)
pushed[#pushed].onChoose(true)
T.check(game.save.inventory.GREAT_BALL == nil, "a full bag refuses the item")
T.eq(modSave.watts, wattsBefore, "the refused purchase costs nothing")
T.check(tostring(list.footer):find("can't carry", 1, true) ~= nil,
  "the full bag speaks up")
game.save.inventory = {}
game.save.bagOrder = nil

-- ------- v0.3.0: streaks (driven clock)

run.loader.modOptions.pokewalker =
  { enabled = true, watts = true, streaks = true }
game.save.party = { Pokemon.new(Data, "FIXMON_A", 5) }
modSave.watts = 0
modSave.shield = false
local DAY = 86400
local clock = os.time({ year = 2026, month = 1, day = 5, hour = 12 })
exportsPW.setNow(function() return clock end)

sync(3000)
T.eq(modSave.streak or 0, 0, "3000 steps misses the 5000 daily goal")
sync(3000)
T.eq(modSave.streak, 1, "same-day syncs accumulate toward the goal")
for _ = 1, 6 do
  clock = clock + DAY
  sync(6000)
end
T.eq(modSave.streak, 7, "seven goal days in a row")
T.eq(modSave.bestStreak, 7, "best streak tracks")
local weeklyPage = false
for _, text in ipairs(shown) do
  if text:find("7-day streak!", 1, true) then weeklyPage = true end
end
T.check(weeklyPage, "the completed week announces its bonus")

local wattsAt7 = modSave.watts
clock = clock + DAY
sync(6000)
T.eq(modSave.streak, 8, "day 8 continues the streak")
T.eq(modSave.watts - wattsAt7, math.floor(6000 / 20 * 1.25),
  "watt earn rides the streak multiplier")

modSave.shield = true
clock = clock + 2 * DAY
sync(6000)
T.eq(modSave.streak, 9, "the shield bridges exactly one missed day")
T.eq(modSave.shield, false, "the shield is consumed")
local shieldPage = false
for _, text in ipairs(shown) do
  if text:find("Streak Shield", 1, true) then shieldPage = true end
end
T.check(shieldPage, "the shield announces the save")

modSave.shield = true
clock = clock + 3 * DAY
sync(6000)
T.eq(modSave.streak, 1, "two missed days break the streak")
T.eq(modSave.shield, true, "a shield only spends on one-day gaps")
modSave.shield = false

for _ = 1, 29 do
  clock = clock + DAY
  sync(6000)
end
T.eq(modSave.streak, 30, "back up to thirty days")
T.eq(game.save.inventory.MASTER_BALL, 1, "day 30 grants the master ball")
clock = clock + DAY
sync(6000)
T.eq(modSave.streak, 31, "the streak keeps counting")
T.eq(game.save.inventory.MASTER_BALL, 1, "the ball is granted exactly once")

-- ------- v0.3.0: gift milestones (journey steps, no retroactive grants)

run.loader.modOptions.pokewalker = { enabled = true, gifts = true }
local ms = exportsPW.milestones
T.check(type(ms) == "table" and ms[1].at == 10000, "milestone ladder exported")
local savedMs = {}
for i, v in ipairs(ms) do savedMs[i] = v end
for i = #ms, 1, -1 do ms[i] = nil end
-- fixture stand-ins: the real ladder's species aren't in the fixture set
ms[1] = { at = 10000, species = "FIXMON_C", level = 5 }
ms[2] = { at = 15000, choice = { "FIXMON_A", "FIXMON_C" }, level = 20 }
ms[3] = { at = 900000, species = "FIXMON_B", level = 10 }

game.save.party = { Pokemon.new(Data, "FIXMON_A", 5) }
sync(20000)
T.eq(#game.save.party, 1, "enabling gifts is not retroactive")
T.check(modSave.milestoneBase ~= nil, "the journey base is snapshotted")
sync(20000)
T.eq(#game.save.party, 2, "crossing 10k journey steps grants the gift")
T.eq(game.save.party[2].species, "FIXMON_C", "the right species arrives")
T.check(modSave.milestonesGranted["10000"] == true, "the grant is recorded")
sync(1000)
local choiceMenu = pushed[#pushed]
T.check(choiceMenu.items ~= nil and #choiceMenu.items == 2,
  "a choice milestone offers its menu (one grant per quiet moment)")
choiceMenu.items[1].onSelect()
T.eq(#game.save.party, 3, "the chosen mon is granted")
T.eq(game.save.party[3].species, "FIXMON_A", "the first choice was taken")
T.check(modSave.milestonesGranted["15000"] == true, "the choice is recorded")
sync(1000)
T.eq(#game.save.party, 3, "no phantom grants below the next threshold")
for i = #ms, 1, -1 do ms[i] = nil end
for i, v in ipairs(savedMs) do ms[i] = v end

-- ------- v0.3.0: step level-ups trigger evolutions (v1 gap closed)

run.loader.modOptions.pokewalker = { enabled = true }
local monE = Pokemon.new(Data, "FIXMON_A", 14)
game.save.party = { monE }
local needed = Growth.expForLevel(Data.pokemon.FIXMON_A.growthRate, 16,
                                  Data.growth_rates) - monE.exp
local evoShownFrom = #shown
sync(needed * 20 + 19, "map.entered")
T.eq(monE.species, "FIXMON_B", "step level-ups now evolve")
T.check(monE.level >= 16, "the evolution level was reached")
local evoPage = false
for i = evoShownFrom + 1, #shown do
  if shown[i]:find("evolving", 1, true) then evoPage = true end
end
T.check(evoPage, "the evolution announces itself")

-- ------- every page of every report respects the 18-column TextBox budget
-- (wider lines soft-wrap and the wrapped continuation scrolls through
-- without waiting for A -- the v0.2.0 auto-scroll bug)

for _, text in ipairs(shown) do
  for line in tostring(text):gmatch("[^\f\n\v]+") do
    T.check(#line <= 18, "report line fits the 18-col box: '" .. line .. "'")
  end
end

-- ------- v0.3.1: sync throttle (driven clock)
-- Sync events seconds apart must reach the native bridge once: iOS app
-- builds (v0.1.51 as of this writing) double-credit when syncs overlap
-- (the bridge re-reads the same anchor while a query is in flight and
-- its pending-file merge adds the duplicate).  The SYNC STEPS enable
-- toggle bypasses the throttle so the permission sheet stays immediate.

local tclock = 100000 -- rebased below every earlier os.time() stamp:
                      -- a backward clock jump must count as expired
exportsPW.setNow(function() return tclock end)
local base = syncCalls
events:emit("game.ready", { game = game })
T.eq(syncCalls, base + 1, "first request (after a backward jump) syncs")
tclock = tclock + 3
events:emit("save.loaded", {})
T.eq(syncCalls, base + 1, "save.loaded 3s after boot is throttled")
tclock = tclock + 3
events:emit("mod.options_changed",
  { mod = "pokewalker", key = "watts", value = true })
T.eq(syncCalls, base + 1, "ordinary option toggles are throttled")
events:emit("mod.options_changed",
  { mod = "pokewalker", key = "enabled", value = true })
T.eq(syncCalls, base + 2, "flipping SYNC STEPS on bypasses the throttle")
tclock = tclock + 31
events:emit("save.loaded", {})
T.eq(syncCalls, base + 3, "an expired cooldown lets the next event sync")

package.loaded["src.render.TextBox"] = savedTextBox
package.loaded["src.ui.Screens"] = savedScreens
package.loaded["src.core.Music"] = savedMusic
for _, name in ipairs(rebindWithFakes) do
  package.loaded[name] = preloaded[name]
end
love.image = savedImage
run.release()
T.finish("pokewalker")
