-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson.safe").new()
local jsonschema = require "resty.ljsonschema"

cjson.decode_array_with_array_mt(true)

local _M = {}


function _M.generate(schema, options)
  do
    local t, err = cjson.decode(schema)
    if not t then
      return nil, "failed decoding schema: " .. tostring(err)
    end
    schema = t
  end

  local ok, func, err = pcall(jsonschema.generate_validator, schema, options)
  if not ok then
    return nil, "failed to generate schema validator: " .. tostring(func)
  end

  if not func then
    return nil, "failed to generate schema validator: " .. tostring(err)
  end

  return func
end


function _M.validate(schema_conf)
  local schema
  do
    local t, err = cjson.decode(schema_conf)
    if not t then
      return nil, "failed decoding schema: " .. tostring(err)
    end
    schema = t
  end

  local ok, err = jsonschema.jsonschema_validator(schema)
  if not ok then
    return ok, "not a valid JSONschema draft 4 schema: " .. tostring(err)
  end

  local f
  f, err = _M.generate(schema_conf)
  if not f then
    return nil, err
  end

  ok, err = pcall(f, {})  --run it once with an empty object
  if not ok then
    return nil, err
  end

  return true
end

return _M
