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

final class SwiftXMLParserTests: XCTestCase {
    
    func testBOM() {
        xParseTest(forData: [U_BOM_1, U_BOM_2, U_BOM_3] + "<a/>".data(using: .utf8)!)
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
          binary excerpt: {<a>}
          line excerpt:   {<a>}
        text: "d", whitespace indicator NOT_WHITESPACE; 1:4 - 1:9 (3..<9 in data)
          binary excerpt: {&#x64;}
          line excerpt:   {&#x64;}
        end of element: name "a"; 1:10 - 1:13 (9..<13 in data)
          binary excerpt: {</a>}
          line excerpt:   {</a>}
        comment: content " &#x64; huhuhu "; 1:14 - 1:35 (13..<35 in data)
          binary excerpt: {<!-- &#x64; huhuhu -->}
          line excerpt:   {<!-- &#x64; huhuhu -->}
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
          binary excerpt: {<?xml version="1.0" encoding="us-ascii"?>}
          line excerpt:   {<?xml version="1.0" encoding="us-ascii"?>}
        document type declaration start: type "tr", publicID "+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN", systemID "TR3000.dtd"; 2:1 - 3:1 (42..<202 in data)
          binary excerpt: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [}
          line excerpt:   {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'}
          line excerpt:   {[}
        unparsed entity declaration: name "gfo-9.1.1-1", public ID: "+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN", system ID "x2cec2af.gfo-9~1~1-1", notation "gif"; 4:2 - 4:219 (204..<422 in data)
          binary excerpt: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}
          line excerpt:   {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}
        internal entity declaration: name "foo1", value "'bar1'"; 5:10 - 5:32 (432..<455 in data)
          binary excerpt: {<!ENTITY foo1 "'bar1'">}
          line excerpt:   {<!ENTITY foo1 "'bar1'">}
        internal entity declaration: name "foo2", value "\"bar2\""; 6:10 - 6:32 (465..<488 in data)
          binary excerpt: {<!ENTITY foo2 '"bar2"'>}
          line excerpt:   {<!ENTITY foo2 '"bar2"'>}
        document type declaration end; 7:1 - 7:2 (489..<491 in data)
          binary excerpt: {]>}
          line excerpt:   {]>}
        start of element: name "a", attributes "var1": "'val1'", "var2": "\"val1\""; 8:1 - 8:31 (492..<523 in data)
          binary excerpt: {<a var1="'val1'" var2='"val1"'>}
          line excerpt:   {<a var1="'val1'" var2='"val1"'>}
        text: "Hallo", whitespace indicator NOT_WHITESPACE; 8:32 - 8:36 (523..<528 in data)
          binary excerpt: {Hallo}
          line excerpt:   {Hallo}
        end of element: name "a"; 8:37 - 8:40 (528..<532 in data)
          binary excerpt: {</a>}
          line excerpt:   {</a>}
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
          binary excerpt: {<?xml version="1.0" encoding="us-ascii"?>}
          line excerpt:   {<?xml version="1.0" encoding="us-ascii"?>}
        document type declaration start: type "tr", publicID "+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN", systemID "TR3000.dtd"; 2:1 - 3:1 (42..<202 in data)
          binary excerpt: {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [}
          line excerpt:   {<!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'}
          line excerpt:   {[}
        unparsed entity declaration: name "gfo-9.1.1-1", public ID: "+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN", system ID "x2cec2af.gfo-9~1~1-1", notation "gif"; 4:2 - 4:219 (204..<422 in data)
          binary excerpt: {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}
          line excerpt:   {<!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>}
        internal entity declaration: name "foo", value "bar"; 5:10 - 5:28 (432..<451 in data)
          binary excerpt: {<!ENTITY foo "bar">}
          line excerpt:   {<!ENTITY foo "bar">}
        document type declaration end; 6:1 - 6:2 (452..<454 in data)
          binary excerpt: {]>}
          line excerpt:   {]>}
        start of element: name "a", attributes "var": "nana"; 7:1 - 7:14 (455..<469 in data)
          binary excerpt: {<a var='nana'>}
          line excerpt:   {<a var='nana'>}
        text: "Hallo", whitespace indicator NOT_WHITESPACE; 7:15 - 7:19 (469..<474 in data)
          binary excerpt: {Hallo}
          line excerpt:   {Hallo}
        end of element: name "a"; 7:20 - 7:23 (474..<478 in data)
          binary excerpt: {</a>}
          line excerpt:   {</a>}
        document ended
        """#)
    }
    
}
