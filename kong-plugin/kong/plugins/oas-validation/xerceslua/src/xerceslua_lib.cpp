#include "xerceslua_lib.h"

#include <lua.hpp>
#include <LuaBridge.h>
#include <RefCountedPtr.h>

#include <iostream>
#include <sstream>
#include <vector>

#ifdef _MSC_VER
#include <xercesc/util/Xerces_autoconf_config.msvc.hpp>
#endif

#include <xercesc/parsers/XercesDOMParser.hpp>
#include <xercesc/sax/HandlerBase.hpp>
#include <xercesc/framework/MemBufInputSource.hpp>
#include <xercesc/framework/Wrapper4InputSource.hpp>

#include <xercesc/util/XMLUni.hpp>
#include <xercesc/util/XMLString.hpp>
#include <xercesc/util/PlatformUtils.hpp>

#include <xercesc/dom/DOM.hpp>

#include <xercesc/validators/common/Grammar.hpp>
#include <xercesc/framework/XMLGrammarPoolImpl.hpp>

using namespace XERCES_CPP_NAMESPACE;

    namespace xerces {
        namespace lua {

            static char const* version = "0.0.2";

            /////////////////
            class ErrorData {
            public:
                enum Type {
                    Warning=0,
                    Error,
                    FatalError
                };
            private:
                std::string SystemId;
                std::string PublicId;
                XMLFileLoc LineNumber;
                XMLFileLoc ColumnNumber;
                std::string Message;
            public:
                std::string getSystemId() const { return SystemId; }
                std::string getPublicId() const { return PublicId; }
                int getLineNumber() const { return (int)LineNumber; }
                int getColumnNumber() const { return (int)ColumnNumber; }
                std::string getMessage() const { return Message; }
            public:
                ErrorData(){}
                ErrorData(std::string s,std::string p,XMLFileLoc l,XMLFileLoc c,std::string m):
                    SystemId(s),
                    PublicId(p),
                    LineNumber(l),
                    ColumnNumber(c),
                    Message(m)
                {}
            };


            //////////////////////
            class ErrorLog {

            public:
                void AddLogEntry(
                    std::string S,
                    std::string P,
                    XMLFileLoc L,
                    XMLFileLoc C,
                    std::string M) {
                        ErrorData Log(S,P,L,C,M);
                    entries.push_back(Log);
                }

                int Count() const {
                    return entries.size();
                }

                bool Ok() const {
                    return entries.size()==0;
                }

		        luabridge::RefCountedPtr<ErrorData> GetLogEntry(size_t pos) const {
                    if (pos >= 0 && pos < entries.size())
                        return luabridge::RefCountedPtr<ErrorData>(new ErrorData(entries[pos]));
                    else
                        return luabridge::RefCountedPtr<ErrorData>(new ErrorData);
                }
            private:
                std::vector<ErrorData> entries;
            };

            /////////////////////////////////////////////
            class CustomErrorHandler : public DOMErrorHandler
            {
            public:
                CustomErrorHandler():failed_ (false) {}
                bool failed () const { return failed_; }
                ErrorLog& Get() {
                    return Log;
                }
                bool handleError (const xercesc::DOMError& e)
                {
                    bool warn (e.getSeverity() == DOMError::DOM_SEVERITY_WARNING);

                    if (!warn)
                        failed_ = true;

                    DOMLocator* loc (e.getLocation ());

                    char* uri (XMLString::transcode (loc->getURI ()));
                    char* msg (XMLString::transcode (e.getMessage ()));

                    // cerr << uri << ":"
                    //     << loc->getLineNumber () << ":" << loc->getColumnNumber () << " "
                    //     << (warn ? "warning: " : "error: ") << msg << endl;

                    std::string M(msg);

                    Log.AddLogEntry(
                        "",
                        "",
                        loc->getLineNumber (),
                        loc->getColumnNumber (),
                        M);

                    XMLString::release (&uri);
                    XMLString::release (&msg);

                    return true;
                }
                
            private:
                ErrorLog Log;
                bool failed_;
            };

            ////////// GrammarType
            static int DTDGrammarType=(int)Grammar::DTDGrammarType;
            static int SchemaGrammarType=(int)Grammar::SchemaGrammarType;
            static int UnKnown=(int)Grammar::UnKnown;

            ////////// ValSchemes
            static int Val_Never=(int)AbstractDOMParser::Val_Never;
            static int Val_Always=(int)AbstractDOMParser::Val_Always;
            static int Val_Auto=(int)AbstractDOMParser::Val_Auto;

            //////////////////////
            class lXercesDOMParser {
            public:

                lXercesDOMParser() {
                     MemoryManager* mm (XMLPlatformUtils::fgMemoryManager);
                     gp  = new XMLGrammarPoolImpl (mm);
                     parser = create_parser (gp);
                }

                ~lXercesDOMParser() {
                    parser->release ();
                    delete gp;
                }

                DOMLSParser* create_parser (XMLGrammarPool* pool) {
                    const XMLCh ls_id [] = {chLatin_L, chLatin_S, chNull};

                    DOMImplementation* impl (
                        DOMImplementationRegistry::getDOMImplementation (ls_id));

                    DOMLSParser* parser (
                        impl->createLSParser (
                        DOMImplementationLS::MODE_SYNCHRONOUS,
                        0,
                        XMLPlatformUtils::fgMemoryManager,
                        pool));

                    DOMConfiguration* conf (parser->getDomConfig ());

                    // Commonly useful configuration.
                    //
                    conf->setParameter (XMLUni::fgDOMComments, false);
                    conf->setParameter (XMLUni::fgDOMDatatypeNormalization, true);
                    conf->setParameter (XMLUni::fgDOMEntities, false);
                    conf->setParameter (XMLUni::fgDOMNamespaces, true);
                    conf->setParameter (XMLUni::fgDOMElementContentWhitespace, false);

                    // Enable validation.
                    //
                    conf->setParameter (XMLUni::fgDOMValidate, true);
                    conf->setParameter (XMLUni::fgXercesSchema, true);
                    conf->setParameter (XMLUni::fgXercesSchemaFullChecking, false);

                    // Use the loaded grammar during parsing.
                    //
                    conf->setParameter (XMLUni::fgXercesUseCachedGrammarInParse, true);

                    // Don't load schemas from any other source (e.g., from XML document's
                    // xsi:schemaLocation attributes).
                    //
                    conf->setParameter (XMLUni::fgXercesLoadSchema, false);

                    // Xerces-C++ 3.1.0 is the first version with working multi
                    // import support.
                    //
                    #if _XERCES_VERSION >= 30100
                    conf->setParameter (XMLUni::fgXercesHandleMultipleImports, true);
                    #endif

                    // We will release the DOM document ourselves.
                    //
                    conf->setParameter (XMLUni::fgXercesUserAdoptsDOMDocument, true);

                    return parser;
                }

                luabridge::RefCountedPtr<ErrorLog> loadGrammar(const char* filename, int grammartype) {
                    CustomErrorHandler eh;
                    parser->getDomConfig ()->setParameter (XMLUni::fgDOMErrorHandler, &eh);

                    parser->loadGrammar(filename, Grammar::SchemaGrammarType, true);
                    return luabridge::RefCountedPtr<ErrorLog>(new ErrorLog(eh.Get()));
                }

                luabridge::RefCountedPtr<ErrorLog> loadGrammarString(const char* xsdstr, int grammartype) {
                    Wrapper4InputSource source (new xercesc::MemBufInputSource((const XMLByte *)xsdstr, strlen(xsdstr), ""));
                    CustomErrorHandler eh;
                    parser->getDomConfig ()->setParameter (XMLUni::fgDOMErrorHandler, &eh);

                    parser->loadGrammar(&source, Grammar::SchemaGrammarType, true);
                    return luabridge::RefCountedPtr<ErrorLog>(new ErrorLog(eh.Get()));
                }

                // void setValidationScheme(int scheme) {
                //     parser->getDomConfig ()->setParameter(setValidationScheme((XercesDOMParser::ValSchemes)scheme));
                // }

		        luabridge::RefCountedPtr<ErrorLog> parse(const char* filename) {
                    CustomErrorHandler eh;
                    parser->getDomConfig ()->setParameter (XMLUni::fgDOMErrorHandler, &eh);
                    parser->parseURI(filename);
                    return luabridge::RefCountedPtr<ErrorLog>(new ErrorLog(eh.Get()));
                }

                luabridge::RefCountedPtr<ErrorLog> parseString(const char* xmlstr) {
                    Wrapper4InputSource source (new xercesc::MemBufInputSource((const XMLByte *)xmlstr, strlen(xmlstr), ""));
                    CustomErrorHandler eh;
                    parser->getDomConfig ()->setParameter (XMLUni::fgDOMErrorHandler, &eh);
                    parser->parse(&source);
                    return luabridge::RefCountedPtr<ErrorLog>(new ErrorLog(eh.Get()));
                }

            private:
                //XercesDOMParser parser;
                XMLGrammarPool* gp;
                DOMLSParser* parser;
            };
        }
}

