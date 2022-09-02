package = "kong-plugin-oas-validation"
version = "0.1.0-0"

supported_platforms = {"linux", "macosx"}
source = {
  url = "",
  tag = "0.1.0"
}

description = {
  summary = "OAS Validation plugin for Kong Enterprise",
}

dependencies = {
  "lua-resty-ljsonschema == 1.1.2",
  "lua-resty-openapi3-deserializer == 2.0.0",
  "xml2lua",
  "xerceslua",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.oas-validation.handler"] = "kong/plugins/oas-validation/handler.lua",
    ["kong.plugins.oas-validation.schema"] = "kong/plugins/oas-validation/schema.lua",
    ["kong.plugins.oas-validation.validation_utils"] = "kong/plugins/oas-validation/validation_utils.lua",

    -- Validator files for version: "draft4" (JSONschema draft 4)
    ["kong.plugins.oas-validation.draft4.init"] = "kong/plugins/oas-validation/draft4/init.lua",
  }
}
