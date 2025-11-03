//===--- Testing.swift ----------------------------------------------------===//
//
// This source file is part of the SwiftXML.org open source project
//
// Copyright (c) 2021-2023 Stefan Springer (https://stefanspringer.com)
// and the SwiftXML project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftXMLInterfaces

public class XTestPrinter: XTestWriter {
    public func writeLine(_ text: String) {
        print(text)
    }
    
    public init() {}
}

public class LineCollector: XTestWriter {
    
    private var _lines = [String]()
    
    public func writeLine(_ text: String) {
        _lines.append(text)
    }
    
    public init() {}
    
    var lines: [String] { _lines }
}

public func xParseTest(forData data: Data, internalEntityResolver: InternalEntityResolver? = nil, writer: XTestWriter = XTestPrinter(), sourceInfo: String? = nil, fullDebugOutput: Bool = false, immediateTextHandlingNearEntities: ImmediateTextHandlingNearEntities = .atExternalEntities) {
    do {
        try XParser(
            internalEntityAutoResolve: true,
            internalEntityResolver: internalEntityResolver ?? XSimpleInternalEntityResolver(entityInAttributeTriggersError: false),
            debugWriter: fullDebugOutput ? { writer.writeLine($0) } : nil
        )
        .parse(
            fromData: data,
            sourceInfo: sourceInfo,
            eventHandlers: [
                XTestParsePrinter(data: data, writer: writer)
            ],
            immediateTextHandlingNearEntities: immediateTextHandlingNearEntities
        )
    }
    catch {
        let message = "ERROR: \(error.localizedDescription)"
        print(message)
        writer.writeLine(message)
    }
}

public func xParseTest(forText text: String, internalEntityResolver: InternalEntityResolver? = nil, writer: XTestWriter = XTestPrinter(), sourceInfo: String? = nil, fullDebugOutput: Bool = false, immediateTextHandlingNearEntities: ImmediateTextHandlingNearEntities = .atExternalEntities) {
    xParseTest(forData: text.data(using: .utf8)!, internalEntityResolver: internalEntityResolver, writer: writer, sourceInfo: sourceInfo, fullDebugOutput: fullDebugOutput, immediateTextHandlingNearEntities: immediateTextHandlingNearEntities)
}

public func xParseTest(forURL url: URL, internalEntityResolver: InternalEntityResolver? = nil, writer: XTestWriter = XTestPrinter(), sourceInfo: String? = nil, fullDebugOutput: Bool = false, immediateTextHandlingNearEntities: ImmediateTextHandlingNearEntities = .atExternalEntities) throws {
    xParseTest(forData: try Data(contentsOf: url), internalEntityResolver: internalEntityResolver, writer: writer, sourceInfo: sourceInfo, fullDebugOutput: fullDebugOutput, immediateTextHandlingNearEntities: immediateTextHandlingNearEntities)
}

public func xParseTest(forPath path: String, internalEntityResolver: InternalEntityResolver? = nil, writer: XTestWriter = XTestPrinter(), sourceInfo: String? = nil, fullDebugOutput: Bool = false, immediateTextHandlingNearEntities: ImmediateTextHandlingNearEntities = .atExternalEntities) throws {
    xParseTest(forData: try Data(contentsOf: URL(fileURLWithPath: path)), internalEntityResolver: internalEntityResolver, writer: writer, sourceInfo: sourceInfo, fullDebugOutput: fullDebugOutput, immediateTextHandlingNearEntities: immediateTextHandlingNearEntities)
}

public protocol XTestWriter {
    func writeLine(_: String)
}

enum ParseExceptions: Error {
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

func linesFromData(data: Data) -> [String] {
    let text = String(data: data, encoding: String.Encoding.utf8)!
    return text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map{ String($0) }
}

public class XTestParsePrinter: XEventHandler {
    
    var writer: XTestWriter
    
    var lines: [String]
    var data: Data
    
    var sleepingLines = [[String]]()
    var sleepingDatas = [Data]()
    
