local socket = require("socket")
require("corowatch")

local t = socket.gettime()
local i = 0
local checkcount=0

local corof1 = function()
  while t+5>socket.gettime() do
    i = i + 1
  end
  print("Loop completed")
end

print(socket.gettime()-t)
local coro = coroutine.watch(coroutine.create(corof1), 4, 2, function() print("warning!!", socket.gettime()-t) end)

print(coroutine.resume(coro))
print(socket.gettime()-t)
print("CheckCount:",checkcount,"\nLoopCount", i)

