local package_name = "corowatch"
local package_version = "scm"
local rockspec_revision = "1"
local github_account_name = "Tieske"
local github_repo_name = "corowatch"


package = package_name
version = package_version.."-"..rockspec_revision

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = (package_version == "scm") and "master" or nil,
  tag = (package_version ~= "scm") and ("v"..package_version) or nil,
}

description = {
  summary = "Watching and killing coroutines.",
  detailed = [[
    Provides a way to limit the runtime of a coroutine.
    This prevents rogue code from locking your Lua state
    by not yielding in a timely manner. Coroutines that
    take longer than the maximum specified can be killed.
  ]],
  license = "MIT",
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",

  modules = {
    ["corowatch"] = "src/corowatch.lua",
  },

  copy_directories = {
    -- can be accessed by `luarocks corowatch doc` from the commandline
    "docs",
  },
}
