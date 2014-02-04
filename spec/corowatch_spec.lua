local corowatch

describe("testing the corowatch module", function()
  
  setup(function()
    corowatch = require("corowatch")
    corowatch.export(_G)
  end)
  
  teardown(function()
  end)

  before_each(function()
  end)
  
  after_each(function()
    collectgarbage()  -- make sure to collect weak references in register table
  end)
  
  it("Checks exported methods", function()
    local coroutine = {}
    local debug = {}
    local globals = {coroutine = coroutine, debug = debug}
    corowatch.export(globals)
    assert.are_equal(corowatch.wrapf,coroutine.wrapf)
    assert.are_equal(corowatch.create,coroutine.create)
    assert.are_equal(corowatch.yield,coroutine.yield)
    assert.are_equal(corowatch.resume,coroutine.resume)
    assert.are_equal(corowatch.wrap,coroutine.wrap)
    --assert.are_equal(corowatch.running,coroutine.running)
    assert.are_equal(corowatch.status,coroutine.status)
    assert.are_equal(corowatch.sethook,debug.sethook)
  end)
    
  it("Checks a coroutine being registered when watched", function()
    local kill_expect, warn_expect, cb_expect = 2, 1, function() end
    assert.is_nil(next(corowatch._register))  -- check register is empty when starting
    local c = corowatch.watch(coroutine.create(function() end), kill_expect, warn_expect, cb_expect)
    local w = corowatch._register[c]
    assert.not_is_nil(w)
    assert.are_equal(kill_expect, w.tkilllimit)
    assert.are_equal(warn_expect, w.twarnlimit)
    assert.are_equal(cb_expect, w.cb)
    assert.is_nil(w.warned)
    assert.is_nil(w.errmsg)
    assert.is_nil(w.killtime)
    assert.is_nil(w.warntime)
    assert.are_equal(debug.gethook(c), w.hook)
  end)
  
  it("Checks a watch entry when a coroutine is resumed", function()
    local kill_expect, warn_expect, cb_expect = 2, 1, function() end
    assert.is_nil(next(corowatch._register))  -- check register is empty when starting
    local w = {}
    local f = function()
        -- copy contents of watch table now the coro is running
        for k,v in pairs(corowatch._register[coroutine.running()]) do
          w[k] = v
        end
      end
    local c = corowatch.watch(coroutine.create(f), kill_expect, warn_expect, cb_expect)
    local t = corowatch.gettime()
    coroutine.resume(c)
    assert.are_equal(kill_expect, w.tkilllimit)
    assert.are_equal(warn_expect, w.twarnlimit)
    assert.are_equal(cb_expect, w.cb)
    assert.is_nil(w.warned)
    assert.is_nil(w.errmsg)
    assert.are_equal(t, w.killtime - kill_expect)
    assert.are_equal(t, w.warntime - warn_expect)
    assert.are_equal(debug.gethook(c), w.hook)
  end)

  it("Checks a watch entry when a coroutine is yielded", function()
    local kill_expect, warn_expect, cb_expect = 2, 1, function() end
    assert.is_nil(next(corowatch._register))  -- check register is empty when starting
    local f = function()
        coroutine.yield(123, "abc")
      end
    local c = corowatch.watch(coroutine.create(f), kill_expect, warn_expect, cb_expect)
    local ok, one, two = coroutine.resume(c)
    local w = corowatch._register[c]
    assert.is_true(ok)
    assert.are_equal(123, one)
    assert.are_equal("abc", two)
    assert.are_equal(kill_expect, w.tkilllimit)
    assert.are_equal(warn_expect, w.twarnlimit)
    assert.are_equal(cb_expect, w.cb)
    assert.is_nil(w.warned)
    assert.is_nil(w.errmsg)
    assert.is_nil(w.killtime)
    assert.is_nil(w.warntime)
    assert.are_equal(debug.gethook(c), w.hook)
  end)

  it("Checks errors when creating a watch", function()
    local c = corowatch.watch(coroutine.create(function() end), 2, 1, function() end)
    assert.has_error(function()
          corowatch.watch(c)  -- cannot add another watch
        end)
    assert.has_error(function() -- when warnlimit, also callback must be provided
          c = corowatch.watch(coroutine.create(function() end), 2, 1)
        end)
    assert.has_error(function() -- either warnlimit or killlimit must be provided
          c = corowatch.watch(coroutine.create(function() end))
        end)
    assert.has_error(function() -- warnlimit must be smaller than killimit
          c = corowatch.watch(coroutine.create(function() end), 1, 2)
        end)
  end)
  
  it("checks that a coroutine created from a watched coroutine is also watched", function()
    local kill_expect, warn_expect, cb_expect = 2, 1, function() end
    local first, second
    local f = function()
      second = coroutine.create(function() end)
    end
    first = corowatch.watch(coroutine.create(f), kill_expect, warn_expect, cb_expect)
    coroutine.resume(first)
    -- now check whether 'second' inherited the watch values
    local w = corowatch._register[second]
    assert.not_is_nil(w)
    assert.are_equal(kill_expect, w.tkilllimit)
    assert.are_equal(warn_expect, w.twarnlimit)
    assert.are_equal(cb_expect, w.cb)
    assert.is_nil(w.warned)
    assert.is_nil(w.errmsg)
    assert.is_nil(w.killtime)
    assert.is_nil(w.warntime)
    assert.are_equal(debug.gethook(second), w.hook)    
  end)
  
  it("checks that a timedout coroutine gets status 'dead'", function()
    local kill_expect, warn_expect, cb_expect = 2, 1, function() end
    local f = function() end
    local c = corowatch.watch(coroutine.create(f), kill_expect, warn_expect, cb_expect)
    assert.are_equal("suspended", coroutine.status(c))
    local w = corowatch._register[c]
    w.errmsg = "just some error that is not nil"
    assert.are_equal("dead", coroutine.status(c))
  end)
  
  it("checks killing and warning time", function()
    local kill_expect, warn_expect = .5, .25
    local tt = {}
    local warncount = 1
    local killcount = 0
    local cb = function(cbt)
        if cbt == "kill" then
          killcount = killcount + 1
          return
        end
        warncount = warncount + 1
        tt[warncount] = corowatch.gettime()
        if warncount < 3 then return true end  -- continue
      end
    local f = function() 
        -- just do something silly in a loop
        while true do
          local i = 0
          i = i + 1
          i = i - 1
        end
      end
    local c = corowatch.watch(coroutine.create(f), kill_expect, warn_expect, cb)
    tt[1] = corowatch.gettime()
    local ok, msg = coroutine.resume(c)
    tt[4] = corowatch.gettime()
    local w = corowatch._getwatch(c)
    assert.is_false(ok)
    assert.are_equal(msg, w.errmsg)
    assert.are_equal(3, warncount)
    assert.are_equal(1, killcount)
    assert(tt[2]-tt[1]-warn_expect < 0.1, "expected time difference to be less than 0.1 seconds")
    assert(tt[3]-tt[2]-warn_expect < 0.1, "expected time difference to be less than 0.1 seconds")
    assert(tt[4]-tt[3]-kill_expect < 0.1, "expected time difference to be less than 0.1 seconds")
    assert.are_equal("dead", coroutine.status(c))
  end)

  it("checks that coroutine.wrap() works as expected with a watched coroutine", function()
    local f = function() 
        local t = corowatch.gettime() + 3
        while t > corowatch.gettime() do
          -- do something silly in a loop
          local i = 0
          i = i + 1
          i = i - 1
        end
      end
    local wf
    -- create/run a watched coroutine from which 'wrap' is called
    coroutine.resume(corowatch.watch(coroutine.create(function()
          wf = coroutine.wrap(f)
        end), 0.25))
    -- now the coroutine embedded in wf should be watched
    local one, two = wf()
    assert.is_false(one)  -- failure report
    assert.is_string(two) -- error message
  end)
  
  
end)
