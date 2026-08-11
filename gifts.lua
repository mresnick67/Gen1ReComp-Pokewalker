-- Gift milestones: pokémon granted at journey-step thresholds.  "Journey"
-- steps count from when STEP GIFTS was first enabled (milestoneBase is
-- snapshotted then and kept across toggle cycles), so enabling the feature
-- late starts a fresh journey instead of dumping every crossed milestone.
-- main.lua grants at most one milestone per quiet overworld moment.
--
-- The ladder is per-generation: main.lua's selectContent() calls
-- Gifts.select() at game.ready, so a Gold save walks a Johto ladder.
-- Grants already made count by their `at` value, so a save that moves
-- between generations never re-grants a crossed rung.

local Strings = require("src.core.Strings")

local Gifts = {}

-- Ordered ascending; each ladder mirrors its own games' gift tradition.
Gifts.MILESTONES_BY_GEN = {
  gen1 = {
    { at = 10000, species = "EEVEE", level = 5 },
    { at = 25000, choice = { "HITMONLEE", "HITMONCHAN" }, level = 20 },
    { at = 50000, species = "PORYGON", level = 15 },
    { at = 100000, species = "LAPRAS", level = 15 },
    { at = 150000, species = "SNORLAX", level = 30 },
    { at = 200000, species = "AERODACTYL", level = 30 },
    { at = 300000, species = "MEW", level = 5 },
  },
  gen2 = {
    { at = 10000, species = "TOGEPI", level = 5 },
    { at = 25000, choice = { "ELEKID", "MAGBY" }, level = 20 },
    { at = 50000, species = "SMEARGLE", level = 15 },
    { at = 100000, species = "SHUCKLE", level = 15 },
    { at = 150000, species = "MILTANK", level = 30 },
    { at = 200000, species = "LARVITAR", level = 30 },
    { at = 300000, species = "CELEBI", level = 5 },
  },
}

-- The live ladder (what pending/grant/card read).  Gen 1 by default so
-- nothing changes before game.ready.
Gifts.MILESTONES = Gifts.MILESTONES_BY_GEN.gen1

function Gifts.select(key)
  Gifts.MILESTONES = Gifts.MILESTONES_BY_GEN[key]
    or Gifts.MILESTONES_BY_GEN.gen1
end

-- The lowest ungranted milestone the journey has crossed, or nil.
function Gifts.pending(mod)
  local base = mod.save:get("milestoneBase")
  if base == nil then return nil end
  local journey = mod.save:get("lifetimeSteps", 0) - base
  local granted = mod.save:get("milestonesGranted", {})
  for _, m in ipairs(Gifts.MILESTONES) do
    if not granted[tostring(m.at)] then
      if journey >= m.at then return m end
      -- ordered ladder: nothing later can be due either
      return nil
    end
  end
  return nil
end

local function displayName(game, species)
  local def = game.data.pokemon[species]
  return (def and def.name) or species
end

local function onGen2(game)
  return ((game.data and game.data.constants
           and game.data.constants.generation) or 1) >= 2
end

-- Gold has no give_pokemon seam (Gen2Compat serves Gen 1's verb table,
-- none of which Gold can run), so the give is composed from the Gen 2
-- engine primitives: build the mon, land it in the party or the first box
-- with room, and tick the dex the way GivePoke does.  Returns whether the
-- gift landed.
local function giveGen2(game, species, level)
  local ok, landed = pcall(function()
    local Mon2 = require("src.battle.gen2.Mon")
    local mon = Mon2.new(game.data, species, level, { caughtLevel = level })
    if not mon then return false end
    local party = game.save.party
    if #party < 6 then
      party[#party + 1] = mon
    else
      local Boxes = require("src.core.gen2.Boxes")
      local target
      for i = 0, Boxes.NUM_BOXES - 1 do
        local index = ((game.save.currentBox or 1) + i - 1)
          % Boxes.NUM_BOXES + 1
        if not Boxes.isFull(game.save, index) then
          target = Boxes.box(game.save, index)
          break
        end
      end
      if not target then return false end
      target[#target + 1] = mon
    end
    require("src.core.gen2.Evolution").markPokedex(game.save, species)
    return true
  end)
  return ok and landed == true
end

-- Announce, (optionally) offer the choice, then give.  On Gen 1
-- give_pokemon is runner-optional with a hand-rolled ctx
-- (src/script/Commands.lua); skipNickname because the nickname prompt
-- needs a script runner -- the in-game Name Rater covers renames.  The
-- milestone is only marked granted when the give actually lands
-- (party/boxes not all full); otherwise the next quiet moment retries.
function Gifts.grant(mod, game, m, onDone)
  local TextBox = require("src.render.TextBox")
  local done = onDone or function() end
  local function give(species)
    local landed
    if onGen2(game) then
      landed = giveGen2(game, species, m.level)
    else
      -- Runtime-built require: only this Gen 1 branch ever runs it, which
      -- a static scan cannot see -- a literal here reads to gen2check as a
      -- Gen 2 defect (MK402), and runtime-built requires are the checker's
      -- documented unresolved-note path for generation-gated code.
      local gen1GiveModule = "src.script.Commands"
      local Commands = require(gen1GiveModule)
      local ctx = { game = game, save = game.save }
      Commands.give_pokemon(ctx, species, m.level, true)
      landed = ctx.lastCheck
    end
    if landed then
      local granted = mod.save:get("milestonesGranted", {})
      granted[tostring(m.at)] = true
      mod.save:set("milestonesGranted", granted)
      game.stack:push(TextBox.new(game,
        Strings("%s is\nyours!", displayName(game, species)), done))
    else
      game.stack:push(TextBox.new(game,
        Strings("No room for your\nmilestone gift!"), done))
    end
  end
  game.stack:push(TextBox.new(game,
    Strings("%d step\nmilestone!", m.at), function()
    if m.choice then
      local entries = {}
      for _, species in ipairs(m.choice) do
        entries[#entries + 1] = {
          label = displayName(game, species),
          onSelect = function() give(species) end,
        }
      end
      -- B declines for now; the milestone stays pending and re-offers
      local menu = mod.ui.Menu.new(game, entries, { tx = 2, ty = 2, tw = 14 })
      menu.onCancel = done
      game.stack:push(menu)
    else
      give(m.species)
    end
  end))
end

return Gifts
