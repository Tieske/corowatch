local corowatch = require("corowatch")
corowatch.export(_G)

local f = function()
  local callcount = 0
  while true do
    -- something for a coroutine to do here
    callcount = callcount + 1
  end
end
local kill_timeout = 1   -- seconds
local warn_timeout = 0.8 -- seconds
local warncount = 0
local cb = function(cbtype)
  if cbtype == "kill" then
    print("now killing coroutine...")
  elseif cbtype == "warn" then
    warncount = warncount + 1
    print("Warning, coroutine might get killed...." .. warncount)
    if warncount < 3 then
      return true   -- reset the timeouts
    end
  end
end

print(coroutine.resume(corowatch.watch(coroutine.create(f), kill_timeout, warn_timeout, cb)))