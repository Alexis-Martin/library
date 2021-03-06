package = "cosyverif"
version = "master-1"

source = {
  url = "git://github.com/cosyverif/library",
}

description = {
  summary     = "CosyVerif Library",
  detailed    = [[]],
  homepage    = "http://www.cosyverif.org/",
  license     = "MIT/X11",
  maintainer  = "Alban Linard <alban.linard@lsv.ens-cachan.fr>",
}

dependencies = {
  "ansicolors >= 1",
  "bcrypt >= 2",
  "bit32 >= 5",
  "c3 >= 0",
  "cjson >= 2",
  "copas-ev >= 0",
  "coronest >= 0",
  "hotswap >= 0",
  "i18n >= 0",
  "lua >= 5.1",
  "lua_cliargs >= 2.5",
  "lua-cjson >= 2",
  "lua-ev >= v1.4",
  "lua-websockets >= v2",
  "luacrypto >= 0",
  "luajwt >= 1",
  "luafilesystem >= 1",
  "lualogging >= 1",
  "luasec >= 0",
  "luasocket >= 2",
  "lustache >= 1",
  "redis-lua >= 2",
  "serpent >= 0",
}

build = {
  type    = "builtin",
  modules = {
    ["cosy"                       ] = "src/cosy.lua",
    ["cosy.commands"              ] = "src/cosy/commands.lua",
    ["cosy.configuration"         ] = "src/cosy/configuration.lua",
    ["cosy.configuration.default" ] = "src/cosy/configuration/default.lua",
    ["cosy.daemon"                ] = "src/cosy/daemon.lua",
    ["cosy.digest"                ] = "src/cosy/digest.lua",
    ["cosy.email"                 ] = "src/cosy/email.lua",
    ["cosy.i18n"                  ] = "src/cosy/i18n.lua",
    ["cosy.i18n.en"               ] = "src/cosy/i18n/en.lua",
    ["cosy.library"               ] = "src/cosy/library.lua",
    ["cosy.loader"                ] = "src/cosy/loader.lua",
    ["cosy.logger"                ] = "src/cosy/logger.lua",
    ["cosy.methods"               ] = "src/cosy/methods.lua",
    ["cosy.nginx"                 ] = "src/cosy/nginx.lua",
    ["cosy.parameters"            ] = "src/cosy/parameters.lua",
    ["cosy.password"              ] = "src/cosy/password.lua",
    ["cosy.random"                ] = "src/cosy/random.lua",
    ["cosy.redis"                 ] = "src/cosy/redis.lua",
    ["cosy.repository"            ] = "src/cosy/repository.lua",
    ["cosy.scheduler"             ] = "src/cosy/scheduler.lua",
    ["cosy.server"                ] = "src/cosy/server.lua",
    ["cosy.socket"                ] = "src/cosy/socket.lua",
    ["cosy.store"                 ] = "src/cosy/store.lua",
    ["cosy.string"                ] = "src/cosy/string.lua",
    ["cosy.time"                  ] = "src/cosy/time.lua",
    ["cosy.token"                 ] = "src/cosy/token.lua",
    ["cosy.value"                 ] = "src/cosy/value.lua",
  },
  install = {
    bin = {
      ["cosy"] = "src/cosy.lua",
    },
  },
}