    public var errors = [Error]()
    
    func enterDataSourceCommon(data: Data, textRange: XTextRange?, dataRange: XDataRange?) {
        if dataSourceLevel == 0 {
            originalTextRange = textRange
            originalDataRange = dataRange
        }
        dataSourceLevel += 1
        sleepingLines.append(self.lines)
        sleepingDatas.append(self.data)
        self.data = data
        self.lines = linesFromData(data: self.data)
    }
    
    func leaveDataSourceCommon() {
        if let awakenedLines = sleepingLines.popLast(),
           let awakenedData = sleepingDatas.popLast() {
            lines = awakenedLines
            data = awakenedData
        }
        dataSourceLevel -= 1
        if dataSourceLevel == 0 {
            originalTextRange = nil
            originalDataRange = nil
        }
    }
    
    var dataSourceLevel = 0
    var originalTextRange: XTextRange? = nil
    var originalDataRange: XDataRange? = nil
    
    public func enterInternalDataSource(data: Data, entityName: String, textRange: SwiftXMLInterfaces.XTextRange?, dataRange: SwiftXMLInterfaces.XDataRange?) -> Bool {
        print("entering replacement text for internal entity: name \"\(entityName)\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!, toStandardOut: true)
        print("  internal entity value: {\(String(data: data, encoding: String.Encoding.utf8)!)}")
        enterDataSourceCommon(data: data, textRange: textRange, dataRange: dataRange)
        return true
    }
    
    public func enterExternalDataSource(data: Data, entityName: String?, systemID: String, url: URL?, textRange: SwiftXMLInterfaces.XTextRange?, dataRange: SwiftXMLInterfaces.XDataRange?) -> Bool {
        print("entering replacement text for external parsed entity: name \"\(entityName ?? "")\", path [\(url?.path ?? "")]; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!, toStandardOut: true)
        enterDataSourceCommon(data: data, textRange: textRange, dataRange: dataRange)
        return true
    }
    
    public func leaveInternalDataSource() -> Bool {
        print("leaving internal replacement text")
        leaveDataSourceCommon()
        return true
    }
    
    public func leaveExternalDataSource() -> Bool {
        print("leaving external replacement text")
        leaveDataSourceCommon()
        return true
    }
    
    public init(data: Data, writer: XTestWriter) throws  {
        self.data = data
        self.lines = linesFromData(data: data)
        self.writer = writer
    }
    
    func write(_ text: String) {
        writer.writeLine(text)
    }
    
    func fakeThrow(error: Error) {
        errors.append(error)
    }
    
    func textExcerpt(forTextRange XTextRange: XTextRange, in lines: [String]) -> String {
        
        func correctedRightIndex(_ _rightIndex: Int?, count: Int, hasNextLine: Bool) -> Int {
            var rightIndex = _rightIndex
            if (rightIndex == count + 1 || rightIndex == count + 2) && hasNextLine {
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
                    return try line.substring(with:
                        (lineNo == XTextRange.startLine ? XTextRange.startColumn-1 : 0)..<(
                            correctedRightIndex(lineNo == XTextRange.endLine ? XTextRange.endColumn : nil, count: lines[technicalLineNumber].count, hasNextLine: technicalLineNumber + 1 < lines.count))
                        )
                }
                catch {
                    fakeThrow(error: ParseExceptions.unknown("PARSER BUG: \(error.localizedDescription)"))
                }
            }
        }
        return ""
    }
    
    func binaryExcerpt(forDataRange dataRange: XDataRange, in data: Data) -> String {
        String(decoding: data.subdata(in: dataRange.binaryStart..<dataRange.binaryUntil), as: UTF8.self)
    }
    
    func writeExcerpt(forTextRange textRange: XTextRange, forDataRange dataRange: XDataRange, toStandardOut: Bool = false) {
        let info = """
              in current source:  from data: {\(binaryExcerpt(forDataRange: dataRange, in: data))}, from lines: {\(textExcerpt(forTextRange: textRange, in: lines))}
              in original source: from data: {\(binaryExcerpt(forDataRange: originalDataRange ?? dataRange, in: sleepingDatas.first ?? data))}, from lines: {\(textExcerpt(forTextRange: originalTextRange ?? textRange, in: sleepingLines.first ?? lines))}
            """
        if toStandardOut {
            print(info)
        } else {
            writer.writeLine(info)
        }
    }
    
    public func documentStart() -> Bool {
        write("document started")
        return true
    }
    
    public func xmlDeclaration(version: String, encoding: String?, standalone: String?, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("XML declaration: version \"\(version.cited())\"\(encoding != nil ? ", encoding \"\(encoding!.cited())\"" : "")\(standalone != nil ? ", standalone \"\(standalone!.cited())\"" : ""); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func documentTypeDeclarationStart(type: String, publicID: String?, systemID: String?, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("document type declaration start: type \"\(type.cited())\"\(publicID != nil ? ", publicID \"\(publicID!.cited())\"" : "")\(systemID != nil ? ", systemID \"\(systemID!.cited())\"" : ""); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func documentTypeDeclarationEnd(textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("document type declaration end; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func elementStart(name: String, attributes: inout [String:String], textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        if !attributes.isEmpty {
            write("start of element: name \"\(name.cited())\", attributes \(attributes.sorted{ $0.0 < $1.0 }.map{ "\"\($0)\": \"\($1.cited())\"" }.joined(separator: ", ")); \(textRange!) (\(dataRange!) in data)")
        }
        else {
            write("start of element: name \"\(name.cited())\", no attributes; \(textRange!) (\(dataRange!) in data)")
        }
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func elementEnd(name: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("end of element: name \"\(name.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func text(text: String, whitespace: WhitespaceIndicator, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("text: \"\(text.cited())\", whitespace indicator \(whitespace); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func cdataSection(text: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("CDATA section: content \"\(text.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func processingInstruction(target: String, data: String?, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("processing instruction: target \"\(target.cited())\"\(data != nil ? ", content \"\(data!.cited())\"" : ""); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func comment(text: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("comment: content \"\(text.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func internalEntityDeclaration(name: String, value: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("internal entity declaration: name \"\(name.cited())\", value \"\(value.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func externalEntityDeclaration(name: String, publicID: String?, systemID: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("external entity declaration: name \"\(name.cited())\"\(publicID != nil ? ", public ID: \"\(publicID!.cited())\"" : ""), system ID \"\(systemID.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func unparsedEntityDeclaration(name: String, publicID: String?, systemID: String, notation: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("unparsed entity declaration: name \"\(name.cited())\"\(publicID != nil ? ", public ID: \"\(publicID!.cited())\"" : ""), system ID \"\(systemID.cited())\", notation \"\(notation.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func notationDeclaration(name: String, publicID: String?, systemID: String?, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("notation declaration: name \"\(name.cited())\"\(publicID != nil ? ", public ID: \"\(publicID!.cited())\"" : "")\(systemID != nil ? ", public ID: \"\(systemID!.cited())\"" : ""); \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func internalEntity(name: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("internal entity: name \"\(name.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func externalEntity(name: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("external entity: name \"\(name.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func elementDeclaration(name: String, literal: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("element declaration: name \"\(name.cited())\": \"\(literal.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func attributeListDeclaration(name: String, literal: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("attribute list declaration: name \"\(name.cited())\": \"\(literal.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func parameterEntityDeclaration(name: String, value: String, textRange: XTextRange?, dataRange: XDataRange?) -> Bool {
        write("parameter entity declaration: name \"\(name.cited())\": \"\(value.cited())\"; \(textRange!) (\(dataRange!) in data)")
        writeExcerpt(forTextRange: textRange!, forDataRange: dataRange!)
        return true
    }
    
    public func documentEnd() -> Bool {
        write("document ended")
        return true
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
        return self
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
        //        return self.debugDescription
    }
    
}
