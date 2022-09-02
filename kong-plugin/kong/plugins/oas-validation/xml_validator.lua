
assert(require 'xerceslua')

local _M = {}

local function  parse_log(log)
	print('parse ok: ', log.Ok)

	local error_msg = ''
	if not log.Ok then
		for i = 0,log.Count-1 do
			local err = log:GetLogEntry(i)
			if error_msg ~= '' then
				error_msg = error_msg .. '\n'
			end

			error_msg = error_msg .. err.Message .. ': Error at lineNumber '.. err.LineNumber
					..' and columnNumber '.. err.ColumnNumber
		end
	end

	return log.Ok, error_msg
end

function _M.parser(schema_str)

	local parser = xerces.XercesDOMParser()
	local log = parser:loadGrammarString(schema_str, xerces.GrammarType.SchemaGrammarType)

	local ok, err_msg = parse_log(log)

	if not ok then
		return nil, err_msg
	end
	
	return parser
end

function _M.validate(xml_str, parser)
	local log = parser:parseString(xml_str)
	return parse_log(log)
end


function _M.validate_from_schema(xml_str, schema_str)
	local parser = _M.parser(schema_str)
	return _M.validate(xml_str, parser)
end

return _M
