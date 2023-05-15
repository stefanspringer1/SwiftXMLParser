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
    
    func testExample() {
        
        let lineCollector = LineCollector()
        
        xParseTest(forText: """
        <?xml version="1.0" encoding="us-ascii"?>
        <!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [
         <!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>
                 <!ENTITY foo '"bar"'>
        ]>
        <a var='"nana"'>Hallo</a>
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
        internal entity declaration: name "foo", value "\"bar\""; 5:10 - 5:30 (432..<453 in data)
          binary excerpt: {<!ENTITY foo '"bar"'>}
          line excerpt:   {<!ENTITY foo '"bar"'>}
        document type declaration end; 6:1 - 6:2 (454..<456 in data)
          binary excerpt: {]>}
          line excerpt:   {]>}
        start of element: name "a", attributes "var": "\"nana\""; 7:1 - 7:16 (457..<473 in data)
          binary excerpt: {<a var='"nana"'>}
          line excerpt:   {<a var='"nana"'>}
        text: "Hallo", whitespace indicator NOT_WHITESPACE; 7:17 - 7:21 (473..<478 in data)
          binary excerpt: {Hallo}
          line excerpt:   {Hallo}
        end of element: name "a"; 7:22 - 7:25 (478..<482 in data)
          binary excerpt: {</a>}
          line excerpt:   {</a>}
        document ended
        """#)
    }
    
}
