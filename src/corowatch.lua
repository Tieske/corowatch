---------------------------------------------------------------------------------------
-- Module to watch coroutine executiontime. Coroutines running too long without
-- yielding can be killed to prevent them from locking the Lua state.
-- The module uses `LuaSocket` to get the time (`socket.gettime` function). If you
-- do not want that, override the `coroutine.gettime` method with your own
-- implementation.
--
-- Version 1.0, [copyright (c) 2013-2014 - Thijs Schreijer](http://www.thijsschreijer.nl)
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

local M = {}    -- module table

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
  local t = M.gettime()
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
-- returns current time in seconds. If not overridden, it will require `luasocket` and use
-- `socket.gettime` to get the current time.
M.gettime = function()
  M.gettime = require("socket").gettime
  return M.gettime()
end

---------------------------------------------------------------------------------------
-- Protects a coroutine from running too long without yielding.
-- @param coro coroutine to be protected
-- @param tkilllimit (optional) time in seconds it is allowed to run without yielding
-- @param twarnlimit (optional) time in seconds it is allowed before `cb` is called
-- (must be smaller than `tkilllimit`)
-- @param cb (optional) callback executed when the kill or warn limit is reached. 
-- The callback has 1 parameter (string value being either "warn" or "kill"), but runs 
-- on the coroutine that is subject of the warning. If the "warn" callback returns a 
-- truthy value (neither `false`, nor `nil`) then the timeouts for kill and warn limits 
-- will be reset (buying more time for the coroutine to finish its business).
-- NOTE: the callback runs inside a debughook.
-- @return coro
M.watch = function(coro, tkilllimit, twarnlimit, cb)
  if getwatch(coro) then error("Cannot create a watch, there already is one") end
  assert(tkilllimit or twarnlimit, "Either kill limit or warn limit must be provided")
  if twarnlimit then assert(cb, "A callback function must be provided when adding a warnlimit") end
  if tkilllimit and twarnlimit then assert(tkilllimit>twarnlimit, "The warnlimit must be smaller than the killlimit") end
  createwatch(coro, tkilllimit, twarnlimit, cb)
  return coro
end
watch = M.watch

---------------------------------------------------------------------------------------
-- This is the same as the regular `coroutine.create`, except that when the running 
-- coroutine is watched, then children spawned will also be watched with the same
-- settings.
-- @param f see `coroutine.create`
M.create = function(f)
  local s = getwatch(cororunning())
  if not s then return corocreate(f) end  -- I'm not being watched
  -- create and add watch
  return watch(corocreate(f), s.tkilllimit, s.twarnlimit, s.cb)
end
create = M.create

---------------------------------------------------------------------------------------
-- This is the same as the regular `coroutine.wrap`, except that when the running 
-- coroutine is watched, then children spawned will also be watched with the same
-- settings. To set sepecific settings for watching use `coroutine.wrapf`.
-- @param f see `coroutine.wrap`
-- @see wrapf
M.wrap = function(f)
  if not getwatch(cororunning()) then return corowrap(f) end  -- not watched
  local coro = create(f)
  return function(...) return resume(coro, ...) end
end

---------------------------------------------------------------------------------------
-- This is the same as the regular `coroutine.wrap`, except that the coroutine created
-- is watched according to the parameters provided, and not according to the watch
-- parameters of the currently running coroutine.
-- @param f function to wrap
-- @param tkilllimit see `watch`
-- @param twarnlimit see `watch`
-- @param cb see `watch`
-- @see create
-- @see wrap
M.wrapf = function(f, tkilllimit, twarnlimit, cb)
  local coro = watch(corocreate(f), tkilllimit, twarnlimit, cb)
  return function(...) return resume(coro, ...) end
end

---------------------------------------------------------------------------------------
-- This is the same as the regular `coroutine.resume`.
-- @param coro see `coroutine.resume`
-- @param ... see `coroutine.resume`
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
resume = M.resume

---------------------------------------------------------------------------------------
-- This is the same as the regular `coroutine.yield`.
-- @param ... see `coroutine.yield`
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

---------------------------------------------------------------------------------------
-- This is the same as the regular `coroutine.status`.
-- @param coro see `coroutine.status`
M.status = function(coro)
  if (getwatch(coro) or {}).errmsg then
    return "dead"
  else
    return corostatus(coro)
  end
end

---------------------------------------------------------------------------------------
-- This is the same as the regular `debug.sethook`, except that when trying to set a 
-- hook on a coroutine that is being watched, if will throw an error.
-- @param coro see `debug.sethook`
-- @param ... see `debug.sethook`
M.sethook = function(coro, ...)
  if getwatch(coro) then
    error("Cannot set a debughook because corowatch is watching this coroutine", 2)
  end
  -- not watched, so do the regular thing
  return sethook(coro, ...)
end

---------------------------------------------------------------------------------------
-- Export the corowatch functions to an external table, or the global environment.
-- The functions exported are `create`, `yield`, `resume`, `status`, `wrap`, and `wrapf`. The standard 
-- `coroutine.running` will be added if there is no `running` value in the table yet. So 
-- basically it exports a complete `coroutine` table + `wrapf`.
-- If the provided table contains subtables `coroutine` and/or `debug` then it is assumed to
-- be a function/global environment and `sethook` will be exported as well (exports will then
-- go into the two subtables)
-- @param t table (optional) to which to export the coroutine functions. 
-- @return the table provided, or a new table if non was provided, with the exported functions
-- @usage
-- -- monkey patch global environment, both coroutine and debug tables
-- require("corowatch").export(_G)
M.export = function(t)
  t = t or {}
  local c, d 
  assert(type(t) == "table", "Expected table, got "..type(t))
  if (type(t.debug) == "table") or type(t.coroutine == "table") then
    -- we got a global table, so monkeypatch debug and coroutine table
    d = t.debug
    c = t.coroutine
  else
    -- we got something else, just export coroutine here
    d = nil
    c = t
  end
  if type(d) == "table" then
    d.sethook = M.sethook
  end
  if type(c) == "table" then
    c.yield = M.yield
    c.create = M.create
    c.resume = M.resume
    c.running = c.running or cororunning
    c.status = M.status
    c.wrap = M.wrap
    c.wrapf = M.wrapf
  end
  return t
end

-- export some internals for testing if requested
if _TEST then
  M._register = register
  M._getwatch = getwatch
end

return M
