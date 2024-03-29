---------------------------------------------------------------------------------------
-- Module to watch coroutine executiontime. Coroutines running too long without
-- yielding can be killed to prevent them from locking the Lua state.
-- The module uses `LuaSocket` to get the time (`socket.gettime` function). If you
-- do not want that, override the `coroutine.gettime` method with your own
-- implementation.
--
-- @copyright Copyright (c) 2013-2022 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE.md`.
-- @name corowatch
-- @class module

local M = {}    -- module table
M._VERSION = "1.1"
M._COPYRIGHT = "Copyright (c) 2013-2022 Thijs Schreijer"
M._DESCRIPTION = "Lua module to watch coroutine usage and kill a coroutine if it fails to yield in a timely manner."


local corocreate = coroutine.create
local cororesume = coroutine.resume
local cororunning = coroutine.running
local corostatus = coroutine.status
local corowrap = coroutine.wrap
local coroyield = coroutine.yield
local _sethook = debug.sethook
local traceback = debug.traceback
local watch, resume, create
local default_hookcount = 10000


local pack, unpack do -- pack/unpack to create/honour the .n field for nil-safety
  local _unpack = _G.table.unpack or _G.unpack
  function pack (...) return { n = select('#', ...), ...} end
  function unpack(t, i, j) return _unpack(t, i or 1, j or t.n or #t) end
end

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
--   hookcount = the count setting for the debughook
-- }


local mainthread = {}  -- for 5.1 where there is no main thread access, running() returns nil
local function sethook(coro, ...)  -- compatibility for Lua 5.1
  if coro == mainthread then
    return _sethook(...)
  end
  return _sethook(coro, ...)
end

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
local createwatch = function(coro, tkilllimit, twarnlimit, cb, hookcount)
  coro = coro or cororunning() or mainthread
  hookcount = hookcount or default_hookcount
  local entry = register[coro] or {}
  entry.tkilllimit = tkilllimit
  entry.twarnlimit = twarnlimit
  entry.cb = cb
  entry.hook = checkhook
  entry.debug = traceback()
  entry.hookcount = hookcount
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
-- The callback has 1 parameter (string value being either "warn" or "kill"), but runs
-- on the coroutine that is subject of the warning. If the "warn" callback returns a
-- truthy value (neither `false`, nor `nil`) then the timeouts for kill and warn limits
-- will be reset (buying more time for the coroutine to finish its business).
--
-- The `hookcount` default of 10000 will ensure offending coroutines are caught with
-- limited performance impact. To better narrow down any offending code that takes too long,
-- this can be set to a lower value (eg. set it to 1, and it will break right after
-- the instruction that tripped the limit). But the smaller the value, the higher the
-- performance cost.
--
-- NOTE: the callback runs inside a debughook.
-- @tparam coroutine|nil coro coroutine to be protected, defaults to the currently running routine
-- @tparam number|nil tkilllimit time in seconds it is allowed to run without yielding
-- @tparam number|nil twarnlimit time in seconds it is allowed before `cb` is called
-- (must be smaller than `tkilllimit`)
-- @tparam function|nil cb callback executed when the kill or warn limit is reached.
-- @tparam[opt=10000] number hookcount the hookcount to use (every `x` number of VM instructions check the limits)
-- @return coro
M.watch = function(coro, tkilllimit, twarnlimit, cb, hookcount)
  if getwatch(coro) then
    error("Cannot create a watch, there already is one")
  end
  assert(tkilllimit or twarnlimit, "Either kill limit or warn limit must be provided")
  if twarnlimit ~= nil then
    assert(type(twarnlimit) == "number", "Expected warn-limit to be a number")
    assert(cb, "A callback function must be provided when adding a warnlimit")
  end
  if tkilllimit ~= nil then
    assert(type(tkilllimit) == "number", "Expected kill-limit to be a number")
    if twarnlimit then
      assert(tkilllimit>twarnlimit, "The warnlimit must be smaller than the killlimit")
    end
  end
  if cb ~= nil then
    assert(type(cb) == "function", "Expected callback to be a function")
  end
  if hookcount ~= nil then
    assert(type(hookcount) == "number", "Expected hookcount to be a number")
    assert(hookcount >= 1, "The hookcount cannot be less than 1")
  end
  createwatch(coro, tkilllimit, twarnlimit, cb, hookcount)
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
  return watch(corocreate(f), s.tkilllimit, s.twarnlimit, s.cb, s.hookcount)
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
-- @tparam function f function to wrap
-- @tparam number|nil tkilllimit see `watch`
-- @tparam number|nil twarnlimit see `watch`
-- @tparam function|nil cb see `watch`
-- @tparam[opt=10000] number hookcount see `watch`
-- @see create
-- @see wrap
M.wrapf = function(f, tkilllimit, twarnlimit, cb, hookcount)
  local coro = watch(corocreate(f), tkilllimit, twarnlimit, cb, hookcount)
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
  local r = pack(cororesume(coro, ...))
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
-- @tparam[opt] table t table to which to export the coroutine functions.
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
if _TEST then  -- luacheck: ignore
  M._register = register
  M._getwatch = getwatch
end

return M
