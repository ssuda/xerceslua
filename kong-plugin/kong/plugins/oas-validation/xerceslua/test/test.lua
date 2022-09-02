
assert(require 'xerceslua')

-- local parser = xerces.XercesDOMParser()
-- parser:loadGrammar("sample.xsd",xerces.GrammarType.SchemaGrammarType)
-- parser:setValidationScheme(xerces.ValSchemes.Val_Always)

-- local log = parser:parse("sample.xml")

-- print('parse ok: ',log.Ok)

-- if not log.Ok then
--     print('error count: ', log.Count)
--     for i = 0,log.Count-1 do
--         local err = log:GetLogEntry(i)
--         print(err.SystemId
--         		..', l:'..err.LineNumber
--         		..', c:'..err.ColumnNumber
--         		..', e:'..err.Message
-- 		)
--     end
-- end

local parser = xerces.XercesDOMParser()
local log  = parser:loadGrammar("pain.xsd", xerces.GrammarType.SchemaGrammarType)
-- parser:setValidationScheme(xerces.ValSchemes.Val_Always)
print('parse ok: ', log.Ok)

if not log.Ok then
    print('error count: ', log.Count)
    for i = 0,log.Count-1 do
        local err = log:GetLogEntry(i)
        print(err.SystemId
        		..', l:'..err.LineNumber
        		..', c:'..err.ColumnNumber
        		..', e:'..err.Message
		)
    end
end

 log = parser:parse("pain.xml")

print('parse ok: ', log.Ok)

if not log.Ok then
    print('error count: ', log.Count)
    for i = 0,log.Count-1 do
        local err = log:GetLogEntry(i)
        print(err.SystemId
        		..', l:'..err.LineNumber
        		..', c:'..err.ColumnNumber
        		..', e:'..err.Message
		)
    end
end