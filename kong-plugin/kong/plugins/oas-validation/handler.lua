-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers               = require "kong.plugins.oas-validation.validation_utils"
local xml_utils             = require "kong.plugins.oas-validation.xml_utils"
local xml_validator         = require "kong.plugins.oas-validation.xml_validator"

local load_method_spec      = helpers.spec_path
local get_method_spec       = helpers.get_method_spec
local locate_request_body   = helpers.locate_request_body
local content_type_allowed  = helpers.content_type_allowed
local is_body_method        = helpers.is_body_method
local param_array_helper    = helpers.param_array_helper
local parameter_check       = helpers.parameter_check
local merge_params          = helpers.merge_params
local cjson                 = require("cjson.safe").new()
local generator             = require("kong.plugins.oas-validation.draft4").generate
local pl_tablex             = require "pl.tablex"
local pl_stringx            = require "pl.stringx"
local match                 = string.match
local ngx                   = ngx
local kong                  = kong
local deserialize           = require "resty.openapi3.deserializer"
local ngx_req_read_body     = ngx.req.read_body
local ngx_req_get_body_data = ngx.req.get_body_data
local ipairs                = ipairs
local EMPTY                 = pl_tablex.readonly({})
local find                  = pl_tablex.find
local replace               = pl_stringx.replace
local json_decode           = cjson.decode
local json_encode           = cjson.encode
local xml_decode            = xml_utils.decode
local xml_validate          = xml_validator.validate
local split                 = require("pl.utils").split
local normalize             = require("kong.tools.uri").normalize
-- local event_hooks           = require "kong.enterprise_edition.event_hooks"

cjson.decode_array_with_array_mt(true)

local DENY_REQUEST_MESSAGE = "request doesn't conform to schema"
local DENY_PARAM_MESSAGE = "request param doesn't conform to schema"
local DENY_RESPONSE_MESSAGE = "response doesn't conform to schema"

local OPEN_API = "openapi"

local OASValidationPlugin = {
  VERSION  = "0.1.0",
  -- priority after security & rate limiting plugins
  PRIORITY = 850,
}

local function get_req_body(content_type, res_schema)
  ngx_req_read_body()

  local body_data = ngx_req_get_body_data()

  if not body_data then
    --no raw body, check temp body
    local body_file = ngx.req.get_body_file()
    if body_file then
      local file = io.open(body_file, "r")
      body_data       = file:read("*all")
      file:close()
    end
  end

  if not body_data or #body_data == 0 then
    return nil
  end

  local body, err

  if content_type == 'application/json' then
    -- try to decode body data as json
    body, err = json_decode(body_data)
    if err then
      return nil, "request body is not valid JSON"
    end
  elseif content_type == 'application/xml' or content_type == 'text/xml' then
    if res_schema.xml ~= nil and res_schema.xml.xsd ~= nil then
      return body_data
    end
    
    body, err = xml_decode(body_data, res_schema)
    if err then
      return nil, "request body is not valid XML"
    end
  end

  kong.log.err('request body: ', xml_utils.print_table(body), " ", content_type)

  return body
end

-- meta table for the sandbox, exposing lazily loaded values
local template_environment
local __meta_environment = {
  __index = function(self, key)
    local lazy_loaders = {
      header = function(self)
        return kong.request.get_headers() or EMPTY
      end,
      query = function(self)
        return kong.request.get_query() or EMPTY
      end,
      path = function(self)
        return split(string.sub(normalize(kong.request.get_path(),true), 2),"/") or EMPTY
      end
    }
    local loader = lazy_loaders[key]
    if not loader then
      -- we don't have a loader, so just return nothing
      return
    end
    -- set the result on the table to not load again
    local value = loader()
    rawset(self, key, value)
    return value
  end,
  __new_index = function(self)
    error("This environment is read-only.")
  end,
}

template_environment = setmetatable({
}, __meta_environment)

local function clear_environment()
  rawset(template_environment, "header", nil)
  rawset(template_environment, "query", nil)
  rawset(template_environment, "path", nil)
