corowatch
=========

Lua module to watch coroutine usage and kill a coroutine if it fails to yield in a timely manner. The main purpose is preventing code from locking the Lua state.
As a convenience function coroutine.wrapf() is included which allows any function to be watched, not only coroutines.

Implementation notes
====================

1. To protect access to coroutines, the module must override the existing coroutine functions. Besides overriding the `create()`, `wrap()`, `status()`, `yield()`, and `resume()` functions, it adds additional functions `watch()`, `wrapf()` and `gettime()` to the global `coroutine` table. 
1. Additionally the global `debug.sethook()` is modified to prevent a coroutine from removing it's own 'watch' routine (from the paranoia department).
1. __Important__: The default `gettime()` function loads LuaSocket to use the `socket.gettime()` function. If you do not use LuaSocket, then it might be better to replace `coroutine.gettime()` with a more lightweight implementation.

Usage
=====
Usage is fairly simple, call the `watch()` method on a coroutine to protect it and provide the timeouts and callbacks as required.

Example (see the `./examples` folder):

```lua
require("corowatch")

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

print(coroutine.resume(coroutine.watch(coroutine.create(f), kill_timeout, warn_timeout, cb)))
````

When run the example code returns the following results;
````
Warning, coroutine might get killed....1
Warning, coroutine might get killed....2
Warning, coroutine might get killed....3
now killing coroutine...
false	Coroutine exceeded its allowed running time of 1 seconds, without yielding
````

Documentation
=============
The documentation is available [online at GitHub](http://tieske.github.com/corowatch/)

Tests
=====
Tests are located in the `./spec` folder and can be run using [busted](http://olivinelabs.com/busted/)

License
=======
MIT license

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

