-- Gift milestones: pokémon granted at journey-step thresholds.  "Journey"
-- steps count from when STEP GIFTS was first enabled (milestoneBase is
-- snapshotted then and kept across toggle cycles), so enabling the feature
-- late starts a fresh journey instead of dumping every crossed milestone.
-- main.lua grants at most one milestone per quiet overworld moment.

local Strings = require("src.core.Strings")

local Gifts = {}

-- Ordered ascending; the ladder mirrors the games' own gift tradition.
Gifts.MILESTONES = {
  { at = 10000, species = "EEVEE", level = 5 },
  { at = 25000, choice = { "HITMONLEE", "HITMONCHAN" }, level = 20 },
  { at = 50000, species = "PORYGON", level = 15 },
  { at = 100000, species = "LAPRAS", level = 15 },
  { at = 150000, species = "SNORLAX", level = 30 },
  { at = 200000, species = "AERODACTYL", level = 30 },
  { at = 300000, species = "MEW", level = 5 },
}

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

-- Announce, (optionally) offer the choice, then give.  give_pokemon is
-- runner-optional with a hand-rolled ctx (src/script/Commands.lua:599);
-- skipNickname because the nickname prompt needs a script runner -- the
-- in-game Name Rater covers renames.  The milestone is only marked
-- granted when the give actually lands (party/boxes not all full);
-- otherwise the next quiet moment retries.
function Gifts.grant(mod, game, m, onDone)
  local TextBox = require("src.render.TextBox")
  local done = onDone or function() end
  local function give(species)
    local Commands = require("src.script.Commands")
    local ctx = { game = game, save = game.save }
    Commands.give_pokemon(ctx, species, m.level, true)
    if ctx.lastCheck then
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