end

local validator_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, parameter)
      -- it was not found, so here we generate it
      local validator_func = assert(generator(json_encode(parameter.schema)))
      self[parameter] = validator_func
    return validator_func
  end
})

local validator_param_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, parameter)
    -- it was not found, so here we generate it
    local validator_func = assert(generator(json_encode(parameter.schema), {
      coercion = true,
    }))
    parameter.decoded_schema = assert(parameter.schema)
    self[parameter] = validator_func
    return validator_func
  end
})

local function validate_style_deepobject(location, parameter)

  local validator = validator_param_cache[parameter]
  local result, err =  deserialize(parameter.style, parameter.decoded_schema.type,
          parameter.explode, parameter.name, template_environment[location])
  if err == "not found" and not parameter.required then
    return true
  end

  if err or not result then
    return false
  end

  -- temporary, deserializer should return correct table
  if parameter.decoded_schema.type == "array" and type(result) == "table" then
    setmetatable(result, cjson.array_mt)
  end

  return validator(result)
end

local function validate_data(parameter, spec_ver)

  local location = parameter["in"]

  if location == "query" and parameter.style == "deepObject" then
    return validate_style_deepobject(location, parameter)
  end

  -- if optional and not in request ignore
  if not parameter.required and parameter.value == nil then
    return true
  end

  if parameter.schema and parameter["in"] == "body" then
    local validator = validator_cache[parameter]
    -- try to validate body against schema
    local ok, err = validator(parameter.value)
    if not ok then
      return false, err
    end
    return true
  elseif parameter.schema and parameter.style then
    local validator = validator_param_cache[parameter]
    local result, err =  deserialize(parameter.style or "simple", parameter.decoded_schema.type,
        parameter.explode, parameter.name, parameter.value)
    if err or not result then
      return false, err
    end
    if parameter.decoded_schema.type == "array" and type(result) == "table" then
      setmetatable(result, cjson.array_mt)
    end
    local ok, err = validator(result)
    if not ok then
      return false, err
    end
    return true
  elseif parameter.schema then
    if parameter.type == "array" and type(parameter.value) == "string" then
      parameter.value = {parameter.value}
    end
    if parameter.type == "array" and type(parameter.value) == "table" then
      setmetatable(parameter.value, cjson.array_mt)
    end
    local validator = validator_param_cache[parameter]
    local ok, err = validator(parameter.value)
    if not ok then
      return false, err
    end
    return true
  elseif spec_ver ~= OPEN_API then
    -- validate swagger v2 parameters
    local schema = {}
    schema.type = parameter.type
    if parameter.enum then schema.enum = parameter.enum end
    if parameter.items then schema.items = parameter.items end
    if parameter.pattern then schema.pattern = parameter.pattern end
    if parameter.format then schema.format = parameter.format end
    if parameter.minItems then schema.minItems = parameter.minItems end
    if parameter.maxItems then schema.maxItems = parameter.maxItems end
    -- check if value is string for type array
    if parameter.type == "array" and type(parameter.value) == "string" and parameter.collectionFormat then
        parameter.value = param_array_helper(parameter)
    end
    if parameter.type == "array" and type(parameter.value) == "table" then
      setmetatable(parameter.value, cjson.array_mt)
    end
    parameter.schema = schema
    local validator = validator_param_cache[parameter]
    local ok, err = validator(parameter.value)
    if not ok then
      return false, err
    end
    -- validate v2 param info not supported by ljsonschema
    local ok, err = helpers.parameter_validator_v2(parameter)
    if not ok then
      return false, err
    end
    return true
  end
end

