-- Standalone: luajit mods/pokewalker/tests/pokewalker_ledger_test.lua
-- Step insurance (v1.2.0): every credit is journaled to mod.storage (a
-- durable per-playthrough shadow of lifetimeSteps) BEFORE it is applied,
-- so loading a save that predates a credit re-credits exactly the
-- unsaved steps -- EXP, watts and gift milestones re-derive, announced
-- with a "Recovered N steps!" page.  This suite drives the ledger
-- arithmetic through the public mod surface: an overlay fs (storage
-- writes land in memory, never on real disk), an identity-carrying game
-- stub (storage needs save.version + meta.playthroughId), and reloads
-- simulated exactly the way Game:adoptSave does it -- swap
-- loader.modSave to the older save's modData, then emit save.loaded.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

love.system = love.system or {}
local syncCalls = 0
love.system.syncHealthSteps = function()
  syncCalls = syncCalls + 1
  return true
end

-- ------- overlay fs: reads fall through to the repo, writes stay here

local FsIo = require("tests.fs_io")
local inner = FsIo.new(".")
local store = {}
local fs = {
  read = function(p)
    if store[p] ~= nil then return store[p] end
    return inner.read(p)
  end,
  write = function(p, body) store[p] = body; return true end,
  remove = function(p) store[p] = nil; return true end,
  createDirectory = function() return true end,
  load = function(p)
    if store[p] ~= nil then
      return loadstring(store[p], "@" .. p)
    end
    return inner.load(p)
  end,
  getInfo = function(p)
    if store[p] ~= nil then return { type = "file" } end
    for k in pairs(store) do
      if k:sub(1, #p + 1) == p .. "/" then return { type = "directory" } end
    end
    return inner.getInfo(p)
  end,
  getDirectoryItems = function(p)
    if p == "mods" then return { "pokewalker" } end
    return inner.getDirectoryItems(p)
  end,
}

-- ------- headless seams (same shape as the main suite)

local savedTextBox = package.loaded["src.render.TextBox"]
local savedScreens = package.loaded["src.ui.Screens"]
local shown, pushed = {}, {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone)
    return { __text = text, __onDone = onDone }
  end,
}
package.loaded["src.ui.Screens"] = {
  push = function() end,
}

