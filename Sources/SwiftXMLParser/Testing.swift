//
//  File.swift
//  
//
//  Created by Stefan Springer on 19.03.22.
//

import Foundation
import SwiftXMLInterfaces

public class XTestPrinter: XTestWriter {
    public func writeLine(_ text: String) {
        print(text)
    }
    
    public init() {}
}

public func xParseTest(forData data: Data, writer: XTestWriter = XTestPrinter(), sourceInfo: String? = nil, fullDebugOutput: Bool = false) {
    do {
        try XParser(
            internalEntityResolver: XSimpleInternalEntityResolver(entityInAttributeTriggersError: false),
            debugWriter: fullDebugOutput ? { writer.writeLine($0) } : nil
        )
        .parse(fromData: data, sourceInfo: sourceInfo, eventHandlers: [
            XTestParsePrinter(data: data, writer: writer)
        ])
    }
    catch {
        print("ERROR: \(error.localizedDescription)")
    }
}

public func xParseTest(forText text: String, writer: XTestWriter = XTestPrinter(), sourceInfo: String? = nil, fullDebugOutput: Bool = false) {
    xParseTest(forData: text.data(using: .utf8)!, writer: writer, sourceInfo: sourceInfo, fullDebugOutput: fullDebugOutput)
}

public func xParseTest(forURL url: URL, writer: XTestWriter = XTestPrinter(), sourceInfo: String? = nil, fullDebugOutput: Bool = false) throws {
    xParseTest(forData: try Data(contentsOf: url), writer: writer, sourceInfo: sourceInfo, fullDebugOutput: fullDebugOutput)
}

public func xParseTest(forPath path: String, writer: XTestWriter = XTestPrinter(), sourceInfo: String? = nil, fullDebugOutput: Bool = false) throws {
    xParseTest(forData: try Data(contentsOf: URL(fileURLWithPath: path)), writer: writer, sourceInfo: sourceInfo, fullDebugOutput: fullDebugOutput)
}

public protocol XTestWriter {
    func writeLine(_: String)
}

enum ParseExceptions: Error{
    case lineDoesNotExist(String)
    case unknown(String)
}

public class XSimpleInternalEntityResolver: InternalEntityResolver {
    
    let entityInAttributeTriggersError: Bool
    
    public init(entityInAttributeTriggersError: Bool) {
        self.entityInAttributeTriggersError = entityInAttributeTriggersError
    }
    
    public func resolve(entityWithName entityName: String, forAttributeWithName attributeName: String?, atElementWithName elementName: String?) -> String? {
        return attributeName != nil && entityInAttributeTriggersError ? "[\(entityName)]" : nil
    }
}

public class XTestParsePrinter: XEventHandler {
    
    var writer: XTestWriter
    
    static func linesFromData(data: Data) -> [String] {
        let text = String(data: data, encoding: String.Encoding.utf8)!
        return text.split(separator: "\n", omittingEmptySubsequences: false).map{ String($0) }
    }
    
    var lines: [String]
    var data: Data
    
    var sleepingLines = [[String]]()
    var sleepingDatas = [Data]()
    
    public var errors = [Error]()
    
    public func enterExternalDataSource(data: Data, url: URL?) {
        sleepingLines.append(self.lines)
        sleepingDatas.append(self.data)
        self.data = data
        self.lines = XTestParsePrinter.linesFromData(data: self.data)
    }
    
    public func leaveExternalDataSource() {
        if let awakenedLines = sleepingLines.popLast(),
           let awakenedData = sleepingDatas.popLast() {
            lines = awakenedLines
            data = awakenedData
        }
    }
    
    public init(data: Data, writer: XTestWriter) throws {
        self.data = data
        self.lines = XTestParsePrinter.linesFromData(data: data)
        self.writer = writer
    }
    
    func write(_ text: String) {
        writer.writeLine(text)
    }
    
