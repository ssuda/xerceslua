-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local deepcopy      = require("pl.tablex").deepcopy
local split         = require("pl.utils").split
local lyaml         = require "lyaml"
local ngx           = ngx
local re_match      = ngx.re.match
local cjson         = require("cjson.safe").new()
local json_decode   = cjson.decode
local yaml_load     = lyaml.load
local kong          = kong
local gsub          = string.gsub
local match         = string.match
local normalize     = require("kong.tools.uri").normalize
local load_xsd      = require "kong.plugins.oas-validation.xml_validator".parser

local _M = {}

local CONTENT_METHODS = {
  "POST", "PUT", "PATCH"
}

local function walk_tree(path, tree)
    assert(type(path) == "string", "path must be a string")
    assert(type(tree) == "table", "tree must be a table")

    local segments = split(path, "%/")
    if path == "/" then
      -- top level reference, to full document
      return tree

    elseif segments[1] == "" then
      -- starts with a '/', so remove first empty segment
      table.remove(segments, 1)

    else
      -- first segment is not empty, so we had a relative path
      return nil, "only absolute references are supported, not " .. path
    end

    local position = tree
    for i = 1, #segments do
      position = position[segments[i]]
      if position == nil then
        return nil, "not found"
      end
      if i < #segments and type(position) ~= "table" then
        return nil, "next level cannot be dereferenced, expected table, got " .. type(position)
      end
    end
    return position
  end -- walk_tree

local function get_dereferenced_schema(full_spec)
    -- deref schema in-place
    local function dereference_single_level(schema, count_1)
      count_1 = (count_1 or 0) + 1
      if count_1 > 1000 then
          return nil, "recursion detected in schema dereferencing"
      end

      for key, value in pairs(schema) do
      local count_2 = 0
      while type(value) == "table" and value["$ref"] do
          count_2 = count_2 +1
          if count_2 > 1000 then
              return nil, "recursion detected in schema dereferencing"
          end

          local reference = value["$ref"]
          local file, path = reference:match("^(.-)#(.-)$")
          if not file then
              return nil, "bad reference: " .. reference
          elseif file ~= "" then
              return nil, "only local references are supported, not " .. reference
          end

          local ref_target, err = walk_tree(path, full_spec)
          if not ref_target then
              return nil, "failed dereferencing schema: " .. err
          end
          value = deepcopy(ref_target)
          schema[key] = value
      end

      if type(value) == "table" then
          local ok, err = dereference_single_level(value, count_1)
          if not ok then
              return nil, err
          end
      end
    end
    return schema
  end

  -- wrap to also deref top level
  local schema = deepcopy(full_spec)
  local wrapped_schema, err = dereference_single_level( { schema } )
  if not wrapped_schema then
      return nil, err
  end

  return wrapped_schema[1]
end

local function find_param(params, name, locin)
  for pi, pv in pairs(params) do
    if pv[name] == name and pv[locin] == locin then
      return true, pi
    end
  end
  return false
end

--merge path and method parameters
function _M.merge_params(p_params, m_params, locin)
  local merged_params = {}
  for pi, pv in pairs(p_params) do
    local res, idx = find_param(m_params, pv["name"], pv[locin])
    if res then
      --replace
      table.insert(merged_params, m_params[idx])
    else
      table.insert(merged_params, pv)
    end
  end

  --add other method parameters
  for pi, pv in pairs(m_params) do
    local res = find_param(merged_params, pv["name"], pv[locin])
    if not res then
      table.insert(merged_params, pv)
    end
  end

  return merged_params

end

function _M.find_key(path, tree)
  assert(type(path) == "string", "path must be a string")
  assert(type(tree) == "table", "tree must be a table")

  for lk, lv in pairs(tree) do
    if lk == path then return lv end
    if type(lv) == "table" then
      for dk, dv in pairs(lv) do
        if dk == path then return dk end
        if type(dv) == "table" then
          for ek, ev in pairs(dv) do
            if ek == path then return ev end
          end
        end
      end
    end
  end
  return nil
end

-- Loads an api specification string
-- Tries to first read it as json, and if failed as yaml
local function load_spec(spec_str)

  -- yaml specs need to be url encoded, otherwise parsing fails
  spec_str = ngx.unescape_uri(spec_str)

  -- first try to parse as JSON
  local result, cjson_err = json_decode(spec_str)
  if type(result) ~= "table" then
    -- if fail, try as YAML
    local ok
    ok, result = pcall(yaml_load, spec_str)
    if not ok or type(result) ~= "table" then
      return nil, ("api specification is neither valid json ('%s') nor valid yaml ('%s')"):
                  format(tostring(cjson_err), tostring(result))
    end
  end

--[[   if not result.openapi or not result.swagger then
    return nil, "no api specification version swagger or openapi found"
  end ]]

  -- build de-referenced specification
  local deref_schema, err = get_dereferenced_schema(result)
  if err then
    return nil, err
  end
  -- sort paths for later path matching
  local sorted_paths = {}
  if not deref_schema.paths then
    return nil, "no paths defined in specification"
  end
  for n in pairs(deref_schema.paths) do table.insert(sorted_paths, n) end
  table.sort(sorted_paths)
  deref_schema.sorted_paths = sorted_paths

  return deref_schema

end

function _M.valid_spec(spec_str)
  local _, err = load_spec(spec_str)
  if err then
    return false, err
  end
  return true
end

local function exists (tab, val)
  for _, value in pairs(tab) do
      if value:lower() == val:lower() then
          return true
      end
  end
  return false
end