local function validate_required(parameter, path_spec, content_type, res_schema)

  local location = parameter["in"]
  parameter_check(parameter)

  -- now retrieve parameter value from request
  local value
  if location == "body" then
    value = get_req_body(content_type, res_schema) or EMPTY
  elseif location == "path" then
    -- find location of parameter in the specification
    local uri_params = split(string.sub(path_spec,2),"/")
    for idx, name in ipairs(uri_params) do
      if match(name, parameter.name) then
        value = template_environment[location][idx]
        break
      end
    end
  else
    value = template_environment[location][parameter.name]
  end

  -- check required fields
  if parameter.required and value == nil and not parameter.allowEmptyValue then
    return false, "required parameter value not found in request"
  end

  parameter.value = value
  return true
end

local function validate_parameters(parameter, path, spec_ver, content_type, res_schema)

  local ok, err = validate_required(parameter, path, content_type, res_schema)
  if not ok then
    return false, err
  end

  local ok, err = validate_data(parameter, spec_ver)
  if not ok then
    return false, err
  end

  return true
end

-- check parameter locations for 
local function check_parameters(spec_params, location, allowed)
  for qname, _ in pairs(template_environment[location]) do
    local exists = false
    for _, parameter in pairs(spec_params) do
      if parameter["in"] == location then
        if qname:lower() == parameter.name:lower() then
          exists = true
        end
      end
    end
    if not exists then
      if allowed and find(split(allowed:lower(), ","), qname:lower()) then
        exists = true
      end
    end
    if not exists then
      return false, string.format("%s parameter '%s' does not exist in specification", location, qname)
    end
  end
  return true
end

local function get_resp_schema(spec_ver, method_spec, content_type)
  local schema
  if not method_spec then
    return nil
  end
  if spec_ver ~= OPEN_API then
    if method_spec.responses["200"] then
      schema = method_spec.responses["200"].schema
    elseif method_spec.responses.default then
      schema = method_spec.responses.default
    end
  else
    if method_spec.responses["200"] then
      if method_spec.responses["200"].content then
        if method_spec.responses["200"].content[content_type] then
          schema = method_spec.responses["200"].content[content_type].schema
		    else
          local wildcard_sub_type =  helpers.toWildcardSubtype(content_type)
          if method_spec.responses["200"].content[wildcard_sub_type] then
            schema = method_spec.responses["200"].content[wildcard_sub_type].schema
          elseif method_spec.responses["200"].content["*/*"] then
            schema = method_spec.responses["200"].content["*/*"].schema
		      end
        end
      end
    end
  end
  return schema
end

function OASValidationPlugin:init_worker()

  -- register validation event hook 
  -- event_hooks.publish("oas-validation", "validation-failed", {
  --   fields = { "consumer", "ip", "service", "err" },
  --   unique = { "consumer", "ip", "service" },
  --   description = "Run an event when oas validation fails",
  -- })

end

local function emit_event_hook(errmsg)

  -- event_hooks.emit("oas-validation", "validation-failed", {
  --   consumer = kong.client.get_consumer() or {},
  --   ip = kong.client.get_forwarded_ip(),
  --   service = kong.router.get_service() or {},
  --   err = errmsg,
  -- })

end

