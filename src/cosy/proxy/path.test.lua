local assert = require "luassert"
local path   = require "cosy.proxy.path"
local tags   = require "cosy.util.tags"
local PATH   = tags.PATH

do
  local p = path ({})
  assert.has.error (function () p [PATH] = true end)
end

do
  local data = {}
  local p = path (data)
  assert.are.same (p [PATH], { data })
end

do
  local data = {}
  local p = path (data)
  local q = p.some_key
  assert.are.same (p [PATH], { data })
  assert.are.same (q [PATH], { data, "some_key" })
end

do
  local data = {}
  local p = path (data)
  local NIL = {}
  for _, value in ipairs {
    NIL,
    true,
    0,
    "",
    { "" },
    function () end,
    coroutine.create (function () end),
  } do
    if value == NIL then
      value = nil
    end
    p.some_key = value
    assert.are.same (p [PATH], { data })
    assert.are.same (p.some_key [PATH], { data, "some_key" })
  end
end

do
  local data = {}
  local p = path (data)
  local NIL = {}
  for _, value in ipairs {
    NIL,
    true,
    0,
    "",
    { "" },
    function () end,
    coroutine.create (function () end),
  } do
    if value == NIL then
      value = nil
    end
    local q = p (value)
    assert.are.same (p [PATH], { data })
    assert.are.same (q [PATH], { value })
  end
end
