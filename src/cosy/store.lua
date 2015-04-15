local Platform      = require "cosy.platform"
local Configuration = require "cosy.configuration"
                      require "cosy.string"

local Store      = {}
local Collection = {}
local Document   = {}

local PATTERN   = setmetatable ({}, { __tostring = function () return "PATTERN" end })
local DATA      = setmetatable ({}, { __tostring = function () return "DATA"    end })
local ROOT      = setmetatable ({}, { __tostring = function () return "ROOT"    end })
local DIRTY     = setmetatable ({}, { __tostring = function () return "DIRTY"   end })

function Store.new ()
  return setmetatable ({}, Store)
end

function Store.__index (store, key)
  local collection = Collection.new (key)
  rawset (store, key, collection)
  return collection
end

function Store.__newindex ()
  assert (false)
end

function Store.commit (store)
  local client = Platform.redis ()
  client:multi ()
  for _, collection in pairs (store) do
    local pattern = collection [PATTERN]
    for key, document in pairs (collection [DATA]) do
      if document [DIRTY] then
        local name  = pattern % {
          key = Platform.value.expression (key),
        }
        local value = document [DATA]
        if value == nil then
          client:del (name)
        else
          client:set (name, Platform.value.encode (value))
          if type (value) == "table" and value.expire_at then
            client:expireat (name, math.ceil (value.expire_at))
          else
            client:persist (name)
          end
        end
      end
    end
  end
  client:exec ()
end

function Collection.new (key)
  local pattern = Configuration.redis.key [key]._
  assert (pattern)
  return setmetatable ({
    [PATTERN] = pattern,
    [DATA   ] = {},
  }, Collection)
end

function Collection.__index (collection, key)
  if not collection [DATA] [key] then
    local name   = collection [PATTERN] % {
      key = Platform.value.expression (key),
    }
    local client = Platform.redis ()
    client:watch (name)
    local value  = client:get (name)
    if value ~= nil then
      value = Platform.value.decode (value)
    end
    collection [DATA] [key] = {
      [DIRTY] = false,
      [DATA ] = value,
    }
  end
  return Document.new (collection [DATA] [key])
end

function Collection.__newindex (collection, key, value)
  collection [DATA] [key] = {
    [DIRTY] = true,
    [DATA ] = value,
  }
end

function Collection.__pairs (collection)
  local coroutine = require "coroutine.make" ()
  return coroutine.wrap (function ()
    local name   = collection [PATTERN] % { key = "*" }
    local client = Platform.redis ()
    local cursor = 0
    repeat
      local t = client:scan (cursor, {
        match = name,
        count = 100,
      })
      cursor = t [1]
      local data = t [2]
      for i = 1, #data do
        local name  = data [i]
        local key   = Platform.value.decode ((collection [PATTERN] / name).key)
        local value = collection [key]
        coroutine.yield (key, value)
      end
    until cursor == "0"
  end)
end

function Collection.__len (collection)
  local i = 0
  repeat
    i = i+1
    local value = collection [i]
  until value == nil
  return i-1
end

function Collection.__ipairs (collection)
  local coroutine = require "coroutine.make" ()
  return coroutine.wrap (function ()
    local i = 0
    repeat
      i = i+1
      local value = collection [i]
      if value == nil then
        return
      end
      coroutine.yield (i, value)
    until true
  end)
end

function Document.new (root)
  local result = root [DATA]
  if type (result) ~= "table" then
    return result
  else
    return setmetatable ({
      [ROOT] = root,
      [DATA] = result,
    }, Document)
  end
end

function Document.__index (document, key)
  local result = document [DATA] [key]
  if type (result) ~= "table" then
    return result
  else
    return setmetatable ({
      [ROOT] = document [ROOT],
      [DATA] = result,
    }, Document)
  end
end

function Document.__newindex (document, key, value)
  document [DATA] [key  ] = value
  document [ROOT] [DIRTY] = true
end

function Document.__pairs (document)
  local coroutine = require "coroutine.make" ()
  return coroutine.wrap (function ()
    for k in pairs (document [DATA]) do
      coroutine.yield (k, document [k])
    end
  end)
end

function Document.__ipairs (document)
  local coroutine = require "coroutine.make" ()
  return coroutine.wrap (function ()
    for i = 1, #document do
      coroutine.yield (i, document [i])
    end
  end)
end

function Document.__len (document)
  return # document [DATA]
end