function OASValidationPlugin:response(conf)
  -- Validate response if enabled in plugin config and if status http is 200
  if conf.validate_response_body then
    if kong.response.get_source() ~= "service" and kong.service.response.get_status() ~= 200 then
      return
    end

    local body = kong.service.response.get_raw_body()
    local req_headers = kong.service.response.get_headers()
    local content_type = req_headers["content-type"]
    if not content_type then
      content_type = "application/json"
    else
      -- remove parameter in content type
      local i = string.find(content_type, ";")
	    if i  then
	      content_type = string.sub(content_type, 1, i-1)
	    end
    end

    -- used ngx.ctx instead of kong.ctx since kong.ctx used in response phase is not thread safe
    local method_spec = get_method_spec(conf, ngx.ctx.resp_uri, ngx.ctx.resp_method)
    local parameter = {schema = get_resp_schema(conf.parsed_spec.swagger or OPEN_API, method_spec, content_type)}

    if parameter.schema then
      local validator = validator_cache[parameter]
      local resp_obj, err

      if content_type == 'application/json' then
        -- try to decode body data as json
        resp_obj, err = json_decode(body)
        if err then
          return kong.response.exit(406, {
            message = "response body is not valid JSON",
          })
        end
      elseif (parameter.schema.xml == nil or  parameter.schema.xml.xsd == nil)
          and (content_type == 'application/xml' or content_type == 'text/xml') then
        resp_obj, err = xml_decode(body, parameter.schema)
        if err then
          return kong.response.exit(406, {
            message = "response body is not valid XML",
          })
        end
      end

      --check response type
      if parameter.type == "array" and type(resp_obj) == "string" then
        resp_obj = {resp_obj}
      end
      if parameter.type == "array" and type(resp_obj) == "table" then
        setmetatable(resp_obj, cjson.array_mt)
      end

      local ok, err
      if parameter.schema.xml ~= nil and parameter.schema.xml.xsd ~= nil then
        kong.log.err('conf xsd_specs: ', xml_utils.print_table(conf.parsed_xsd_specs), parameter.schema.xml.xsd)

        ok, err = xml_validate(body, conf.parsed_xsd_specs[parameter.schema.xml.xsd])
      else
        local ok, err = validator(resp_obj)
      end

      if not ok then
        local errmsg = string.format("response body validation failed with error: %s", replace(err, "userdata", "null"))
        kong.log.err(errmsg)
        -- emit event hook for validation failure
        emit_event_hook(errmsg)
        if conf.notify_only_response_body_validation_failure then
          return
        else
          if not conf.verbose_response then
            errmsg = DENY_RESPONSE_MESSAGE
          end
          return kong.response.exit(406, {
            message = errmsg,
          })
        end
      end
    else
      local errmsg = "no response schema defined in api specification"
      kong.log.notice(errmsg)
      -- emit event hook for validation failure
      emit_event_hook(errmsg)
      return
    end
  else
    return
  end
end

