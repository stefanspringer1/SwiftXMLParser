import XCTest
@testable import SwiftXMLParser

final class SwiftXMLParserTests: XCTestCase {
    
    func testBOM() {
        xParseTest(forData: [U_BOM_1, U_BOM_2, U_BOM_3] + "<a/>".data(using: .utf8)!)
    }
    
    func testExample() {
        xParseTest(forText: """
        <?xml version="1.0" encoding="us-ascii"?>
        <!DOCTYPE tr PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//DTD Technical Regulation::Revision 3//EN' 'TR3000.dtd'
        [
         <!ENTITY gfo-9.1.1-1 PUBLIC '+//ISO 9070/RA::A00007::GE::DIN German Institute for Standardization::Regulations//NONSGML Testpublikation 20100811:2021-05-27::Graphical form 9.1.1-1//EN' 'x2cec2af.gfo-9~1~1-1' NDATA gif>
                 <!ENTITY foo '"bar"'>
        ]>
        <a var='"nana"'>Hallo</a>
        """)
    }
    
}