    func fakeThrow(error: Error) {
        errors.append(error)
    }
    func writeTextExcerpt(forTextRange XTextRange: XTextRange) {
        
        func correctedRightIndex(_ _rightIndex: Int?, count: Int, hasNextLine: Bool) -> Int {
            var rightIndex = _rightIndex
            if rightIndex == count + 1 && hasNextLine {
                rightIndex = count
            }
            return rightIndex ?? count
        }
        
        for lineNo in XTextRange.startLine...XTextRange.endLine {
            let technicalLineNumber = lineNo-1
            if technicalLineNumber >= lines.count {
                fakeThrow(error: ParseExceptions.lineDoesNotExist("PARSER BUG: line \(lineNo) does not exist!"))
            }
            else {
                let line = lines[technicalLineNumber]
                do {
                    let subLine = try line.substring(with:
                        (lineNo == XTextRange.startLine ? XTextRange.startColumn-1 : 0)..<(
                            correctedRightIndex(lineNo == XTextRange.endLine ? XTextRange.endColumn : nil, count: lines[technicalLineNumber].count, hasNextLine: technicalLineNumber + 1 < lines.count))
                        )
                    writer.writeLine("  line excerpt:   {\(subLine)}")
                }
                catch {
                    fakeThrow(error: ParseExceptions.unknown("PARSER BUG: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    func writeBinaryExcerpt(forDataRange XDataRange: XDataRange) {
        writer.writeLine("  binary excerpt: {\(String(decoding: data.subdata(in: XDataRange.binaryStart..<XDataRange.binaryUntil), as: UTF8.self))}")
    }
    
    func writeExcerpt(forTextRange XTextRange: XTextRange, forDataRange XDataRange: XDataRange) {
        writeBinaryExcerpt(forDataRange: XDataRange)
        writeTextExcerpt(forTextRange: XTextRange)
    }
    
    public func documentStart() {
        write("document started")
    }
    
    public func xmlDeclaration(version: String, encoding: String?, standalone: String?, textRange: XTextRange?, dataRange: XDataRange?) {
        write("XML declaration: version \"\(version.cited())\"\(encoding != nil ? ", encoding \"\(encoding!.cited())\"" : "")\(standalone != nil ? ", standalone \"\(standalone!.cited())\"" : ""); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func documentTypeDeclarationStart(type: String, publicID: String?, systemID: String?, textRange: XTextRange?, dataRange: XDataRange?) {
        write("document type declaration start: type \"\(type.cited())\"\(publicID != nil ? ", publicID \"\(publicID!.cited())\"" : "")\(systemID != nil ? ", systemID \"\(systemID!.cited())\"" : ""); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func documentTypeDeclarationEnd(textRange: XTextRange?, dataRange: XDataRange?) {
        write("document type declaration end; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func elementStart(name: String, attributes: [String : String]?, textRange: XTextRange?, dataRange: XDataRange?) {
        if let theAttributes = attributes {
            write("start of element: name \"\(name.cited())\", attributes \(theAttributes.map{ "\($0): \"\($1.cited())\"" }.joined(separator: ", ")); \(textRange!) (\(dataRange!) in data)")
        }
        else {
            write("start of element: name \"\(name.cited())\", no attributes; \(textRange!) (\(dataRange!) in data)")
        }
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func elementEnd(name: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("end of element: name \"\(name.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func text(text: String, whitespace: WhitespaceIndicator, textRange: XTextRange?, dataRange: XDataRange?) {
        write("text: \"\(text.cited())\", whitespace indicator \(whitespace); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func cdataSection(text: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("CDATA section: content \"\(text.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func processingInstruction(target: String, data: String?, textRange: XTextRange?, dataRange: XDataRange?) {
        write("processing instruction: target \"\(target.cited())\"\(data != nil ? ", content \"\(data!.cited())\"" : ""); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func comment(text: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("comment: content \"\(text.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func internalEntityDeclaration(name: String, value: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("internal entity declaration: name \"\(name.cited())\", value \"\(value.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func externalEntityDeclaration(name: String, publicID: String?, systemID: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("external entity declaration: name \"\(name.cited())\"\(publicID != nil ? ", public ID: \"\(publicID!.cited())\"" : ""), system ID \"\(systemID.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func unparsedEntityDeclaration(name: String, publicID: String?, systemID: String, notation: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("unparsed entity declaration: name \"\(name.cited())\"\(publicID != nil ? ", public ID: \"\(publicID!.cited())\"" : ""), system ID \"\(systemID.cited())\", notation \"\(notation.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func notationDeclaration(name: String, publicID: String?, systemID: String?, textRange: XTextRange?, dataRange: XDataRange?) {
        write("notation declaration: name \"\(name.cited())\"\(publicID != nil ? ", public ID: \"\(publicID!.cited())\"" : "")\(systemID != nil ? ", public ID: \"\(systemID!.cited())\"" : ""); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func internalEntity(name: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("internal entity: name \"\(name.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func externalEntity(name: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("external entity: name \"\(name.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func elementDeclaration(name: String, literal: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("element declaration: name \"\(name.cited())\": \"\(literal.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func attributeListDeclaration(name: String, literal: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("attribute list declaration: name \"\(name.cited())\": \"\(literal.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func parameterEntityDeclaration(name: String, value: String, textRange: XTextRange?, dataRange: XDataRange?) {
        write("parameter entity declaration: name \"\(name.cited())\": \"\(value.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
    }
    
    public func documentEnd() {
        write("document ended")
    }
    
}

extension String {
    
    func index(from: Int) throws -> Index {
        if from > self.count {
            throw ParseError("index \(from) not in text {\(self)}")
        }
        return self.index(startIndex, offsetBy: from)
    }

    func substring(with r: Range<Int>) throws -> String {
        let startIndex = try index(from: r.lowerBound)
        let endIndex = try index(from: r.upperBound)
        return String(self[startIndex..<endIndex])
    }
    
    func cited() -> String {
        return self.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\"", with: "\\\"")
        //        return self.debugDescription
    }
    
}
