local Configuration = require "cosy.configuration"
local I18n          = require "cosy.i18n"
local Logger        = require "cosy.logger"

Configuration.load "cosy.nginx"

local i18n   = I18n.load "cosy.nginx"
i18n._locale = Configuration.locale._

local Nginx = {}

local configuration_template = [[
error_log   error.log;
pid         {{{pidfile}}};

worker_processes 1;
events {
  worker_connections 1024;
}

http {
  tcp_nopush            on;
  tcp_nodelay           on;
  keepalive_timeout     65;
  types_hash_max_size   2048;

  proxy_temp_path       proxy;
  proxy_cache_path      cache   keys_zone=foreign:10m;
  lua_package_path      "{{{path}}}";

  include /etc/nginx/mime.types;

  gzip              on;
  gzip_min_length   0;
  gzip_types        *;
  gzip_proxied      no-store no-cache private expired auth;

  server {
    listen        localhost:{{{port}}};
    listen        {{{host}}}:{{{port}}};
    server_name   "{{{name}}}";
    charset       utf-8;
    index         index.html;
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    access_log    access.log;
    root          "{{{www}}}";
    
    location / {
      try_files $uri $uri/ /index.html @foreigns;
    }

    location @foreigns {
      proxy_cache  foreign;
      expires      modified  1d;
      resolver     {{{resolver}}};
      set $target "";
      access_by_lua '
        local redis   = require "nginx.redis" :new ()
        local ok, err = redis:connect ("{{{redis_host}}}", {{{redis_port}}})
        if not ok then
          ngx.log (ngx.ERR, "failed to connect to redis: ", err)
          return ngx.exit (500)
        end
        redis:select ({{{redis_database}}})
        local target = redis:get ("foreign:" .. ngx.var.uri)
        if not target or target == ngx.null then
          return ngx.exit (404)
        end
        ngx.var.target = target
      ';
      proxy_pass $target;
    }

    location /lua {
      default_type  application/lua;
      root          /;
      set $target   "";
      access_by_lua '
        local name = ngx.var.uri:match "/lua/(.*)"
        local filename = package.searchpath (name, "{{{path}}}")
        if filename then
          ngx.var.target = filename
        else
          ngx.log (ngx.ERR, "failed to locate lua module: " .. name)
          return ngx.exit (404)
        end
      ';
      try_files     $target =404;
    }

    location /ws {
      proxy_pass          http://{{{wshost}}}:{{{wsport}}};
      proxy_http_version  1.1;
      proxy_set_header    Upgrade $http_upgrade;
      proxy_set_header    Connection "upgrade";
    }

    location /hook {
      content_by_lua '
        local temporary = os.tmpname ()
        local file      = io.open (temporary, "w")
        file:write [==[
          git pull --quiet --force
          luarocks install --local --force --only-deps cosyverif
          for rock in $(luarocks list --outdated --porcelain | cut -f 1)
          do
          luarocks install --local --force ${rock}
          done
          rm --force $0
        ]==]
        file:close ()
        os.execute ("bash " .. temporary .. " &")
      ';
    }

  }
}
]]

function Nginx.configure ()
  local resolver
  do
    local file = io.open "/etc/resolv.conf"
    if not file then
      Logger.error {
        _ = i18n ["nginx:no-resolver"],
      }
    end
    local result = {}
    for line in file:lines () do
      local address = line:match "nameserver%s+(%S+)"
      if address then
        result [#result+1] = address
      end
    end
    file:close ()
    resolver = table.concat (result, " ")
  end
  local configuration = configuration_template % {
    host           = Configuration.http.interface._,
    port           = Configuration.http.port._,
    www            = Configuration.http.www._,
    pidfile        = Configuration.http.pid_file._,
    name           = Configuration.server.name._,
    wshost         = Configuration.server.interface._,
    wsport         = Configuration.server.port._,
    redis_host     = Configuration.redis.interface._,
    redis_port     = Configuration.redis.port._,
    redis_database = Configuration.redis.database._,
    path           = package.path,
    resolver       = resolver,
  }
  local file = io.open (Nginx.directory .. "/nginx.conf", "w")
  file:write (configuration)
  file:close ()
end

function Nginx.start ()
  Nginx.directory = os.tmpname ()
  Logger.debug {
    _         = i18n ["nginx:directory"],
    directory = Nginx.directory,
  }
  os.execute ([[
    rm -f {{{directory}}} && mkdir -p {{{directory}}}
  ]] % { directory = Nginx.directory })
  Nginx.configure ()
  os.execute ([[
    {{{nginx}}} -p {{{directory}}} -c {{{directory}}}/nginx.conf 2>> {{{directory}}}/error.log
  ]] % {
    nginx     = Configuration.http.nginx._,
    directory = Nginx.directory,
  })
end

function Nginx.stop ()
  os.execute ([[
    [ -f {{{pidfile}}} ] && {
      kill -QUIT $(cat {{{pidfile}}})
    }
  ]] % { pidfile = Configuration.http.pid_file._ })
  os.execute ([[
    rm -rf {{{directory}}}
  ]] % { directory = Nginx.directory })
  Nginx.directory = nil
end

function Nginx.update ()
  Nginx.configure ()
  os.execute ([[
    [ -f {{{pidfile}}} ] && {
      kill -HUP $(cat {{{pidfile}}})
    }
  ]] % { pidfile = Configuration.http.pid_file._ })
end

return Nginx
