-- Radar charges: bought in the watt shop, armed immediately, spent on the
-- next stepped-on encounter tile.  The force mechanism is the engine's
-- documented encounter.roll contract (src/world/OverworldController.lua):
-- returning a { species, level } table without calling next() forces that
-- encounter.  Static legendaries stay safe -- their one-time flags key on
-- NPC ids, not species, and dex flags are idempotent.

local Radar = {}

Radar.POOLS = {
  BLUE = {
    { species = "DITTO", level = 25 },
    { species = "TANGELA", level = 25 },
    { species = "SCYTHER", level = 25 },
    { species = "PINSIR", level = 25 },
    { species = "ONIX", level = 25 },
  },
  SILVER = {
    { species = "CHANSEY", level = 26 },
    { species = "KANGASKHAN", level = 28 },
    { species = "TAUROS", level = 28 },
    { species = "DRATINI", level = 20 },
  },
}

Radar.BIRDS = {
  { species = "ZAPDOS", level = 50 },
  { species = "MOLTRES", level = 50 },
  { species = "ARTICUNO", level = 50 },
}

-- Pick the forced encounter for a tier.  ctx comes from rollEncounter:
-- { mapId, terrain = "grass"|"water"|"indoor", rng }.  Terrain flavors the
-- legendary tiers (surfing rolls Articuno, caves roll Moltres).
function Radar.pick(tier, ctx)
  local rng = (ctx and ctx.rng) or love.math.random
  if tier == "GOLD" then
    if ctx and ctx.terrain == "water" then
      return { species = "ARTICUNO", level = 50 }
    end
    if ctx and ctx.terrain == "indoor" then
      return { species = "MOLTRES", level = 50 }
    end
    local bird = Radar.BIRDS[rng(1, #Radar.BIRDS)]
    return { species = bird.species, level = bird.level }
  end
  if tier == "DIAMOND" then
    if rng(1, 3) == 3 then return { species = "MEW", level = 30 } end
    return { species = "MEWTWO", level = 70 }
  end
  local pool = Radar.POOLS[tier]
  if not pool then return nil end
  local entry = pool[rng(1, #pool)]
  return { species = entry.species, level = entry.level }
end

-- isOn() gates on the WATTS option so a disabled economy never hijacks a
-- roll, even if an armed charge is left in the save.
function Radar.install(mod, isOn)
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    local armed = mod.save:get("radar", false)
    if armed and armed.tier and isOn() then
      local enc = Radar.pick(armed.tier, ctx)
      if enc then
        -- spent the moment the battle fires -- win, lose, catch, or flee
        mod.save:set("radar", false)
        mod.log:info("radar %s fired: %s L%d", armed.tier, enc.species,
                     enc.level)
        return enc
      end
    end
    return next(encDef, ctx)
  end)
end

return Radar
