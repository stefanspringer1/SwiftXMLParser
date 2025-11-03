//===--- SwiftXMLParserTests.swift ----------------------------------------===//
//
// This source file is part of the SwiftXML.org open source project
//
// Copyright (c) 2021-2023 Stefan Springer (https://stefanspringer.com)
// and the SwiftXML project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import XCTest
@testable import SwiftXMLParser
import SwiftXMLInterfaces

final class SwiftXMLParserTests: XCTestCase {
    
    func testBOM() {
        xParseTest(forData: [U_BOM_1, U_BOM_2, U_BOM_3] + "<a/>".data(using: .utf8)!)
    }
    
    func testTextAllowedInElementWithName() throws {
        let source = """
                    <div class="tr--p annotate">Hallo <b>Welt!</b></div>
                    """
        let parser = XParser(textAllowedInElementWithName: ["p","b","div"])
        try parser.parse(fromData: source.data(using: .utf8)!, eventHandlers: [])
    }
    
    func testTwoEqualSignsForAttribute() {
        let lineCollector = LineCollector()
        
        xParseTest(forText: """
        <a att=="val"/>
        """, writer: lineCollector)
        
        XCTAssertEqual(lineCollector.lines.joined(separator: "\n"), #"""
        document started
        ERROR: 1:8:E: multiple equal signs after token
        """#)
    }
    
    /*
     https://www.w3.org/TR/2006/REC-xml11-20060816/#sec-comments
     */
    func testNumCharRefs() {
        let lineCollector = LineCollector()
        
        xParseTest(forText: """
        <a>&#x64;</a><!-- &#x64; huhuhu -->
        """, writer: lineCollector)
        
        XCTAssertEqual(lineCollector.lines.joined(separator: "\n"), #"""
        document started
        start of element: name "a", no attributes; 1:1 - 1:3 (0..<3 in data)
          in current source:  from data: {<a>}, from lines: {<a>}
          in original source: from data: {<a>}, from lines: {<a>}
        text: "d", whitespace indicator NOT_WHITESPACE; 1:4 - 1:9 (3..<9 in data)
          in current source:  from data: {&#x64;}, from lines: {&#x64;}
          in original source: from data: {&#x64;}, from lines: {&#x64;}
        end of element: name "a"; 1:10 - 1:13 (9..<13 in data)
          in current source:  from data: {</a>}, from lines: {</a>}
          in original source: from data: {</a>}, from lines: {</a>}
        comment: content " &#x64; huhuhu "; 1:14 - 1:35 (13..<35 in data)
          in current source:  from data: {<!-- &#x64; huhuhu -->}, from lines: {<!-- &#x64; huhuhu -->}
          in original source: from data: {<!-- &#x64; huhuhu -->}, from lines: {<!-- &#x64; huhuhu -->}
        document ended
        """#)
    }
    
    func testValueQuotes() {
        
        let lineCollector = LineCollector()
        
        xParseTest(forText: """
        <?xml version="1.0" encoding="us-ascii"?>
        <!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [
         <!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>
                 <!ENTITY foo1 "'bar1'">
                 <!ENTITY foo2 '"bar2"'>
        ]>
        <a var1="'val1'" var2='"val1"'>Hallo</a>
        """, writer: lineCollector)
        
        XCTAssertEqual(lineCollector.lines.joined(separator: "\n"), #"""
        document started
        XML declaration: version "1.0", encoding "us-ascii"; 1:1 - 1:41 (0..<41 in data)
          in current source:  from data: {<?xml version="1.0" encoding="us-ascii"?>}, from lines: {<?xml version="1.0" encoding="us-ascii"?>}
          in original source: from data: {<?xml version="1.0" encoding="us-ascii"?>}, from lines: {<?xml version="1.0" encoding="us-ascii"?>}
        document type declaration start: name "tr", publicID "+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN", systemID "TR3000.dtd"; 2:1 - 3:1 (42..<202 in data)
          in current source:  from data: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [}, from lines: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'}
          in original source: from data: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [}, from lines: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'}
        unparsed entity declaration: name "gfo-9.1.1-1", public ID: "+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN", system ID "x2cec2af.gfo-9~1~1-1", notation "gif"; 4:2 - 4:219 (204..<422 in data)
          in current source:  from data: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}, from lines: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}
          in original source: from data: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}, from lines: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}
        internal entity declaration: name "foo1", value "'bar1'"; 5:10 - 5:32 (432..<455 in data)
          in current source:  from data: {<!ENTITY foo1 "'bar1'">}, from lines: {<!ENTITY foo1 "'bar1'">}
          in original source: from data: {<!ENTITY foo1 "'bar1'">}, from lines: {<!ENTITY foo1 "'bar1'">}
        internal entity declaration: name "foo2", value "\"bar2\""; 6:10 - 6:32 (465..<488 in data)
          in current source:  from data: {<!ENTITY foo2 '"bar2"'>}, from lines: {<!ENTITY foo2 '"bar2"'>}
          in original source: from data: {<!ENTITY foo2 '"bar2"'>}, from lines: {<!ENTITY foo2 '"bar2"'>}
        document type declaration end; 7:1 - 7:2 (489..<491 in data)
          in current source:  from data: {]>}, from lines: {]>}
          in original source: from data: {]>}, from lines: {]>}
        start of element: name "a", attributes "var1": "'val1'", "var2": "\"val1\""; 8:1 - 8:31 (492..<523 in data)
          in current source:  from data: {<a var1="'val1'" var2='"val1"'>}, from lines: {<a var1="'val1'" var2='"val1"'>}
          in original source: from data: {<a var1="'val1'" var2='"val1"'>}, from lines: {<a var1="'val1'" var2='"val1"'>}
        text: "Hallo", whitespace indicator NOT_WHITESPACE; 8:32 - 8:36 (523..<528 in data)
          in current source:  from data: {Hallo}, from lines: {Hallo}
          in original source: from data: {Hallo}, from lines: {Hallo}
        end of element: name "a"; 8:37 - 8:40 (528..<532 in data)
          in current source:  from data: {</a>}, from lines: {</a>}
          in original source: from data: {</a>}, from lines: {</a>}
        document ended
        """#)
    }
    
    func testInternalSubset() {
        
        let lineCollector = LineCollector()
        
        xParseTest(forText: """
        <?xml version="1.0" encoding="us-ascii"?>
        <!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [
         <!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>
                 <!ENTITY foo "bar">
        ]>
        <a var='nana'>Hallo</a>
        """, writer: lineCollector)
        
        XCTAssertEqual(lineCollector.lines.joined(separator: "\n"), #"""
        document started
        XML declaration: version "1.0", encoding "us-ascii"; 1:1 - 1:41 (0..<41 in data)
          in current source:  from data: {<?xml version="1.0" encoding="us-ascii"?>}, from lines: {<?xml version="1.0" encoding="us-ascii"?>}
          in original source: from data: {<?xml version="1.0" encoding="us-ascii"?>}, from lines: {<?xml version="1.0" encoding="us-ascii"?>}
        document type declaration start: name "tr", publicID "+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN", systemID "TR3000.dtd"; 2:1 - 3:1 (42..<202 in data)
          in current source:  from data: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [}, from lines: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'}
          in original source: from data: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [}, from lines: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'}
        unparsed entity declaration: name "gfo-9.1.1-1", public ID: "+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN", system ID "x2cec2af.gfo-9~1~1-1", notation "gif"; 4:2 - 4:219 (204..<422 in data)
          in current source:  from data: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}, from lines: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}
          in original source: from data: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}, from lines: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}
        internal entity declaration: name "foo", value "bar"; 5:10 - 5:28 (432..<451 in data)
          in current source:  from data: {<!ENTITY foo "bar">}, from lines: {<!ENTITY foo "bar">}
          in original source: from data: {<!ENTITY foo "bar">}, from lines: {<!ENTITY foo "bar">}
        document type declaration end; 6:1 - 6:2 (452..<454 in data)
          in current source:  from data: {]>}, from lines: {]>}
          in original source: from data: {]>}, from lines: {]>}
        start of element: name "a", attributes "var": "nana"; 7:1 - 7:14 (455..<469 in data)
          in current source:  from data: {<a var='nana'>}, from lines: {<a var='nana'>}
          in original source: from data: {<a var='nana'>}, from lines: {<a var='nana'>}
        text: "Hallo", whitespace indicator NOT_WHITESPACE; 7:15 - 7:19 (469..<474 in data)
          in current source:  from data: {Hallo}, from lines: {Hallo}
          in original source: from data: {Hallo}, from lines: {Hallo}
        end of element: name "a"; 7:20 - 7:23 (474..<478 in data)
          in current source:  from data: {</a>}, from lines: {</a>}
          in original source: from data: {</a>}, from lines: {</a>}
        document ended
        """#)
    }
    
    func testComplexInternalEntity() {
        
        class EntityResolver: InternalEntityResolver {
            
            public func resolve(entityWithName entityName: String, forAttributeWithName attributeName: String?, atElementWithName elementName: String?) -> String? {
                switch entityName {
                case "test1": "Hello &amp; &test2; <b/>"
                case "test2": "&lt; so"
                default: nil
                }
            }
            
        }
        
        let source = #"""
        <a>&test1;</a>
        """#
        
        do {
            let lineCollector = LineCollector()
            
            xParseTest(
                forText: source,
                internalEntityResolver: EntityResolver(),
                writer: lineCollector,
                immediateTextHandlingNearEntities: .atExternalEntities // the default
            )
            
            XCTAssertEqual(lineCollector.lines.joined(separator: "\n"), #"""
                document started
                start of element: name "a", no attributes; 1:1 - 1:3 (0..<3 in data)
                  in current source:  from data: {<a>}, from lines: {<a>}
                  in original source: from data: {<a>}, from lines: {<a>}
                text: "Hello & < so ", whitespace indicator NOT_WHITESPACE; 1:1 - 1:20 (0..<20 in data)
                  in current source:  from data: {Hello &amp; &test2; }, from lines: {Hello &amp; &test2; }
                  in original source: from data: {&test1;}, from lines: {&test1;}
                start of element: name "b", no attributes; 1:21 - 1:24 (20..<24 in data)
                  in current source:  from data: {<b/>}, from lines: {<b/>}
                  in original source: from data: {&test1;}, from lines: {&test1;}
                end of element: name "b"; 1:21 - 1:24 (20..<24 in data)
                  in current source:  from data: {<b/>}, from lines: {<b/>}
                  in original source: from data: {&test1;}, from lines: {&test1;}
                end of element: name "a"; 1:11 - 1:14 (10..<14 in data)
                  in current source:  from data: {</a>}, from lines: {</a>}
                  in original source: from data: {</a>}, from lines: {</a>}
                document ended
                """#)
        }
        
        do {
            let lineCollector = LineCollector()
            
            xParseTest(
                forText: source,
                internalEntityResolver: EntityResolver(),
                writer: lineCollector,
                immediateTextHandlingNearEntities: .always
            )
            
            XCTAssertEqual(lineCollector.lines.joined(separator: "\n"), #"""
                document started
                start of element: name "a", no attributes; 1:1 - 1:3 (0..<3 in data)
                  in current source:  from data: {<a>}, from lines: {<a>}
                  in original source: from data: {<a>}, from lines: {<a>}
                text: "Hello & ", whitespace indicator NOT_WHITESPACE; 1:13 - 1:18 (0..<12 in data)
                  in current source:  from data: {Hello &amp; }, from lines: {&test2}
                  in original source: from data: {&test1;}, from lines: {&test1;}
                text: "< so", whitespace indicator NOT_WHITESPACE; 1:1 - 1:7 (0..<7 in data)
                  in current source:  from data: {&lt; so}, from lines: {&lt; so}
                  in original source: from data: {&test1;}, from lines: {&test1;}
                text: " ", whitespace indicator WHITESPACE; 1:20 - 1:20 (19..<20 in data)
                  in current source:  from data: { }, from lines: { }
                  in original source: from data: {&test1;}, from lines: {&test1;}
                start of element: name "b", no attributes; 1:21 - 1:24 (20..<24 in data)
                  in current source:  from data: {<b/>}, from lines: {<b/>}
                  in original source: from data: {&test1;}, from lines: {&test1;}
                end of element: name "b"; 1:21 - 1:24 (20..<24 in data)
                  in current source:  from data: {<b/>}, from lines: {<b/>}
                  in original source: from data: {&test1;}, from lines: {&test1;}
                end of element: name "a"; 1:11 - 1:14 (10..<14 in data)
                  in current source:  from data: {</a>}, from lines: {</a>}
                  in original source: from data: {</a>}, from lines: {</a>}
                document ended
                """#)
        }
    }
    
    func testParserAbortion() throws {
        
        let source = """
            <a>
                <b>
                    <c/>
                </b>
            </a>
            """
        
        class AbortingEventHandler: XDefaultEventHandler {
            
            let abortingAtElementWithName: String?
            var messages = [String]()
            
            init(abortingAtElementWithName: String?) {
                self.abortingAtElementWithName = abortingAtElementWithName
            }
            
            override func elementStart(name: String, attributes: inout [String : String], textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
                messages.append("starting <\(name)>")
                if name == abortingAtElementWithName {
                    messages.append("abort!")
                    return false
                } else {
                    return true
                }
            }
            
            override func elementEnd(name: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
                messages.append("ending <\(name)>")
                return true
            }
            
        }
        
        guard let data = source.data(using: .utf8) else {
            throw XCTSkip("couldn't convert to utf8")
        }
        
        do {
            let abortingEventHandler = AbortingEventHandler(abortingAtElementWithName: nil)
            try XParser().parse(fromData: data, eventHandlers: [abortingEventHandler])
            XCTAssertEqual(abortingEventHandler.messages.joined(separator: "\n"), """
                starting <a>
                starting <b>
                starting <c>
                ending <c>
                ending <b>
                ending <a>
                """)
        }
        
        do {
            let abortingEventHandler = AbortingEventHandler(abortingAtElementWithName: "a")
            try XParser().parse(fromData: data, eventHandlers: [abortingEventHandler])
            XCTAssertEqual(abortingEventHandler.messages.joined(separator: "\n"), """
                starting <a>
                abort!
                """)
        }
        
        do {
            let abortingEventHandler = AbortingEventHandler(abortingAtElementWithName: "b")
            try XParser().parse(fromData: data, eventHandlers: [abortingEventHandler])
            XCTAssertEqual(abortingEventHandler.messages.joined(separator: "\n"), """
                starting <a>
                starting <b>
                abort!
                """)
        }
        
    }
}
