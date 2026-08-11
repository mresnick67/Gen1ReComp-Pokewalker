-- Standalone: luajit mods/pokewalker/tests/pokewalker_gen2_test.lua
-- Gen 2 (Gold) migration coverage: the mod loads through the SDK's
-- generation=2 seam (the gen2compat gate + registry routing, no Gold boot),
-- the Johto content tables go live once game.ready reports a Gen 2
-- dataset, the shop's way back is the Gen2-prefixed start menu, and a
-- step credit runs the Gen 2 EXP path (mon.experience via
-- src/battle/gen2/Mon.gainExperience).
--
-- Fixture limits (T4 runs ROM-free against T.fixtures): fixture species
-- are FIXMON_*, so real Johto ids are asserted through the selected
-- tables, not through data lookups -- the content-id audit warns for each
-- of them here, which is that seam working as designed.  The gift give is
-- exercised with a fixture stand-in ladder, exactly as the gen1 suite
-- swaps its own ladder.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
-- Gold's ROM extractor writes constants.generation = 2; flipping the
-- fixture is what tells the mod it is running on Gold.
Data.constants = Data.constants or {}
Data.constants.generation = 2

love.system = love.system or {}
love.system.syncHealthSteps = function() return true end

-- Same headless seams as the gen1 suite; restored at the end.
local savedTextBox = package.loaded["src.render.TextBox"]
local savedScreens = package.loaded["src.ui.Screens"]
local shown, screenPushes, pushed = {}, {}, {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone)
    return { __text = text, __onDone = onDone }
  end,
}
package.loaded["src.ui.Screens"] = {
  push = function(_, id, ...)
    screenPushes[#screenPushes + 1] = id
  end,
}

local run = T.sdk.loadMod("mods/pokewalker", { generation = 2, data = Data })
T.eq(run.mod and run.mod.state, "loaded", "loads on a Gold boot ("
  .. tostring(run.mod and run.mod.skipReason) .. ")")
T.eq(#run.errors, 0, "no gen2 load errors (" .. tostring(run.errors[1]) .. ")")

local events = run.loader.events
local Pokemon = require("src.pokemon.Pokemon")
local mon = Pokemon.new(Data, "FIXMON_A", 5)

local ow = { map = {}, runner = { isRunning = function() return false end } }
local game = {
  data = Data,
  save = {
    party = { mon },
    inventory = {},
    player = { name = "GOLD", id = 4321 },
  },
  overworld = ow,
  stack = {
    top = function() return ow end,
    push = function(_, state)
      pushed[#pushed + 1] = state
      shown[#shown + 1] = state.__text
      if state.__onDone then state.__onDone() end
    end,
    pop = function() end,
  },
}

events:emit("game.ready", { game = game })

-- ------- game.ready on a Gen 2 dataset selects the Johto tables

local milestones = run.loader.exports.pokewalker.milestones
T.eq(milestones and milestones[1] and milestones[1].species, "TOGEPI",
  "the Johto milestone ladder is live on Gold")

-- ------- radar: Johto pools, birds AND beasts, five-legendary apex

run.loader.modOptions.pokewalker = { enabled = true, watts = true }
-- the save bucket materializes on the first mod.save:set; seed it so the
-- radar can be armed before any credit has run
run.loader.modSave.pokewalker = run.loader.modSave.pokewalker or {}
local modSave = run.loader.modSave.pokewalker
local Runtime = require("src.mods.Runtime")
local vanillaRoll = function() return nil end
local low = function(a, _) return a end
local high = function(_, b) return b end

modSave.radar = { tier = "BLUE" }
local enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "grass", rng = low })
T.eq(enc and enc.species, "DUNSPARCE", "blue radar rolls the Johto pool")

modSave.radar = { tier = "GOLD" }
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "water", rng = high })
T.eq(enc and enc.species, "SUICUNE", "surf-fired gold radar can roll Suicune")

modSave.radar = { tier = "GOLD" }
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "grass", rng = high })
T.eq(enc and enc.species, "SUICUNE", "the gold pool holds birds AND beasts")