local function retrieve_method_path(path, method)
  if method == "GET" then return path.get
  elseif method == "POST" then return path.post
  elseif method == "PUT" then return path.put
  elseif method == "PATCH" then return path.patch
  elseif method == "DELETE" then return path.delete
  elseif method == "OPTIONS" then return path.options
  elseif method == "HEAD" then return path.head
  elseif method == "TRACE" then return path.trace
  end

  return nil
end

function _M.content_type_allowed(content_type, method, method_spec, conf)
  if content_type ~= "application/json" and content_type ~= "application/xml" and content_type ~= "text/xml" then
    return false, "content-type '" .. content_type .. "' is not supported"
  end
  if exists(CONTENT_METHODS, method) then
    if method_spec.consumes then
      local content_types = method_spec.consumes
      if type(content_types) ~= "table" then
        content_types = {content_types}
      end
      if not exists(content_types, content_type) then
        return false, string.format("content type '%s' does not exist in specification", content_type)
      end
    end

  end
  return true
end

function _M.param_array_helper(parameter)

  local FORMATS = {
    csv = {
      seperator = ",",
    },
    ssv = {
      seperator = " ",
    },
    tsv = {
      seperator = "\\",
    },
    pipes = {
      seperator = "|",
    },
  }

  local format = parameter.collectionFormat or nil
  if not format then
    return nil
  end

  if format == "multi" and type(parameter.value) == "string" then
    return {parameter.value}
  end

  return split(parameter.value, FORMATS[format].seperator, true)

end

local function get_method_spec(conf, uri_path, method)
  local paths = conf.parsed_spec.paths
  local method_path

  for _, path in ipairs(conf.parsed_spec.sorted_paths) do
    local formatted_path = gsub(path, "[-.]", "%%%1")
    formatted_path = gsub(formatted_path, "{(.-)}", "[A-Za-z0-9]+") .. "$"
    local matched_path = match(uri_path, formatted_path)
    if matched_path then
      method_path = retrieve_method_path(paths[path], method)
      if method_path then
        return method_path, path, paths[path].parameters or nil
      end
    end
  end

  return nil, nil, nil, "path not found in api specification"
end

function _M.spec_path(conf)
  -- Get resource information
  local uri_path = normalize(kong.request.get_path(), true)
  local method = kong.request.get_method()

  -- store parsed spec
  local err
  if conf.api_spec and not conf.parsed_spec then
    conf.parsed_spec, err = load_spec(conf.api_spec)
    if not conf.parsed_spec then
      return false, false, false, string.format("Unable to parse the api specification: %s", err)
    end
  end

  -- store parsed xsd spec
  if conf.xsd_specs and not conf.parsed_xsd_specs then
    conf.parsed_xsd_specs = {}
    for i, v in ipairs(conf.xsd_specs) do
      local parser, err = load_xsd(v.schema)
      if not parser then
        return false, false, false, string.format("Unable to parse the xsd specification: %s", err)
      end
      conf.parsed_xsd_specs[v.name] = parser
    end
  end

  return get_method_spec(conf, uri_path, method)

end

function _M.get_method_spec(conf, path, method)
  return get_method_spec(conf, path, method)
end

function _M.toWildcardSubtype(content_type)
  -- remove parameter in content type
  local i = string.find(content_type, "/")
  if i then
    return string.sub(content_type, 1, i-1) .. "/*"
  end
  return content_type
end

function _M.locate_request_body(method_spec, type)
  if method_spec.requestBody and method_spec.requestBody.content then
    if method_spec.requestBody.content[type] and method_spec.requestBody.content[type].schema then
      return method_spec.requestBody.content[type].schema
    else
      local wildcardSubtype =  _M.toWildcardSubtype(type)
      if method_spec.requestBody.content[wildcardSubtype] and method_spec.requestBody.content[wildcardSubtype].schema then
        return method_spec.requestBody.content[wildcardSubtype].schema
      elseif method_spec.requestBody.content["*/*"] and method_spec.requestBody.content["*/*"].schema then
        return method_spec.requestBody.content["*/*"].schema
      else
        return false, string.format("no request body schema found for content-type '%s'", type)
      end
    end
  end
end

function _M.parameter_validator_v2(parameter)
  if parameter.type then
    if parameter.type == "string" then
      if parameter.format then
        if parameter.format == "email" then
          if not re_match(parameter.value, "[a-zA-Z][\\w\\_]{6,15})\\@([a-zA-Z0-9.-]+)\\.([a-zA-Z]{2,4}") then
            return false, "parameter value is not a valid email address"
          end
        elseif parameter.format == "uuid" then
          if not re_match(parameter.value, "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") then
            return false, "parameter value does not match UUID format"
          end
        end
      end
    end
  end

  return true

end

function _M.is_body_method(method)
  return exists(CONTENT_METHODS, method)
end

function _M.parameter_check(parameter)
  local location = parameter["in"]
  if not location then
    return false, "no parameter.in field exists in specification"
  end
  if not parameter["name"] then
    return false, "no parameter.name field exists in specification"
  end
  if not parameter.required then
    parameter.required = false
  end
  if location == "query" and not parameter.allowEmptyValue then
    parameter.allowEmptyValue = false
  else
    parameter.allowEmptyValue = true
  end
  if parameter.schema and parameter.content then
    return false, "either parameter.schema or parameter.content allowed, not both"
  end
  if not parameter.schema then
    if not parameter.type then
      return false, "no parameter.type exists in specification"
    end
    if parameter.type == "array" and not parameter.items then
      return false, "parameter.items is required if parameter.style is 'array'"
    end
  end

end

return _M