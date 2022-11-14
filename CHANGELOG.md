# CHANGELOG

#### Releasing new versions

- create a release branch
- update the changelog below
- update version and copyright-years in `./LICENSE` and `./src/corowatch.lua` (in doc-comments
  header, and in module constants)
- create a new rockspec and update the version inside the new rockspec:<br/>
  `cp corowatch-scm-1.rockspec ./rockspecs/corowatch-X.Y.Z-1.rockspec`
- test: run `make test` and `make lint`
- clean and render the docs: run `make clean` and `make docs`
- commit the changes as `release X.Y.Z`
- push the commit, and create a release PR
- after merging tag the release commit with `vX.Y.Z`
- upload to LuaRocks:<br/>
  `luarocks upload ./rockspecs/corowatch-X.Y.Z-1.rockspec --api-key=ABCDEFGH`
- test the newly created rock:<br/>
  `luarocks install corowatch`


### unreleased

- in Lua 5.1, sethook should be called without "coro" for the main thread
- make pack/unpack nil-safe

### Version 1.0, released 04-Feb-2014

- no automatic monkey patching of globals anymore

### Version 0.2, released 07-Apr-2013

- fixed debughook settings, improved performance

### Version 0.1, released 04-Apr-2013

- initial release
