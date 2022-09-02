
local xml2lua = require("xml2lua")
local kong    = kong
local cjson = require("cjson.safe").new()

local xmlhandler = require("xmlhandler.tree")

local _M = {}

-- Returns:
--  0 for objects
--  1 for empty object/table (these two are indistinguishable in Lua)
--  2 for arrays
local function tablekind(t)
    local length = #t
    if length == 0 then
      if next(t) == nil then
        return 1 -- empty table
      else
        return 0 -- pure hash
      end
    end
  
    -- not empty, check if the number of items is the same as the length
    local items = 0
    for k, v in pairs(t) do items = items + 1 end
    if items == #t then
      return 2 -- array
    else
      return 0 -- mixed array/object
    end
  end

---Recursivelly traverses the lua table and schema table simultaneously and transforms according schema 
--@param table  Parent table to be transformed
--@param table_key table key 
--@param table_value table value
--@param schema_key schema key 
--@param schema_value schema object of the schema key

local function xml2oas(table, table_key, table_value, schema_key, schema_value)
    -- rename xml element to schema property
    if table ~= nil and table_key ~= nil and schema_key ~= nil and table_key ~= schema_key then
        table[schema_key] = table_value
        table[table_key] = nil
    end

     -- convert attributes to properties
    if table_value ~= nil and table_value._attr ~= nil then
        for i, p in pairs(table_value._attr) do
            -- ignore xmlns:
            if not p.find('^xmlns') then
                table_value[i] = p
            end
        end
        table_value._attr = nil
    end

    -- kong.log.err(table, schema_value.type, table_key, schema_key, type(table_value))

    if schema_value.type == 'object' then
        for sk, sv in pairs(schema_value.properties) do
            table_key = sk
            if sv.xml ~= nil and sv.xml.name ~= nil then
                table_key = sv.xml.name
            end

            -- kong.log.err(table_key, sk)

            if table_value[table_key] ~= nil or table_value[sk] ~= nil then
                xml2oas(table_value, table_key, table_value[table_key] or table_value[sk], sk, sv)
            end
        end
    elseif schema_value.type == 'array' then
        if schema_value.xml ~= nil and schema_value.xml.wrapped then
            local key, value = next(table_value)
            table_value = value
            table[schema_key] = value
            
            if key ~= schema_key then
                table[key] = nil
            end
        end

        if type(table[schema_key]) ~= "table" or table[schema_key][1] == nil then
            -- kong.log.err('converting to table', table[schema_key][1])
            table[schema_key] = {table[schema_key]}
        end

        setmetatable(table[schema_key], cjson.array_mt)

        if type(table_value) == "table" then
            for k, item in pairs(table_value) do
                xml2oas(item, nil, item, nil, schema_value.items)
            end
        end
    elseif table ~= nil and schema_key ~= nil and schema_value.type ~= type(table_value) then
        if schema_value.type == 'integer' or schema_value.type == 'number' then
            -- kong.log.err('converting to number', schema_key, schema_value.type, table_key, type(table_value))
            table[schema_key] = tonumber(table_value) 
        elseif schema_value.type == 'boolean' then
            -- kong.log.err('converting to boolean', schema_key, schema_value.type, table_key, type(table_value))
            table[schema_key] = string.lower(table_value) == 'true'
        end
    end
end

---Gets the first key of a given table
local function get_first_key_value(tb)
    for k, v in pairs(tb) do
        return k, v
    end
 end

---Recursivelly prints a table in an easy-to-ready format
--@param tb The table to be printed
--@param level the indentation level to start with
local function print_table(tb, level)
    if tb == nil then
       return
    end
    
    local str = ''
    level = level or 1
    local spaces = string.rep(' ', level*2)

    if type(tb) == 'table' then
        if tablekind(tb) == 2 then
            str = str .. spaces .. '{'
            for _, v in ipairs(tb) do
                str = str .. tostring(v) .. ','
            end
            str = str .. '}' 
        else
            for k,v in pairs(tb) do
                if type(v) == "table" then
                str = str .. spaces .. k .. '\n'
                str = str .. print_table(v, level+1) .. '\n'
                else
                str = str .. spaces .. k..'='.. tostring(v) .. ': ' .. type(v) .. '\n'
                end
            end
        end
    end

    return str
  end
  

function _M.decode(xml_string, schema)
    if not schema then
        return nil, "no schema to parse xml"
    end

    kong.log.err(xml_string, print_table(schema))

    local handler = xmlhandler:new()

    --Instantiates the XML parser
    local parser = xml2lua.parser(handler)
    local ok, err = pcall(parser.parse, parser, xml_string)

    if not ok then
        return nil, "failed to parse xml: " .. tostring(err)
    end
    
    local key, value =  get_first_key_value(handler.root)
    kong.log.err('before tansformation ', print_table(value))

    local ok, err = pcall(xml2oas, nil, nil, value, nil, schema)

    if not ok then
        kong.log.err("failed to transform xml: " .. tostring(err))
        return nil, "failed to transform xml: " .. tostring(err)
    end

    kong.log.err('after tansformation ', print_table(value))
    return value
end

_M.print_table = print_table

return _M
