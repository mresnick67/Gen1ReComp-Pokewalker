-- The watt shop.  The engine's mart (src/ui/ShopMenu.lua) is hard-wired to
-- game.save.money, game.data.items prices, and the ¥ glyph, so this is its
-- buy flow re-composed over the same widgets (ListMenu + QuantityBox +
-- ChoiceBox via mod.ui) with watts as the currency and our own catalog.
-- A wrapper screen draws the watts box (ListMenu's own money box hardcodes
-- ¥) the way the Safari steps panel decorates the start menu.
--
-- Footer/prompt strings stay within 2 lines of <= 18 columns: the dialogue
-- footer shows two lines, and TextBox soft-wrap never waits for A.

local Strings = require("src.core.Strings")

local Shop = {}

-- Prices are the design's watt table (20 steps = 1W); engine def.price is
-- unusable (MASTER_BALL / PP_UP / MOON_STONE are priced 0 in the ROM).
Shop.CATALOG = {
  { item = "POKE_BALL", watts = 50, stack = true },
  { item = "GREAT_BALL", watts = 100, stack = true },
  { shield = true, label = "STREAK SHIELD", watts = 250 },
  { item = "ULTRA_BALL", watts = 250, stack = true },
  { item = "NUGGET", watts = 500, stack = true },
  { radar = "BLUE", label = "BLUE RADAR", watts = 500 },
  { item = "PP_UP", watts = 750, stack = true },
  { stones = true, label = "EVO.STONE", watts = 1000 },
  { item = "RARE_CANDY", watts = 1250, stack = true },
  { radar = "SILVER", label = "SILVER RADAR", watts = 1500 },
  { item = "MASTER_BALL", watts = 2500, stack = true },
  { radar = "GOLD", label = "GOLD RADAR", watts = 5000 },
  -- "DIAMOND RADAR" + "10000W" overruns the 18-tile row into the price
  { radar = "DIAMOND", label = "DMND RADAR", watts = 10000 },
}

Shop.STONES = {
  "FIRE_STONE", "WATER_STONE", "THUNDER_STONE", "LEAF_STONE", "MOON_STONE",
}

local function itemName(game, id)
  local def = game.data.items[id]
  return (def and def.name) or id
end

local function newShop(mod, game)
  local Bag = require("src.inventory.Bag")
  local greet = Strings("Spend your\nsteps!")
  local notEnough = Strings("Not enough\nwatts!")
  local bagFull = Strings("You can't carry\nany more items.")
  local function watts() return mod.save:get("watts", 0) end
  local function debit(n) mod.save:set("watts", watts() - n) end

  local items = {}
  for _, row in ipairs(Shop.CATALOG) do
    items[#items + 1] = {
      label = row.item and itemName(game, row.item) or row.label,
      right = ("%dW"):format(row.watts),
      value = row,
    }
  end

  local list
  local function purchased(text)
    pcall(function() require("src.core.Sound").play(game.data, "Purchase") end)
    list.footer = text or Strings("Here you are!\nThank you!")
  end
  -- footer prompt, then YES/NO; re-checks affordability at confirm time
  local function confirmThen(cost, prompt, apply)
    list.footer = prompt
    game.stack:push(mod.ui.ChoiceBox.new(game, function(yes)
      if not yes then list.footer = greet; return end
      if watts() < cost then list.footer = notEnough; return end
      apply()
    end))
  end

  list = mod.ui.ListMenu.new(game, Strings("WATT SHOP"), items, {
    dialogue = true,
    footer = greet,
    onChoose = function(item)
      local row = item.value
      if row.radar and mod.save:get("radar", false) then
        list.footer = Strings("A radar charge\nis already armed.")
        return
      end
      if row.shield and mod.save:get("shield", false) then
        list.footer = Strings("You already hold\na STREAK SHIELD.")
        return
      end
      if watts() < row.watts then
        list.footer = notEnough
        return
      end
      if row.item and row.stack then
        local affordable = math.min(99, math.floor(watts() / row.watts))
        game.stack:push(mod.ui.QuantityBox.new(game, {
          max = affordable,
          onDone = function(qty)
            if not qty then list.footer = greet; return end
            local cost = qty * row.watts
            confirmThen(cost,
              Strings("%s x%d?\n%dW. OK?", item.label, qty, cost), function()
              if not Bag.add(game.save, row.item, qty) then
                list.footer = bagFull
                return
              end
              debit(cost)
              purchased()
            end)
          end,
        }))
      elseif row.stones then
        local entries = {}
        for _, sid in ipairs(Shop.STONES) do
          entries[#entries + 1] = {
            label = itemName(game, sid),
            onSelect = function()
              confirmThen(row.watts,
                Strings("%s?\n%dW. OK?", itemName(game, sid), row.watts),
                function()
                  if not Bag.add(game.save, sid, 1) then
                    list.footer = bagFull
                    return
                  end
                  debit(row.watts)
                  purchased()
                end)
            end,
          }
        end
        game.stack:push(mod.ui.Menu.new(game, entries, { tx = 2, ty = 2, tw = 15 }))
      elseif row.radar then
        confirmThen(row.watts,
          Strings("%s?\n%dW. OK?", item.label, row.watts), function()
          debit(row.watts)
          mod.save:set("radar", { tier = row.radar })
          purchased(Strings("Radar armed!\nWalk in grass."))
        end)
      elseif row.shield then
        confirmThen(row.watts,
          Strings("%s?\n%dW. OK?", item.label, row.watts), function()
          debit(row.watts)
          mod.save:set("shield", true)
          purchased(Strings("STREAK SHIELD\narmed!"))
        end)
      end
    end,
  })

  -- wrapper: delegate to the list, then repaint the money box with watts.
  -- Dialogue mode always draws its ¥ box at hlcoord 11,0 (ListMenu.lua's
  -- MONEY_BOX), so ours must sit at the exact same tile rect -- anything
  -- offset leaves the vanilla box's border peeking out underneath.  The
  -- list is never separately on the stack, so its self-pop pops this
  -- wrapper.
  local Font = mod.ui.Font
  local screen = { isOpaque = true, list = list }
  function screen:update(dt) list:update(dt) end
  function screen:draw()
    list:draw()
    Font.drawBox(11, 0, 9, 3)
    love.graphics.setColor(0, 0, 0, 1)
    local amount = ("%dW"):format(watts())
    Font.draw(amount, 152 - Font.width(amount), 8)
    love.graphics.setColor(1, 1, 1, 1)
  end
  function screen:sgbPalettes(g) return list:sgbPalettes(g) end
  return screen
end

function Shop.register(mod)
  mod.content.screens:register("PokewalkerMenu", {
    new = function(game)
      local Screens = require("src.ui.Screens")
      -- mart pattern: keepOpen rows push above this menu, so closing the
      -- shop or card lands back here; EXIT (or B) reopens the start menu
      local menu = mod.ui.Menu.new(game, {
        { label = Strings("WATT SHOP"), keepOpen = true,
          onSelect = function() mod.ui.push(game, "PokewalkerShop") end },
        { label = Strings("TRAINER CARD"), keepOpen = true,
          onSelect = function() mod.ui.push(game, "PokewalkerCard") end },
        { label = Strings("EXIT"),
          onSelect = function() Screens.push(game, "StartMenu") end },
      }, { tx = 0, ty = 0, tw = 16 })
      menu.onCancel = function() Screens.push(game, "StartMenu") end
      return menu
    end,
  })
  mod.content.screens:register("PokewalkerShop", {
    new = function(game) return newShop(mod, game) end,
  })
end

return Shop
