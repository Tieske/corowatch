package = "corowatch"
version = "0.1-1"
source = {
  url = "https://getithere.tar.gz",
  dir = "corowatch"
}
description = {
  summary = "Watching and killing coroutines.",
  detailed = [[
    Provides a way to limit the runtime of a coroutine.
    This prevents rogue code from locking your Lua state
    by not yielding in a timely manner. Coroutines that
    take longer than the maximum specified can be killed.
  ]],
  homepage = "http://",
  license = "MIT <http://opensource.org/licenses/MIT>"
}
dependencies = {
  "lua >= 5.1",
}
build = {
  type = "builtin",
  modules = {
    ["corowatch"] = "src/corowatch.lua",
  },
}
