local corowatch

describe("testing the corowatch module", function()
  
  setup(function()
    corowatch = require("corowatch")
  end)
  
  teardown(function()
  end)

  before_each(function()
  end)
  
  after_each(function()
    collectgarbage()  -- make sure to collect weak references in register table
  end)
  
  it("Checks exported methods", function()
    assert.are_equal(corowatch.watch,coroutine.watch)
    assert.are_equal(corowatch.create,coroutine.create)
    assert.are_equal(corowatch.yield,coroutine.yield)
    assert.are_equal(corowatch.resume,coroutine.resume)
    assert.are_equal(corowatch.wrap,coroutine.wrap)
    assert.are_equal(corowatch.running,coroutine.running)
    assert.are_equal(corowatch.status,coroutine.status)
  end)
    
  it("Checks a coroutine being registered when watched", function()
    local kill_expect, warn_expect, cbwarn_expect = 2, 1, function() end
    assert.is_nil(next(corowatch._register))  -- check register is empty when starting
    local c = coroutine.watch(coroutine.create(function() end), kill_expect, warn_expect, cbwarn_expect)
    local w = corowatch._register[c]
    assert.not_is_nil(w)
    assert.are_equal(kill_expect, w.tkilllimit)
    assert.are_equal(warn_expect, w.twarnlimit)
    assert.are_equal(cbwarn_expect, w.cbwarn)
    assert.is_nil(w.warned)
    assert.is_nil(w.errmsg)
    assert.is_nil(w.killtime)
    assert.is_nil(w.warntime)
    assert.are_equal(debug.gethook(c), w.hook)
  end)
  
  it("Checks a watch entry when a coroutine is running", function()
    local kill_expect, warn_expect, cbwarn_expect = 2, 1, function() end
    assert.is_nil(next(corowatch._register))  -- check register is empty when starting
    local w = {}
    local f = function()
        -- copy contents of watch table now the coro is running
        for k,v in pairs(corowatch._register[coroutine.running()]) do
          w[k] = v
        end
      end
    local c = coroutine.watch(coroutine.create(f), kill_expect, warn_expect, cbwarn_expect)
    local t = corowatch.gettime()
    coroutine.resume(c)
    assert.are_equal(kill_expect, w.tkilllimit)
    assert.are_equal(warn_expect, w.twarnlimit)
    assert.are_equal(cbwarn_expect, w.cbwarn)
    assert.is_nil(w.warned)
    assert.is_nil(w.errmsg)
    assert.are_equal(t, w.killtime - kill_expect)
    assert.are_equal(t, w.warntime - warn_expect)
    assert.are_equal(debug.gethook(c), w.hook)
  end)

end)