modSave.radar = { tier = "GOLD" }
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "indoor", rng = low })
T.eq(enc and enc.species, "MOLTRES", "cave-fired gold radar keeps the birds")

modSave.radar = { tier = "DIAMOND" }
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "grass", rng = function() return 3 end })
T.eq(enc and enc.species, "LUGIA", "the apex pool includes Lugia")

modSave.radar = { tier = "DIAMOND" }
enc = Runtime.call("encounter.roll", vanillaRoll,
  Data.encounters.FIX_ROUTE,
  { mapId = "FIX_ROUTE", terrain = "grass", rng = low })
T.eq(enc and enc.species, "CELEBI", "the apex pool includes Celebi")
modSave.radar = false

-- ------- the shop's stone picker gains the SUN STONE; EXIT goes to
-- ------- Gen2StartMenu

local factory = Data.screens and Data.screens.PokewalkerShop
T.check(factory ~= nil, "PokewalkerShop screen registered on Gold")
local screen = (factory.new or factory)(game)
local list = screen.list
modSave.watts = 10000
for _, it in ipairs(list.items) do
  if it.value.stones then list.onChoose(it) end
end
local stoneMenu = pushed[#pushed]
T.check(stoneMenu.items ~= nil and #stoneMenu.items == 6,
  "the Gold stone picker offers six stones")
local sawSun = false
for _, entry in ipairs(stoneMenu.items) do
  -- SUN_STONE has no fixture item def, so the label is the raw id
  if tostring(entry.label):find("SUN", 1, true) then sawSun = true end
end
T.check(sawSun, "the sixth stone is the SUN STONE")

local menuFactory = Data.screens.PokewalkerMenu
local walkerMenu = (menuFactory.new or menuFactory)(game)
for _, entry in ipairs(walkerMenu.items) do
  if tostring(entry.label) == "EXIT" then entry.onSelect() end
end
T.eq(screenPushes[#screenPushes], "Gen2StartMenu",
  "EXIT reopens the Gen 2 start menu, not the Gen 1 id")

-- ------- a step credit runs the Gen 2 EXP path

run.loader.modOptions.pokewalker = { enabled = true }
love.filesystem.write("steps_pending.json", '{"steps": 20000}')
events:emit("map.entered", {})
T.check(love.filesystem.read("steps_pending.json") == nil,
  "the credit consumed the pending file")
T.check((mon.experience or 0) > 0,
  "EXP landed on mon.experience (the Gen 2 field)")
T.check(mon.level > 5, "the Gen 2 growth math leveled the mon")
T.check(mon.stats and mon.stats.specialAttack ~= nil,
  "level-ups rebuilt the stats with the Gen 2 builder")
local sawGrew = false
for _, text in ipairs(shown) do
  if tostring(text):find("grew", 1, true) then sawGrew = true end
end
T.check(sawGrew, "the report announces the level-up")

-- ------- the gift give composes the Gen 2 primitives (no give_pokemon
-- ------- seam on Gold); fixture stand-in ladder, like the gen1 suite

-- grant is driven through the live milestone table (the export IS the
-- module's table, so editing it in place is the same swap the gen1 suite
-- does)
local realLadder = milestones
local standIn = { at = 100, species = "FIXMON_C", level = 9 }
for i = #realLadder, 1, -1 do realLadder[i] = nil end
realLadder[1] = standIn
run.loader.modOptions.pokewalker = { enabled = true, gifts = true }
modSave.milestoneBase = 0
modSave.milestonesGranted = {}
love.filesystem.write("steps_pending.json", '{"steps": 200}')
events:emit("map.entered", {})
T.eq(#game.save.party, 2, "the milestone gift landed in the party")
T.eq(game.save.party[2] and game.save.party[2].species, "FIXMON_C",
  "and it is the milestone species")
T.check(game.save.party[2].experience ~= nil,
  "the gift is a Gen 2 mon record (mon.experience)")
T.check(modSave.milestonesGranted["100"] == true,
  "the milestone is marked granted only after landing")

run.release()
package.loaded["src.render.TextBox"] = savedTextBox
package.loaded["src.ui.Screens"] = savedScreens
love.filesystem.remove("steps_pending.json")
T.finish("pokewalker-gen2")