local run = T.sdk.loadMod("mods/pokewalker", { data = Data, fs = fs })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local events = run.loader.events
local Pokemon = require("src.pokemon.Pokemon")
local mon = Pokemon.new(Data, "FIXMON_A", 5)
local ow = { map = {}, runner = { isRunning = function() return false end } }
local game = {
  data = Data,
  save = {
    version = "red",
    meta = { format = 4, mods = {}, playthroughId = "walk-1" },
    modData = {},
    party = { mon },
    inventory = {},
    player = { name = "RED", id = 7 },
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
-- mirror Game:adoptSave: the mod.save bucket IS save.modData
run.loader.modSave = game.save.modData

local LEDGER = "mod_storage/red/walk-1/pokewalker/ledger.lua"
local function ledgerValue()
  local body = store[LEDGER]
  if not body then return nil end
  local chunk = assert(loadstring(body))
  return chunk().lifetimeSteps
end
local function modSave() return run.loader.modSave.pokewalker or {} end
local function deliver(steps)
  love.filesystem.write("steps_pending.json",
    ('{"steps": %d}'):format(steps))
end
local function sawPage(needle)
  for _, text in ipairs(shown) do
    if tostring(text):find(needle, 1, true) then return true end
  end
  return false
end

run.loader.modOptions.pokewalker = { enabled = true, watts = true }
events:emit("game.ready", { game = game })

-- ------- 1. a fresh credit seeds the ledger to match the save counter

deliver(4000)
events:emit("map.entered", {})
T.eq(modSave().lifetimeSteps, 4000, "the credit lands in the save bucket")
T.eq(ledgerValue(), 4000, "and the ledger shadows it exactly")

-- ------- 2. the Discord scenario: credit a milestone, reload a stale
-- ------- save, watch the recovery re-grant the gift

local Gifts = run.loader.exports.pokewalker.milestones
local realLadder = {}
for i, m in ipairs(Gifts) do realLadder[i] = m end
for i = #Gifts, 1, -1 do Gifts[i] = nil end
Gifts[1] = { at = 5000, species = "FIXMON_C", level = 9 }

run.loader.modOptions.pokewalker =
  { enabled = true, watts = true, gifts = true }
-- the player enabled STEP GIFTS at 4000 lifetime steps and SAVEd: the
-- persisted bucket carries the journey base, like any real stale save
run.loader.modSave.pokewalker.milestoneBase = 4000
-- snapshot what an in-game SAVE would have persisted at this point
local function snapshot(bucket)
  local copy = {}
  for k, v in pairs(bucket) do copy[k] = v end
  return copy
end
local savedBucket = snapshot(modSave())

deliver(6000) -- journey 6000 crosses the 5000-step stand-in milestone
events:emit("map.entered", {})
T.eq(modSave().lifetimeSteps, 10000, "milestone credit applied")
T.eq(ledgerValue(), 10000, "ledger tracked it")
T.eq(#game.save.party, 2, "the milestone gift joined the party")
T.eq(modSave().milestonesGranted and modSave().milestonesGranted["5000"],
  true, "milestone marked granted")

-- the player quits WITHOUT saving: reload the pre-credit save
game.save.party = { mon }
game.save.modData = { pokewalker = savedBucket }
run.loader.modSave = game.save.modData
events:emit("save.loaded", {})
T.check(sawPage("Recovered"), "the recovery announces itself")
T.eq(modSave().lifetimeSteps, 10000, "recovered steps re-credit the counter")
T.eq(#game.save.party, 2, "the lost milestone gift re-grants")
T.eq(modSave().milestonesGranted and modSave().milestonesGranted["5000"],
  true, "milestone re-marked granted")
T.eq(ledgerValue(), 10000, "a pure recovery does not advance the ledger")

-- ------- 3. boot-window monotonicity: a credit that lands BEFORE the
-- ------- reconcile (map.entered precedes save.loaded on every CONTINUE)
-- ------- must not regress the shadow

local staleBucket = { lifetimeSteps = 2000, watts = savedBucket.watts }
game.save.party = { mon }
game.save.modData = { pokewalker = staleBucket }
run.loader.modSave = game.save.modData
run.loader.modOptions.pokewalker = { enabled = true, watts = true }
deliver(500)
events:emit("map.entered", {})  -- boot map.entered: no reconcile yet
T.eq(ledgerValue(), 10500,
  "the shadow advances by the new walk without regressing (max() rule)")
T.eq(modSave().lifetimeSteps, 2500, "the boot credit applied normally")
shown = {}
events:emit("save.loaded", {})  -- now the reconcile runs
T.check(sawPage("Recovered"), "the remainder recovers after reconcile")
T.eq(modSave().lifetimeSteps, 10500,
  "recovery brings the counter to the shadow exactly once")

-- ------- 4. a saved-state reload recovers nothing

local savedState = snapshot(modSave())
game.save.modData = { pokewalker = savedState }
run.loader.modSave = game.save.modData
shown = {}
events:emit("save.loaded", {})
T.check(not sawPage("Recovered"), "no phantom recovery from a saved state")
T.eq(modSave().lifetimeSteps, 10500, "counter untouched")

-- ------- 5. double-reload without saving: recompute, never accumulate

game.save.modData = { pokewalker = { lifetimeSteps = 3000 } }
run.loader.modSave = game.save.modData
events:emit("save.loaded", {})
T.eq(modSave().lifetimeSteps, 10500, "first recovery reaches the shadow")
game.save.modData = { pokewalker = { lifetimeSteps = 3000 } }
run.loader.modSave = game.save.modData
events:emit("save.loaded", {})
T.eq(modSave().lifetimeSteps, 10500,
  "second recovery recomputes to the same shadow, never past it")

-- ------- 6. checkpoint.restored takes the same path

game.save.modData = { pokewalker = { lifetimeSteps = 8000 } }
run.loader.modSave = game.save.modData
shown = {}
events:emit("checkpoint.restored", { game = game, kind = "overworld" })
T.check(sawPage("Recovered"), "checkpoint restore recovers too")
T.eq(modSave().lifetimeSteps, 10500, "back to the shadow")

-- ------- 7. playthrough isolation: another slot has its own ledger

game.save.meta.playthroughId = "walk-2"
game.save.modData = { pokewalker = {} }
run.loader.modSave = game.save.modData
shown = {}
events:emit("save.loaded", {})
T.check(not sawPage("Recovered"),
  "a different playthrough sees no foreign ledger")
T.eq(modSave().lifetimeSteps, nil, "and gains no phantom steps")
game.save.meta.playthroughId = "walk-1"

-- ------- 8. degradation: no identity -> credit still applies, one warn

for i = #Gifts, 1, -1 do Gifts[i] = nil end
for i, m in ipairs(realLadder) do Gifts[i] = m end
game.save.version = nil
game.save.modData = { pokewalker = { lifetimeSteps = 100 } }
run.loader.modSave = game.save.modData
run.loader.modOptions.pokewalker = { enabled = true }
deliver(300)
events:emit("map.entered", {})
T.eq(modSave().lifetimeSteps, 400,
  "storage failure never blocks the credit itself")
deliver(300)
events:emit("map.entered", {})
T.eq(modSave().lifetimeSteps, 700, "and later credits keep working")

love.filesystem.remove("steps_pending.json")
package.loaded["src.render.TextBox"] = savedTextBox
package.loaded["src.ui.Screens"] = savedScreens
run.release()
T.finish("pokewalker-ledger")
