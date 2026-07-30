-- Watts + streaks.  Watts are the walking currency (WATT_RATE steps = 1W)
-- spent in shop.lua; streaks are consecutive daily-goal days that multiply
-- both the EXP and watt earn rates.  All state lives in mod.save so it
-- travels with the game save.
--
-- The engine has no clock utility, so day attribution is owned here:
-- a "goal day" is the calendar day (local time) a sync credited enough
-- steps, keyed "YYYY-MM-DD".  Economy.now is injectable for tests.

local Strings = require("src.core.Strings")

local Economy = {}

Economy.now = os.time

Economy.WATT_RATE = 20      -- steps per watt (matches the default EXP rate)
Economy.WEEKLY_BONUS = 500  -- watts per completed 7-day streak week
Economy.BALL_STREAK = 30    -- streak day that earns the free MASTER BALL

local function dayKey(t)
  return os.date("%Y-%m-%d", t)
end

-- Calendar-day distance between two YYYY-MM-DD keys (noon avoids DST edges).
local function dayNumber(key)
  local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
  if not y then return nil end
  return math.floor(os.time({ year = tonumber(y), month = tonumber(m),
                              day = tonumber(d), hour = 12 }) / 86400)
end

function Economy.mult(streak)
  if streak >= 30 then return 2 end
  if streak >= 14 then return 1.5 end
  if streak >= 7 then return 1.25 end
  if streak >= 3 then return 1.1 end
  return 1
end

function Economy.addWatts(mod, n)
  mod.save:set("watts", mod.save:get("watts", 0) + n)
end

-- Credit one sync's steps into streak state and the watt balance.
-- opts = { streaks = bool, watts = bool, goal = number }.
-- Returns mult, wattsEarned, pages (report pages; every line <= 18 cols
-- and every page <= 2 lines -- see the TextBox budget note in main.lua).
function Economy.credit(mod, game, steps, opts)
  local pages = {}
  local mult = 1
  if opts.streaks then
    local today = dayKey(Economy.now())
    local daySteps = (mod.save:get("dayKey") == today)
      and mod.save:get("daySteps", 0) or 0
    daySteps = daySteps + steps
    mod.save:set("dayKey", today)
    mod.save:set("daySteps", daySteps)
    local last = mod.save:get("lastGoalDay", false)
    if daySteps >= opts.goal and last ~= today then
      local streak = 1
      if last then
        local gap = (dayNumber(today) or 0) - (dayNumber(last) or 0)
        if gap == 1 then
          streak = mod.save:get("streak", 0) + 1
        elseif gap == 2 and mod.save:get("shield", false) then
          -- exactly one missed day: the shield bridges it.  Longer gaps
          -- break the streak AND keep the shield (nothing to bridge).
          mod.save:set("shield", false)
          streak = mod.save:get("streak", 0) + 1
          pages[#pages + 1] = Strings("Streak Shield\nkept your streak!")
        end
      end
      mod.save:set("streak", streak)
      mod.save:set("lastGoalDay", today)
      if streak > mod.save:get("bestStreak", 0) then
        mod.save:set("bestStreak", streak)
      end
      if streak % 7 == 0 then
        if opts.watts then
          Economy.addWatts(mod, Economy.WEEKLY_BONUS)
          pages[#pages + 1] = Strings("%d-day streak!\nYou earned 500W!", streak)
        else
          pages[#pages + 1] = Strings("%d-day streak!", streak)
        end
      end
      if streak == Economy.BALL_STREAK then
        local Bag = require("src.inventory.Bag")
        if Bag.add(game.save, "MASTER_BALL", 1) then
          pages[#pages + 1] = Strings("30 days! Here's\na MASTER BALL!")
        else
          Economy.addWatts(mod, 2500)
          pages[#pages + 1] = Strings("30 days! Bag\nfull: +2500W!")
        end
      end
    end
    mult = Economy.mult(mod.save:get("streak", 0))
  end
  local wattsEarned = 0
  if opts.watts then
    wattsEarned = math.floor(steps / Economy.WATT_RATE * mult)
    if wattsEarned > 0 then
      Economy.addWatts(mod, wattsEarned)
      table.insert(pages, 1, Strings("You earned\n%dW!", wattsEarned))
    end
  end
  return mult, wattsEarned, pages
end

return Economy
