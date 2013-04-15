---------------------------------------------------------------------------------------
-- Module to watch coroutine executiontime. Coroutines running too long without
-- yielding can be killed to prevent them from locking the Lua state.
-- The module uses LuaSocket to get the time (socket.gettime() function). If you
-- do not want that, override the coroutine.gettime() method with your own
-- implementation.
--
-- Version 0.2, [copyright (c) 2013 - Thijs Schreijer](http://www.thijsschreijer.nl)
-- @name corowatch
-- @class module

local corocreate = coroutine.create
local cororesume = coroutine.resume
local cororunning = coroutine.running
local corostatus = coroutine.status
local corowrap = coroutine.wrap
local coroyield = coroutine.yield
local sethook = debug.sethook
local traceback = debug.traceback
local watch, resume, create
local unpack = unpack or table.unpack  -- 5.1/5.2 compat issue
local hookcount = 10000

-- create watch register; table indexed by coro with watch properties
local register = setmetatable({},{__mode = "k"})  -- set weak keys
-- register element = {
--   twarnlimit = when to warn, seconds
--   tkilllimit = when to kill, seconds
--   cb = callback, function
--   warned = boolean; was cwwarn called already?
--   killtime = point in time after which to kill the coroutine
--   warntime = point in time after which to warn
--   errmsg = errormessage if timedout, so if set, the coro should be dead
--   hook = function; the debughook in use
--   debug = debug.traceback() at the time of protecting
-- }


local mainthread = {}  -- for 5.1 where there is no main thread access, running() returns nil

-- Gets the entry for the coro from the coroutine register.
-- @return the coroutine entry from the register
local getwatch = function(coro)
  return register[coro or cororunning() or mainthread]
end


-- Debughook function, to check for timeouts
local checkhook = function()
  local e = getwatch()
  if not e then return end  -- not being watched
  local t = coroutine.gettime()
  if e.errmsg then
    -- the coro is tagged with an error. This means that somewhere the error
    -- was thrown, but the coro didn't die (probably a pcall in between). The coro should have died
    -- but didn't so it is in an 'undetermined' state. So kill again.
    error(e.errmsg,2)
  elseif not e.warned and e.warntime and e.warntime < t then
    -- warn now
    if e.cb("warn") then
      -- returned positive, so reset timeouts
      if e.tkilllimit then e.killtime = t + e.tkilllimit end
      if e.twarnlimit then e.warntime = t + e.twarnlimit end
    else
      e.warned = true
    end
  elseif e.killtime and e.killtime < t then
    if e.cb then e.cb("kill") end
    -- run hook now every instruction, to kill again and again if it persists (pcall/cboundary)
    sethook(cororunning(), e.hook, "", 1)
    -- kill now
    e.errmsg = "Coroutine exceeded its allowed running time of "..tostring(e.tkilllimit).." seconds, without yielding"
    if e.debug then
      e.errmsg = e.errmsg ..
       "\n============== traceback at coroutine creation time ====================\n" ..
       e.debug ..
       "\n======================== end of traceback ==============================" 
    end
    error(e.errmsg, 2)
  end
end

-- Creates an entry in the coroutine register. If it already exists, existing values
-- will be overwritten (in the existing entry) with the new values.
-- @param coro coroutine for which to create the entry
-- @return the entry created
local createwatch = function(coro, tkilllimit, twarnlimit, cb)
  coro = coro or cororunning() or mainthread
  local entry = register[coro] or {}
  entry.tkilllimit = tkilllimit
  entry.twarnlimit = twarnlimit
  entry.cb = cb
  entry.hook = checkhook
  entry.debug = traceback()
  sethook(coro, entry.hook, "", hookcount)
  register[coro] = entry
  return entry
end

---------------------------------------------------------------------------------------
-- returns current time in seconds. If not overridden, it will require luasocket and use
-- socket.gettime() to get the current time.
coroutine.gettime = function()
  coroutine.gettime = require("socket").gettime
  return coroutine.gettime()
end

---------------------------------------------------------------------------------------
-- Protects a coroutine from running too long without yielding.
-- @param coro coroutine to be protected
-- @param tkilllimit (optional) time in seconds it is allowed to run without yielding
-- @param twarnlimit (optional) time in seconds it is allowed before cb is called
-- (must be smaller than tkilllimit)
-- @param cb (optional) callback executed when the kill or warn limit is reached. 
-- The callback has 1 parameter (string value being either "warn" or "kill"), but runs 
-- on the coroutine that is subject of the warning. If the "warn" callback returns a 
-- truthy value (neither false, nor nil) the coro the timeouts for kill and warn limits 
-- will be reset (buying more time for the coroutine to finish its business).
-- NOTE: the callback runs inside a debughook.
-- @return coro
coroutine.watch = function(coro, tkilllimit, twarnlimit, cb)
  if getwatch(coro) then error("Cannot create a watch, there already is one") end
  assert(tkilllimit or twarnlimit, "Either kill limit or warn limit must be provided")
  if twarnlimit then assert(cb, "A callback function must be provided when adding a warnlimit") end
  if tkilllimit and twarnlimit then assert(tkilllimit>twarnlimit, "The warnlimit must be smaller than the killlimit") end
  createwatch(coro, tkilllimit, twarnlimit, cb)
  return coro
end
watch = coroutine.watch

---------------------------------------------------------------------------------------
-- This is the same as the regular coroutine.create(), except that when the running 
-- coroutine is watched, then children spawned will also be watched with the same
-- settings.
coroutine.create = function(f)
  local s = getwatch(cororunning())
  if not s then return corocreate(f) end  -- I'm not being watched
  -- create and add watch
  return watch(corocreate(f), s.tkilllimit, s.twarnlimit, s.cb)
end
create = coroutine.create

---------------------------------------------------------------------------------------
-- This is the same as the regular coroutine.wrap(), except that when the running 
-- coroutine is watched, then children spawned will also be watched with the same
-- settings. To set sepecific settings for watching use coroutine.wrapf()
-- @see coroutine.wrapf
coroutine.wrap = function(f)
  if not getwatch(cororunning()) then return corowrap(f) end  -- not watched
  local coro = create(f)
  return function(...) return resume(coro, ...) end
end

---------------------------------------------------------------------------------------
-- This is the same as the regular coroutine.wrap(), except that the coroutine created
-- is watched according to the parameters provided, and not according to the watch
-- parameters of the currently running coroutine.
-- @param f function to wrap
-- @param tkilllimit see coroutine.create
-- @param twarnlimit see coroutine.create
-- @param cb see coroutine.create
-- @see coroutine.create 
-- @see coroutine.wrap
coroutine.wrapf = function(f, tkilllimit, twarnlimit, cb)
  local coro = watch(corocreate(f), tkilllimit, twarnlimit, cb)
  return function(...) return resume(coro, ...) end
end

---------------------------------------------------------------------------------------
-- This is the same as the regular coroutine.resume().
coroutine.resume = function(coro, ...)
  assert(type(coro) == "thread", "Expected thread, got "..type(coro))
  local e = getwatch(coro)
  if e then
    if e.errmsg then
      -- the coro being resumed is tagged with an error. This means that somewhere the error
      -- was thrown, but the coro didn't die (probably a pcall in between). The coro should have died
      -- but didn't so it is in an 'undetermined' state. Return error, don't resume
      return false, e.errmsg
    end
    local t = coroutine.gettime()
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
resume = coroutine.resume

---------------------------------------------------------------------------------------
-- This is the same as the regular coroutine.yield().
coroutine.yield = function(...)
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

---------------------------------------------------------------------------------------
-- This is the same as the regular coroutine.status().
coroutine.status = function(coro)
  if (getwatch(coro) or {}).errmsg then
    return "dead"
  else
    return corostatus(coro)
  end
end

---------------------------------------------------------------------------------------
-- This is the same as the regular debug.sethook(), except that when trying to set a 
-- hook on a coroutine that is being watched, if will throw an error.
debug.sethook = function(coro, ...)
  if getwatch(coro) then
    error("Cannot set a debughook because corowatch is watching this coroutine", 2)
  end
  -- not watched, so do the regular thing
  return sethook(coro, ...)
end

-- export some internals for testing if requested
if _TEST then
  coroutine._register = register
  coroutine._getwatch = getwatch
end

return coroutine
