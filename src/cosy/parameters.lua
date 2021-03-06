local Configuration = require "cosy.configuration"
local I18n          = require "cosy.i18n"
local Logger        = require "cosy.logger"
local Repository    = require "cosy.repository"

Configuration.load "cosy.parameters"

local i18n   = I18n.load "cosy.parameters"
i18n._locale = Configuration.locale._

local Parameters    = setmetatable ({}, {
  __index = function (_, key)
    return Configuration.data [key]
  end,
})

function Parameters.check (request, parameters)
  request    = request    or {}
  parameters = parameters or {}
  local reasons = {}
  local checked = {}
  for _, field in ipairs { "required", "optional" } do
    for key, parameter in pairs (parameters [field] or {}) do
      local value = request [key]
      if field == "required" and value == nil then
        reasons [#reasons+1] = {
          _   = i18n ["check:not-found"],
          key = key,
        }
      elseif value ~= nil then
        for i = 1, Repository.size (parameter.check) do
          local ok, reason = parameter.check [i]._ {
            parameter = parameter,
            request   = request,
            key       = key,
          }
          checked [key] = true
          if not ok then
            reason.parameter     = key
            reasons [#reasons+1] = reason
            break
          end
        end
      end
    end
  end
  for key in pairs (request) do
    if not checked [key] then
      Logger.warning {
        _   = i18n ["check:no-check"],
        key = key,
      }
    end
  end
  if #reasons ~= 0 then
    error {
      _       = i18n ["check:error"],
      reasons = reasons,
    }
  end
end

return Parameters