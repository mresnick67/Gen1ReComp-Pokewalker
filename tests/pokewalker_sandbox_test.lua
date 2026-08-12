-- Standalone: luajit mods/pokewalker/tests/pokewalker_sandbox_test.lua
-- The 2026-08 mod sandbox blocks love.system and love.filesystem by
-- RAISING on index (not returning nil).  Until upstream ships a scoped
-- steps seam (bryanthaboi/gen1recomp#1183) the mod must be cleanly
-- dormant there: no sync, no credit, and -- the part that bit v1.0.0 --
-- no error from any event handler.  The engine in this checkout predates
-- the sandbox, so its love facade is simulated here: _G.love is swapped
-- for a proxy that raises on the blocked keys and passes everything else
-- through, which is the facade's exact shape (src/mods/Sandbox.lua on
-- upstream's sandbox branch).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

-- a pending file exists (written earlier by the native side) BEFORE the
-- facade goes up: the strongest tempting case for the credit path
love.filesystem.write("steps_pending.json", '{"steps": 20000}')

local run = T.sdk.loadMod("mods/pokewalker", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

-- The facade goes up AFTER load: on the real sandbox only mod code sees
-- it (the loader and engine keep the real love), and this mod reads the
-- love global at event time, not load time, so swapping it here puts the
-- mod in exactly the sandbox's world for everything that follows.
local realLove = love
local BLOCKED = { filesystem = true, thread = true, system = true,
                  event = true }
_G.love = setmetatable({}, {
  __index = function(_, key)
    if BLOCKED[key] then
      error(("love.%s is not available to mods"):format(key), 2)
    end
    return realLove[key]
  end,
})

local events = run.loader.events
local Pokemon = require("src.pokemon.Pokemon")
local mon = Pokemon.new(Data, "FIXMON_A", 5)
local baselineExp = mon.exp
local ow = { map = {}, runner = { isRunning = function() return false end } }
local game = {
  data = Data,
  save = { party = { mon }, inventory = {},
           player = { name = "RED", id = 1 } },
  overworld = ow,
  stack = { top = function() return ow end, push = function() end },
}

-- SYNC STEPS on: the exact configuration that error-spammed under the
-- real sandbox before the probe existed
run.loader.modOptions.pokewalker = { enabled = true, watts = true }

events:emit("game.ready", { game = game })
events:emit("save.loaded", {})
events:emit("map.entered", {})
events:emit("battle.ended", {})
events:emit("mod.options_changed",
  { mod = "pokewalker", key = "enabled", value = true })

T.eq(#run.errors, 0, "no event handler errors under the facade ("
  .. tostring(run.errors[1]) .. ")")
T.eq(mon.exp, baselineExp, "no EXP is credited without a reachable bridge")
_G.love = realLove
T.check(love.filesystem.read("steps_pending.json") ~= nil,
  "the pending file is left for an engine that can consume it")

love.filesystem.remove("steps_pending.json")
run.release()
T.finish("pokewalker-sandbox")
