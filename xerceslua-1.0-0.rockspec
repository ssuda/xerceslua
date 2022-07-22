package = "xerceslua"
version = "1.0-0"
source = {
   url = "git://github.com/ssuda/xerceslua",
   tag = "v1.0",
}
description = {
   summary = "A minimal lua wrapper of Xerces-C++ in order to be able to validate xml files.",
   detailed = [[
      A minimal lua wrapper of Xerces-C++ in order to be able to validate xml files.
   ]],
   license = "MIT"
}
dependencies = {
   "lua >= 5.1, < 5.4"
}
external_dependencies = {
   LIBXERCES = {
      header = "xercesc/parsers/XercesDOMParser.hpp"
   }
}
build = {
    type = "builtin",
    modules = {
       xerceslua = {
          sources = {"src/xerceslua.cpp", "src/xerceslua_lib.cpp"},
          libraries = {"xerces-c"},
          incdirs = {"$(LIBXERCES_INCDIR)", "./deps/LuaBridge", "./deps"},
          libdirs = {"$(LIBXERCES_LIBDIR)"}
       }
    }
 }