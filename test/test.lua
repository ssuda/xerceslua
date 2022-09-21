
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

<<<<<<< HEAD
local log=parser:parse_string([[<?xml version="1.0" encoding="UTF-8"?>
<libraries xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="sample.xsd">
	<library>
		<name>pugilua</name>
		<url>https://github.com/d-led/pugilua</url>
		<no_such_field />
	</library>
</libraries>]])
print('parse ok: ',log.Ok)
if not log.Ok then
    print('error count: ', log.Count)
    for i=0,log.Count-1 do
        local err=log:GetLogEntry(i)
=======
 log = parser:parse("pain.xml")

print('parse ok: ', log.Ok)

if not log.Ok then
    print('error count: ', log.Count)
    for i = 0,log.Count-1 do
        local err = log:GetLogEntry(i)
>>>>>>> Updating to 1.0.2
        print(err.SystemId
        		..', l:'..err.LineNumber
        		..', c:'..err.ColumnNumber
        		..', e:'..err.Message
		)
    end
end