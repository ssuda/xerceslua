xerceslua
=========

A minimal lua wrapper of Xerces-C++ in order to be able to validate xml files

[![Build Status](https://travis-ci.org/d-led/xerceslua.svg?branch=master)](https://travis-ci.org/d-led/xerceslua)

Usage
-----

````lua
assert(require 'xerceslua')

local parser = xerces.XercesDOMParser()
parser:loadGrammar("sample.xsd",xerces.GrammarType.SchemaGrammarType)
parser:setValidationScheme(xerces.ValSchemes.Val_Always)

local log = parser:parse_string([[<?xml version="1.0" encoding="UTF-8"?>
<libraries xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="sample.xsd">
	<library>
		<name>pugilua</name>
		<url>https://github.com/d-led/pugilua</url>
		<no_such_field />
	</library>
</libraries>]])

print('parse ok: ', log.Ok)
if not log.Ok then
    print('error count: ', log.Count)
    for i = 0,log.Count-1 do
        local err=log:GetLogEntry(i)
        print(err.SystemId
        		..', l:'..err.LineNumber
        		..', c:'..err.ColumnNumber
        		..', e:'..err.Message
		)
    end
end
````

Example
-------

run `test.bat` (or `test.lua`) from the `test` directory.

Dependencies
------------

 * [Xerces-C++](http://xerces.apache.org/xerces-c/) 
````
Ubuntu:
# sudo apt install libxerces-c-dev

Mac OS X:
# brew install xerces-c

Centos:
# dnf install xerces-c-devel
````

* Run sample
````
$ cd test && lua test.lua
````
 

License
-------

This library is distributed under the MIT License:

Copyright (c) 2012-2014 Dmitry Ledentsov

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
