local corocreate = coroutine.create
local cororesume = coroutine.resume
local cororunning = coroutine.running
local corostatus = coroutine.status
local corowrap = coroutine.wrap         --> TODO: to be implemented!!
local coroyield = coroutine.yield
local sethook = debug.sethook

local socket
local unpack = unpack or table.unpack  -- 5.1/5.2 compat issue

local M = coroutine       -- grab global table to update

-- create watch register; table indexed by coro with watch properties
-- element = {
--   twarnlimit = when to warn, seconds
--   tkilllimit = when to kill, seconds
--   cbwarn = warn callback, function
--   warned = boolean; was cwwarn called already?
--   error = errormessage after kill, string
--   killtime = point in time after which to kill the coroutine
--   warntime = point in time after which to warn
--   errmsg = errormessage if timedout, so if set, the coro should be dead
--   hook = function; the debughook in use
-- }
local register = setmetatable({},{__mode = "k"})  -- set weak keys


local mainthread = {}  -- for 5.1 where there is no main thread access, running() returns nil
---------------------------------------------------------------------------------------
-- Gets the entry for the coro from the coroutine register.
-- @return the coroutine entry from the register
local getwatch = function(coro)
  return register[coro or cororunning() or mainthread]
end


---------------------------------------------------------------------------------------
-- Debughook function, to check for timeouts
local checkhook = function()
  local e = getwatch()
  if not e then return end  -- not being watched
  local t = M.gettime()
  if e.errmsg then
    -- the coro is tagged with an error. This means that somewhere the error
    -- was thrown, but the coro didn't die (probably a pcall in between). The coro should have died
    -- but didn't so it is in an 'undetermined' state. So kill again.
    error(e.errmsg,2)
  elseif not e.warned and e.warntime and e.warntime < t then
    -- warn now
    if e.cbwarn(cororunning()) then
      -- returned positive, so reset timeouts
      if e.tkilllimit then e.killtime = t + e.tkilllimit end
      if e.twarnlimit then e.warntime = t + e.twarnlimit end
    else
      e.warned = true
    end
  elseif e.killtime and e.killtime < t then
    -- run hook now every instruction, to kill again and again if it persists (pcall/cboundary)
    sethook(coro, checkhook, "l", 1)
    -- kill now
    e.errmsg = "Coroutine exceeded its allowed running time of "..tostring(e.tkilllimit).." seconds, without yielding"
    error(e.errmsg, 2)
  end
end

---------------------------------------------------------------------------------------
-- Creates an entry in the coroutine register. If it already exists, existing values
-- will be overwritten (in the existing entry) with the new values.
-- @param coro coroutine for which to create the entry
-- @return the entry created
local createwatch = function(coro, tkilllimit, twarnlimit, cbwarn)
  coro = coro or cororunning() or mainthread
  local entry = register[coro] or {}
  entry.tkilllimit = tkilllimit
  entry.twarnlimit = twarnlimit
  entry.cbwarn = cbwarn
  sethook(coro, checkhook, "l", 5000)
  register[coro] = entry
  return entry
end

---------------------------------------------------------------------------------------
-- returns current time in seconds. If not overridden, it will require luasocket and use
-- socket.gettime() to get the current time.
M.gettime = function()
  if not socket then socket = require("socket") end
  return socket.gettime()
end

---------------------------------------------------------------------------------------
-- Protects a coroutine by adding a hook.
-- @param coro coroutine to be protected
-- @param tkilllimit time in seconds it is allowed to run
-- @param twarnlimit (optional) time in seconds it is allowed before cbwarn is called
-- @param cbwarn (optional) callback executed before the coro is terminated. 
-- If the callback returns false/nil the coro will be terminated, otherwise
-- the timeout is repeated
-- @return coro
local watch = function(coro, tkilllimit, twarnlimit, cbwarn)
  if getwatch(coro) then error("Cannot create a watch, there already is one") end
  assert((twarnlimit and cbwarn) or not (twarnlimit or cbwarn), "Must either provide a warn limit AND a warn callback, or provide neither")
  assert(tkilllimit or twarnlimit, "Either kill limit or warn limit must be provided")
  createwatch(coro, tkilllimit, twarnlimit, cbwarn)
  return coro
end
M.watch = watch

---------------------------------------------------------------------------------------
-- when the running coroutine is watched, then children spawned must also be watched
M.create = function(f)
  local s = getwatch(cororunning())
  if not s then return corocreate(f) end  -- I'm not being watched
  -- create and add watch
  return watch(corocreate(f), s.tkilllimit, s.twarnlimit, s.cbwarn)
end

-- before resume, the timeout must be set
M.resume = function(coro, ...)
  assert(type(coro) == "thread", "Expected thread, got "..type(coro))
  local e = getwatch(coro)
  if e then
    if e.errmsg then
      -- the coro being resumed is tagged with an error. This means that somewhere the error
      -- was thrown, but the coro didn't die (probably a pcall in between). The coro should have died
      -- but didn't so it is in an 'undetermined' state. Return error, don't resume
      return false, e.errmsg
    end
    local t = M.gettime()
    if e.tkilllimit then e.killtime = t + e.tkilllimit end
    if e.twarnlimit then e.warntime = t + e.twarnlimit end
    e.warned = nil
  end
  local r = { cororesume(coro, ...) }
  if e and e.errmsg then
    return false, e.errmsg
  else
    return unpack(r)
  end
end

M.yield = function(...)
  local e = getwatch()
  if e then 
    if e.errmsg then
      -- the coro is yielding, while it is tagged with an error. This means that somewhere the error
      -- was thrown, but the coro didn't die (probably a pcall in between). The coro should have died
      -- but didn't so it is in an 'undetermined' state. So kill again.
      error(e.errmsg,2)
    end
    e.killtime = nil
    e.warntime = nil
    e.warned = nil
  end
  return coroyield(...) 
end

M.status = function(coro)
  if (getwatch(coro) or {}).errmsg then
    return "dead"
  else
    return corostatus(coro)
  end
end

return M
