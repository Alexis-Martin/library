local Loader        = require "cosy.loader"
local Configuration = require "cosy.configuration"
local Digest        = require "cosy.digest"
local I18n          = require "cosy.i18n"
local Json          = require "cosy.json"
local Value         = require "cosy.value"
local Scheduler     = require "cosy.scheduler"
local Coromake      = require "coroutine.make"

Configuration.load "cosy.library"

local i18n   = I18n.load "cosy.library"
i18n._locale = Configuration.locale._

local m18n   = I18n.load "cosy.methods"
m18n._locale = Configuration.locale._

local Library   = {}
local Client    = {}
local Operation = {}

local function threadof (f, ...)
  if Scheduler._running then
    f (...)
  else
    Scheduler.addthread (f, ...)
    Scheduler.loop ()
  end
end

function Client.connect (client)
  local data = client._data
  local url = "ws://{{{host}}}:{{{port}}}/ws" % {
    host = data.host,
    port = data.port,
  }
  if _G.js then
    client._ws = _G.js.new (_G.window.WebSocket, url, "cosy")
  else
    local Websocket = require "websocket"
    client._ws = Websocket.client.ev {
      timeout = Configuration.library.timeout._,
      loop    = Scheduler._loop,
    }
  end
  client._ws.onopen     = function ()
    client._status = "opened"
    Scheduler.wakeup (client._co)
  end
  client._ws.onclose    = function ()
    client._status = "closed"
    Scheduler.wakeup (client._co)
  end
  client._ws.onmessage  = function (_, event)
    local message 
    if _G.js then
      message = event.data
    else
      message = event
    end
    message = Value.decode (message)
    local identifier = message.identifier
    if identifier then
      client._results [identifier] = message
      Scheduler.wakeup (client._waiting [identifier])
    end
  end
  client._ws.onerror    = function (_, err)
    client._status = "closed"
    client._error  = err
    Scheduler.wakeup (client._co)
  end
  if not _G.js then
    client._ws:on_open    (client._ws.onopen   )
    client._ws:on_close   (client._ws.onclose  )
    client._ws:on_message (client._ws.onmessage)
    client._ws:on_error   (client._ws.onerror  )
  end
  if _G.js then
    client._co = coroutine.running ()
    Scheduler.sleep (-math.huge)
  else
    threadof (function ()
      client._status = "closed"
      client._ws:connect (url, "cosy")
      client._co = coroutine.running ()
      Scheduler.sleep (-math.huge)
    end)
  end
  if  client._status == "opened"
  and data.username and data.username ~= ""
  and data.password and data.password ~= "" then
    client.user.authenticate {}
  end
end

local mcoroutine = Coromake ()

Client.methods = {}

Client.methods ["user:create"] = function (operation, parameters)
  local client        = operation._client
  local data          = client._data
  parameters.password = Digest (parameters.password)
  local result = mcoroutine.yield ()
  if result.success then
    data.username = parameters.username
    data.hashed   = parameters.password
    data.token    = result.response.token
  end
  local position, status = Loader.loadhttp "http://www.telize.com/geoip"
  if status == 200 then
    client.user.update {
      token    = data.token,
      position = Json.decode (position),
    }
  end
end

Client.methods ["user:authenticate"] = function (operation, parameters)
  local client        = operation._client
  local data          = client._data
  parameters.username = parameters.username or data.username
  if parameters.password then
    parameters.password = Digest (parameters.password)
  elseif data.hashed then
    parameters.password = data.hashed
  end
  local result = mcoroutine.yield ()
  if result.success then
    data.username = parameters.username
    data.hashed   = parameters.password
    data.token    = result.response.token
  end
end

Client.methods ["user:update"] = function (operation, parameters)
  local client        = operation._client
  local data          = client._data
  if parameters.password then
    parameters.password = Digest (parameters.password)
  end
  local result = mcoroutine.yield ()
  if result.success and parameters.username then
    data.username = parameters.username
    data.token    = nil
  end
  if result.success and parameters.password then
    data.hashed = parameters.password
  end
end

function Client.__index (client, key)
  return setmetatable ({
    _client = client,
    _keys   = { key },
  }, Operation)
end

function Operation.__index (operation, key)
  local unpack = table.unpack or unpack
  return setmetatable ({
    _client = operation._client,
    _keys = { unpack (operation._keys), key },
  }, Operation)
end

function Operation.__call (operation, parameters, try_only)
  -- Automatic reconnect:
  local client = operation._client
  local data   = client._data
  if client._status ~= "opened" then
    Client.connect (client)
  end
  if client._status ~= "opened" then
    return nil, {
      _ = i18n ["server:unreachable"],
    }
  end
  -- Call special cases:
  local operator = table.concat (operation._keys, ":")
  local wrapper  = Client.methods [operator]
  local wrapperco
  -- Call:
  local result
  local function f ()
    local co         = coroutine.running ()
    local identifier = #client._waiting + 1
    client._waiting [identifier] = co
    client._results [identifier] = nil
    client._ws:send (Value.expression {
      identifier = identifier,
      operation  = operator,
      parameters = parameters,
      try_only   = try_only,
    })
    Scheduler.sleep (Configuration.library.timeout._)
    result = client._results [identifier]
    client._waiting [identifier] = nil
    client._results [identifier] = nil
  end
  -- First try:
  if data.token and not parameters.token then
    parameters.token = data.token
  end
  if wrapper then
    wrapperco = mcoroutine.create (wrapper)
    mcoroutine.resume (wrapperco, operation, parameters, try_only)
  end
  threadof (f)
  if result == nil then
    return nil, {
      _ = i18n ["server:timeout"],
    }
  end
  if wrapperco and not try_only then
    mcoroutine.resume (wrapperco, result)
  end
  if result.success then
    return result.response or true
  end
  if  result.error
  and result.error._ == "check:error"
  and #result.error.reasons == 1
  and result.error.reasons [1].key == "token"
  and data.username
  and data.hashed
  then
    local r = client.user.authenticate {}
    if not r then
      return nil, result.error
    end
  else
    return nil, result.error
  end
  -- Retry:
  if data.token and not parameters.token then
    parameters.token = data.token
  end
  if wrapper then
    wrapperco = mcoroutine.create (wrapper)
    mcoroutine.resume (wrapperco, operation, parameters, try_only)
  end
  threadof (f)
  if result == nil then
    return nil, {
      _ = i18n ["server:timeout"],
    }
  end
  if wrapperco and not try_only then
    mcoroutine.resume (wrapperco, result)
  end
  if result.success then
    return result.response or true
  else
    return nil, result.error
  end
end

function Library.client (t)
  local client = setmetatable ({
    _status  = false,
    _error   = false,
    _ws      = false,
    _results = {},
    _waiting = {},
    _data    = {},
  }, Client)
  client._data.host     = t.host     or false
  client._data.port     = t.port     or 80
  client._data.username = t.username or false
  client._data.password = t.password or false
  client._data.hashed   = false
  client._data.token    = false
  Client.connect (client)
  if client._status == "opened" then
    return client
  elseif client._status == "closed" then
    return nil, client._error
  else
    assert (false)
  end
end

if _G.js then
  function Library.connect (url)
    local parser   = _G.window.document:createElement "a";
    parser.href    = url;
    return Library.client {
      host     = parser.hostname,
      port     = parser.port,
      username = parser.username,
      password = parser.password,
    }
  end
else
  local Url = require "socket.url"
  function Library.connect (url)
    local parsed = Url.parse (url)
    return Library.client {
      host     = parsed.host,
      port     = parsed.port,
      username = parsed.user,
      password = parsed.password,
    }
  end
end

return Library