void register_xerceslua (lua_State* L) {
    using namespace xerces::lua;

    try {
        XMLPlatformUtils::Initialize();
    }
    catch (const XMLException& toCatch) {
        std::cerr<<toCatch.getMessage()<<std::endl;
    }

#ifdef DEBUG
    std::cout<<"loaded xerceslua "<<version<<std::endl;
#endif

    luabridge::getGlobalNamespace(L)
        .beginNamespace("xerces")

        .addVariable("version",&version,false)

        .beginNamespace("GrammarType")
            .addVariable("DTDGrammarType",&DTDGrammarType,false)
            .addVariable("SchemaGrammarType",&SchemaGrammarType,false)
            .addVariable("UnKnown",&UnKnown,false)
        .endNamespace()

        .beginNamespace("ValSchemes")
            .addVariable("Val_Never",&Val_Never,false)
            .addVariable("Val_Always",&Val_Always,false)
            .addVariable("Val_Auto",&Val_Auto,false)
        .endNamespace()

        .beginClass<ErrorLog>("ErrorLog")
            .addConstructor<void (*)()>()
            .addProperty("Count",&ErrorLog::Count)
            .addProperty("Ok",&ErrorLog::Ok)
            .addFunction("GetLogEntry",&ErrorLog::GetLogEntry)
        .endClass()

        .beginClass<ErrorData>("ErrorData")
            .addConstructor<void (*)()>()
            .addProperty("SystemId",&ErrorData::getSystemId)
            .addProperty("PublicId",&ErrorData::getPublicId)
            .addProperty("LineNumber",&ErrorData::getLineNumber)
            .addProperty("ColumnNumber",&ErrorData::getColumnNumber)
            .addProperty("Message",&ErrorData::getMessage)
        .endClass()

        .beginClass<lXercesDOMParser>("XercesDOMParser")
            .addConstructor<void (*)()>()
            .addFunction("loadGrammar",&lXercesDOMParser::loadGrammar)
            .addFunction("loadGrammarString",&lXercesDOMParser::loadGrammarString)
            // .addFunction("setValidationScheme",&lXercesDOMParser::setValidationScheme)
            .addFunction("parse",&lXercesDOMParser::parse)
            .addFunction("parseString",&lXercesDOMParser::parseString)
        .endClass()

        .endNamespace()
        ;

}
