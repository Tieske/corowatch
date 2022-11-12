# 1. Introduction

Lua module to watch coroutine usage and kill a coroutine if it fails to yield in a timely manner. The main purpose is preventing code from locking the Lua state.
As a convenience function coroutine.wrapf() is included which allows any function to be watched, not only coroutines.


## 1.1 Implementation notes

1. To protect access to coroutines, the module must override the existing coroutine functions. Besides overriding the `create()`, `wrap()`, `status()`, `yield()`, and `resume()` functions, it adds additional functions `watch()`, `wrapf()` and `gettime()` to the global `coroutine` table.
1. Additionally the global `debug.sethook()` is modified to prevent a coroutine from removing it's own 'watch' routine (from the paranoia department).
1. When using LuaJIT, debug-hooks will not be called in jitted code. Hence JIT compilation must be turned off; `if jit then jit.off() end`.
1. __Important__: The default `gettime()` function loads LuaSocket to use the `socket.gettime()` function. If you do not use LuaSocket, then it might be better to replace `coroutine.gettime()` with a more lightweight implementation.


## 1.2 Usage

Usage is fairly simple, call the `watch()` method on a coroutine to protect it and provide the timeouts and callbacks as required.

Example (see the `./examples` folder):

```lua
require("corowatch").export(_G) -- monkey patch the globals

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
    if warncount < 4 then
      return true   -- reset the timeouts
    end
  end
end

print(coroutine.resume(corowatch.watch(coroutine.create(f), kill_timeout, warn_timeout, cb)))
````

When run the example code returns the following results;
````
Warning, coroutine might get killed....1
Warning, coroutine might get killed....2
Warning, coroutine might get killed....3
now killing coroutine...
false	Coroutine exceeded its allowed running time of 1 seconds, without yielding
````


## 1.3 Limitations

The mechanics of this library depend on the debug library. A debug hook is set to repeatedly (once every 10000 VM instructions) check the coroutine for a time out. When a timeout is detected, an error is generated that will kill the coroutine (coroutine status will be 'dead'). There are two ways that it won't work;

1. When a C function is being executed; the debughooks can only interrupt Lua code, not C code. So if C code takes too long or locks, it won't be interrupted.
1. When the running code that gets interrupted is inside a protected call (Lua side `pcall()`, `xpcall()` or C-side `lua_pcall()`) then the error thrown by corowatch will not kill the coroutine, but it will be caught by that protected call.

To mitigate these situations; the debughook is altered once the first error is thrown. It will from there on run every 1 VM instruction. This will then rethrow the same error directly after the C function or protected call that caught the previous error. This process is repeated until the coroutine dies, and effectively cascades the error up the callstack.