function OASValidationPlugin:access(conf)

  clear_environment()

  if conf.validate_response_body then
    -- used ngx.ctx instead of kong.ctx since kong.ctx used in response phase is not thread safe
    ngx.ctx.resp_uri = normalize(kong.request.get_path(), true)
    ngx.ctx.resp_method = kong.request.get_method()
  end

  local content_type = kong.request.get_header("content-type")
  if not content_type then
    content_type = "application/json"
  else
    -- remove parameter in content type
    local i = string.find(content_type, ";")
    if i  then
      content_type = string.sub(content_type, 1, i-1)
    end
  end

  local method_spec, path_spec, path_params, err = load_method_spec(conf)
  if not method_spec then
    local errmsg = string.format("validation failed, %s", err)
    kong.log.err(errmsg)
    -- emit event hook for validation failure
    emit_event_hook(errmsg)
    if conf.notify_only_request_validation_failure then
      return
    else
      if conf.verbose_response then
        return kong.response.exit(400, { message = errmsg})
      end
      return kong.response.exit(400, { message = DENY_REQUEST_MESSAGE })
    end
  end

  local method = kong.request.get_method()

  -- check content-type matches the spec
  local ok, err = content_type_allowed(content_type, method, method_spec)
  if not ok then
    local errmsg = string.format("validation failed: %s", err)
    kong.log.err(errmsg)
    -- emit event hook for validation failure
    emit_event_hook(errmsg)
    if conf.notify_only_request_validation_failure then
      return
    else
      if conf.verbose_response then
        return kong.response.exit(400, { message = errmsg})
      end
      return kong.response.exit(400, { message = DENY_REQUEST_MESSAGE })
    end
  end

  --merge path and method level parameters
  --method level parameters take precedence over path
  local merged_params
  if path_params then
    if conf.parsed_spec.swagger then
      merged_params = merge_params(path_params, method_spec.parameters, "location")
    else
      merged_params = merge_params(path_params, method_spec.parameters, "in")
    end
  else
    merged_params = method_spec.parameters
  end

  if conf.header_parameter_check then
    local ok, err = check_parameters(merged_params or EMPTY, "header", conf.allowed_header_parameters)
    if not ok then
      local errmsg = string.format("validation failed with error: %s", err)
      kong.log.err(errmsg)
      -- emit event hook for validation failure
      emit_event_hook(errmsg)
      if conf.notify_only_request_validation_failure then
        return
      else
        if conf.verbose_response then
          return kong.response.exit(400, { message = errmsg})
        end
        return kong.response.exit(400, { message = DENY_PARAM_MESSAGE })
      end
    end
  end

  local res_schema = locate_request_body(method_spec, content_type)

  -- check if query & headers in request exist in spec
  if conf.query_parameter_check then
    local ok, err = check_parameters(merged_params or EMPTY, "query")
    if not ok then
      local errmsg = string.format("validation failed with error: %s", err)
      kong.log.err(errmsg)
      -- emit event hook for validation failure
      emit_event_hook(errmsg)
      if conf.notify_only_request_validation_failure then
        return
      else
        if conf.verbose_response then
          return kong.response.exit(400, { message = errmsg})
        end
        return kong.response.exit(400, { message = DENY_PARAM_MESSAGE })
      end
    end
  end

  for _, parameter in ipairs(merged_params or EMPTY) do
    if not conf.validate_request_header_params and parameter["in"] == "header" then
      goto continue
    end
    if not conf.validate_request_query_params and parameter["in"] == "query" then
      goto continue
    end
    if not conf.validate_request_uri_params and parameter["in"] == "path" then
      goto continue
    end
    if not conf.validate_request_body and parameter["in"] == "body" and conf.parsed_spec.swagger then
      goto continue
    end

    local ok, err = validate_parameters(parameter, path_spec, conf.parsed_spec.swagger or OPEN_API, content_type, res_schema)
    if not ok then
      -- check for userdata cjson.null and return nicer err message
      local errmsg = string.format("%s '%s' validation failed with error: '%s'", parameter["in"],
                                      parameter.name, replace(err, "userdata", "null"))
      kong.log.err(errmsg)
      -- emit event hook for validation failure
      emit_event_hook(errmsg)
      if conf.notify_only_request_validation_failure then
        return
      else
        if err and conf.verbose_response then
          return kong.response.exit(400, { message = errmsg})
        end
        return kong.response.exit(400, { message = DENY_PARAM_MESSAGE })
      end
    end

    ::continue::

  end

  -- validate oas body if required
  if conf.validate_request_body and conf.parsed_spec.openapi and is_body_method(method) then
    if not res_schema then
      local errmsg = "request body schema not found in api specification"
      kong.log.err(errmsg)
      -- emit event hook for validation failure
      emit_event_hook(errmsg)
      if conf.notify_only_request_validation_failure then
        return
      else
        if conf.verbose_response then
          return kong.response.exit(400, { message = errmsg})
        end
        return kong.response.exit(400, { message = DENY_PARAM_MESSAGE })
      end
    end
    local parameter = {
      schema = res_schema
    }
    local validator = validator_cache[parameter]
    -- validate request body against schema
    local body = get_req_body(content_type, res_schema) or EMPTY
    local ok, err

    if res_schema.xml ~= nil and res_schema.xml.xsd ~= nil then
      kong.log.err('conf xsd_specs: ', conf.parsed_xsd_specs[res_schema.xml.xsd])
      ok, err = xml_validate(body, conf.parsed_xsd_specs[res_schema.xml.xsd])
    else
      ok, err = validator(body)
    end

    if not ok then
      -- check for userdata cjson.null and return nicer err message
      local errmsg = string.format("request body validation failed with error: '%s'", replace(err, "userdata", "null"))
      kong.log.err(errmsg)
      -- emit event hook for validation failure
      emit_event_hook(errmsg)
      if conf.notify_only_request_validation_failure then
        return
      else
        if err and conf.verbose_response then
          return kong.response.exit(400, { message = errmsg})
        end
        return kong.response.exit(400, { message = DENY_PARAM_MESSAGE })
      end
    end
  end
end

return OASValidationPlugin

