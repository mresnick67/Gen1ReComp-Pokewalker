-- The Pokéwalker trainer card: a small stats screen imitating the engine's
-- TrainerCard structure (isOpaque, A/B dismiss) drawn with plain
-- Font.drawBox frames -- the ROM card tiles aren't reusable from a mod.

local Strings = require("src.core.Strings")

local Card = {}

-- deps = { gifts = gifts module or nil } for the next-milestone line.
function Card.register(mod, deps)
  deps = deps or {}
  mod.content.screens:register("PokewalkerCard", {
    new = function(game)
      local Font = mod.ui.Font
      local self = { isOpaque = true }
      function self:update(dt)
        local input = game.input
        if input:wasPressed("a") or input:wasPressed("b") then
          game.stack:pop()
        end
      end
      function self:draw()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, 160, 144)
        Font.drawBox(0, 0, 20, 18)
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(Strings("POKéWALKER"), 16, 16)
        local y = 40
        local function line(s)
          Font.draw(s, 16, y)
          y = y + 16
        end
        line(("WATTS %d"):format(mod.save:get("watts", 0)))
        line(("STEPS %d"):format(mod.save:get("lifetimeSteps", 0)))
        line(("STREAK %d BEST %d"):format(mod.save:get("streak", 0),
                                          mod.save:get("bestStreak", 0)))
        local radar = mod.save:get("radar", false)
        line("RADAR " .. (radar and radar.tier or "----"))
        line("SHIELD " .. (mod.save:get("shield", false) and "ARMED" or "----"))
        local giftLine = "GIFT ----"
        if deps.gifts and mod.options:get("gifts") then
          local base = mod.save:get("milestoneBase")
          if base ~= nil then
            local journey = mod.save:get("lifetimeSteps", 0) - base
            local granted = mod.save:get("milestonesGranted", {})
            for _, m in ipairs(deps.gifts.MILESTONES) do
              if not granted[tostring(m.at)] then
                giftLine = ("GIFT IN %d"):format(math.max(0, m.at - journey))
                break
              end
            end
          else
            -- first sync after enabling snapshots the journey base
            giftLine = "GIFT SOON"
          end
        end
        line(giftLine)
        love.graphics.setColor(1, 1, 1, 1)
      end
      return self
    end,
  })
end

return Card
