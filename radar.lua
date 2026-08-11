-- Radar charges: bought in the watt shop, armed immediately, spent on the
-- next stepped-on encounter tile.  The force mechanism is the engine's
-- documented encounter.roll contract (src/world/OverworldController.lua;
-- Gold fires the same hook from its grass/water step): returning a
-- { species, level } table without calling next() forces that encounter.
-- Static legendaries stay safe -- their one-time flags key on NPC ids, not
-- species, and dex flags are idempotent.
--
-- Content is per-generation: main.lua's selectContent() calls
-- Radar.select() at game.ready, so a Gold save rolls Johto pools while a
-- Gen 1 save keeps the original tables.  Every list is picked from with
-- one rng draw (single-entry lists draw nothing), so the Gen 1 tables
-- roll exactly as they did before the split -- including the DIAMOND
-- list's [MEWTWO, MEWTWO, MEW] shape, which preserves the old
-- rng(1,3)==3 Mew odds draw for draw.

local Radar = {}

Radar.SETS = {
  gen1 = {
    POOLS = {
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
        { species = "BULBASAUR", level = 15 },
        { species = "CHARMANDER", level = 15 },
        { species = "SQUIRTLE", level = 15 },
      },
    },
    -- GOLD tier; terrain flavors the pick (surfing rolls Articuno, caves
    -- roll Moltres)
    BIRDS = {
      { species = "ZAPDOS", level = 50 },
      { species = "MOLTRES", level = 50 },
      { species = "ARTICUNO", level = 50 },
    },
    WATER = { { species = "ARTICUNO", level = 50 } },
    INDOOR = { { species = "MOLTRES", level = 50 } },
    -- DIAMOND tier: 1-in-3 Mew, else Mewtwo
    APEX = {
      { species = "MEWTWO", level = 70 },
      { species = "MEWTWO", level = 70 },
      { species = "MEW", level = 30 },
    },
  },
  gen2 = {
    POOLS = {
      BLUE = {
        { species = "DUNSPARCE", level = 25 },
        { species = "YANMA", level = 25 },
        { species = "AIPOM", level = 25 },
        { species = "GLIGAR", level = 25 },
        { species = "PHANPY", level = 25 },
      },
      SILVER = {
        { species = "MISDREAVUS", level = 26 },
        { species = "SKARMORY", level = 28 },
        { species = "HERACROSS", level = 28 },
        { species = "LARVITAR", level = 20 },
        { species = "CHIKORITA", level = 15 },
        { species = "CYNDAQUIL", level = 15 },
        { species = "TOTODILE", level = 15 },
      },
    },
    -- GOLD tier on Gold: the three birds AND the three beasts; water picks
    -- between the water pair, caves between the fire pair
    BIRDS = {
      { species = "ZAPDOS", level = 50 },
      { species = "MOLTRES", level = 50 },
      { species = "ARTICUNO", level = 50 },
      { species = "RAIKOU", level = 50 },
      { species = "ENTEI", level = 50 },
      { species = "SUICUNE", level = 50 },
    },
    WATER = {
      { species = "ARTICUNO", level = 50 },
      { species = "SUICUNE", level = 50 },
    },
    INDOOR = {
      { species = "MOLTRES", level = 50 },
      { species = "ENTEI", level = 50 },
    },
    -- DIAMOND tier on Gold: every apex legendary, one uniform draw
    APEX = {
      { species = "CELEBI", level = 30 },
      { species = "HO_OH", level = 70 },
      { species = "LUGIA", level = 70 },
      { species = "MEW", level = 30 },
      { species = "MEWTWO", level = 70 },
    },
  },
}

-- The live set.  Gen 1 by default so nothing changes before game.ready
-- (or on engines that predate constants.generation).
Radar.ACTIVE = Radar.SETS.gen1

function Radar.select(key)
  Radar.ACTIVE = Radar.SETS[key] or Radar.SETS.gen1
end

local function pickFrom(pool, rng)
  if not pool or #pool == 0 then return nil end
  local entry = pool[#pool == 1 and 1 or rng(1, #pool)]
  return { species = entry.species, level = entry.level }
end

-- Pick the forced encounter for a tier.  ctx comes from rollEncounter:
-- { mapId, terrain = "grass"|"water"|"indoor", rng }.
function Radar.pick(tier, ctx)
  local set = Radar.ACTIVE
  local rng = (ctx and ctx.rng) or love.math.random
  if tier == "GOLD" then
    if ctx and ctx.terrain == "water" then return pickFrom(set.WATER, rng) end
    if ctx and ctx.terrain == "indoor" then return pickFrom(set.INDOOR, rng) end
    return pickFrom(set.BIRDS, rng)
  end
  if tier == "DIAMOND" then
    return pickFrom(set.APEX, rng)
  end
  return pickFrom(set.POOLS[tier], rng)
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
