-- Standalone: luajit mods/pokewalker/tests/pokewalker_test.lua
-- Exercises the stated effect: opt-in gating, the native-bridge seam,
-- steps converting to EXP through the engine's own growth math, and the
-- rare-candy-style credit presentation (paged report + move learning).
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
local shown, menuCalls = {}, {}
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
  save = { party = { mon } },
  overworld = ow,
  stack = {
    top = function() return stackTop end,
    push = function(_, state)
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
T.check(shown[1] ~= nil and shown[1]:find("You walked 20000 steps", 1, true) ~= nil,
  "walk report opens the credit")
T.check(shown[1]:find("\f", 1, true) ~= nil,
  "report pages are \\f-separated so each box waits for A")
T.eq(#menuCalls, 1, "a full moveset routes through the learn menu")
T.eq(menuCalls[1].id, "MoveLearnMenu", "the engine's own menu is used")
T.eq(menuCalls[1].move, "FIX_EMBERISH", "offering the level-7 learnset move")
T.eq(#mon.moves, 4, "nothing is force-forgotten")

-- A fresh mon with a free slot auto-learns with its own message page.
local mon2 = Pokemon.new(Data, "FIXMON_A", 5)
game.save.party = { mon2 }
love.filesystem.write("steps_pending.json", '{"steps": 20000}')
events:emit("battle.ended", {})
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

package.loaded["src.render.TextBox"] = savedTextBox
package.loaded["src.ui.Screens"] = savedScreens
run.release()
T.finish("pokewalker")
