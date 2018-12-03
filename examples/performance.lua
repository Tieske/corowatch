
--package.path = "C:\\Users\\Thijs\\Dropbox\\Lua projects\\corowatch\\src\\?.lua;"..package.path
local corowatch = require("corowatch")
corowatch.export(_G)

local res = 1

local testfunc = function()
  for n = 1,2000000 do
    res=math.sin(n/1000)
  end
  return res
end

local function test1()
  collectgarbage()
  collectgarbage()
  collectgarbage("stop")
  local t1 = corowatch.gettime()
  testfunc()
  t1 = corowatch.gettime() - t1
  collectgarbage("restart")
  collectgarbage()
  collectgarbage()
  return t1
end

local function test2(wrapper)
  -- wrapper = coroutine.wrap, or coroutine.wrapf
  collectgarbage()
  collectgarbage()
  collectgarbage("stop")
  local t2 = corowatch.gettime()
  wrapper(testfunc, 10001, 10000, function() end)()
  t2 = corowatch.gettime() - t2
  collectgarbage("restart")
  collectgarbage()
  collectgarbage()
  return t2
end

-- warm up
for n = 1,3 do
  test1()
  test2(coroutine.wrap)
  test2(coroutine.wrapf)   -- luacheck: ignore
end

-- run test
local t0, t1, t2, iter = 0,0,0,10
for n = 1,iter do
  t0=test1() + t0
  t1=test2(coroutine.wrap) + t1
  t2=test2(coroutine.wrapf) + t2   -- luacheck: ignore
end
t0=t0/iter  -- main loop
t1=t1/iter  -- coroutine
t2=t2/iter  -- protected coroutine

print("Mainloop :",t0)
print("Coroutine:",t1)
print("Corowatch:",t2)
print("corowatch is " .. math.floor((t2-t1)/t1 *100) .. "% slower than unprotected")
print("coroutine is " .. math.floor((t0-t1)/t0 *100) .. "% faster than the main loop")

