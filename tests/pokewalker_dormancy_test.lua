-- Standalone: luajit mods/pokewalker/tests/pokewalker_dormancy_test.lua
-- Dormancy through the mod.steps seam (RFC 0009): on a build without the
-- native bridge (desktop), available() is false and the mod must be
-- fully inert -- no sync, no credit, no handler errors -- while an
-- engine-side pending delivery stays where it is for a build that can
-- consume it.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

-- no native bridge on this build
local savedSync = T.love.system.syncHealthSteps
T.love.system.syncHealthSteps = nil

-- a delivery staged earlier (by a build that HAD the bridge) is not
-- consumed by a dormant mod
love.filesystem.write("steps_pending.json", '{"steps": 20000}')

local run = T.sdk.loadMod("mods/pokewalker", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

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

-- SYNC STEPS on: the configuration that must still do nothing bridgeless
run.loader.modOptions.pokewalker = { enabled = true, watts = true }

events:emit("game.ready", { game = game })
events:emit("save.loaded", {})
events:emit("map.entered", {})
events:emit("battle.ended", {})
events:emit("mod.options_changed",
  { mod = "pokewalker", key = "enabled", value = true })

T.eq(#run.errors, 0, "no event handler errors without a bridge ("
  .. tostring(run.errors[1]) .. ")")
T.eq(mon.exp, baselineExp, "no EXP is credited without a bridge")
T.check(love.filesystem.read("steps_pending.json") ~= nil,
  "the staged delivery is left for a build that can consume it")

love.filesystem.remove("steps_pending.json")
T.love.system.syncHealthSteps = savedSync
run.release()
T.finish("pokewalker-dormancy")
