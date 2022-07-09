//
//  XParser.swift
//
//  Created 2021 by Stefan Springer, https://stefanspringer.com
//  License: Apache License 2.0

import Foundation
import SwiftXMLInterfaces

// states for finding the type of declaration:
fileprivate typealias DECLARATION_LIKE_STATE_TYPE = UInt8
fileprivate let _EMPTY: DECLARATION_LIKE_STATE_TYPE = 0
fileprivate let _ONE: DECLARATION_LIKE_STATE_TYPE = 1
fileprivate let _DOCUMENT_TYPE_DECLARATION_HEAD = _ONE << 1
fileprivate let _ENTITY_DECLARATION = _ONE << 2
fileprivate let _NOTATION_DECLARATION = _ONE << 3
fileprivate let _ELEMENT_DECLARATION = _ONE << 4
fileprivate let _ATTRIBUTE_LIST_DECLARATION = _ONE << 5
fileprivate let _COMMENT = _ONE << 6
fileprivate let _CDATA_SECTION = _ONE << 7
fileprivate let _DECLARATION_LIKE = _DOCUMENT_TYPE_DECLARATION_HEAD | _ENTITY_DECLARATION | _NOTATION_DECLARATION | _ELEMENT_DECLARATION | _ATTRIBUTE_LIST_DECLARATION | _COMMENT | _CDATA_SECTION

// other contants:
fileprivate let EMPTY_QUOTE_SIGN: Data.Element = 0

public protocol itemParseResult {
    var description: String { get }
}

fileprivate struct tokenParseResult: itemParseResult {
    var value: String
    public var description: String { return value }
}

fileprivate extension String {
    func xmlEscpape() -> String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

public struct attributeParseResult: itemParseResult {
    var name: String
    var value: String
    public var description: String { return name + "=\"" + value.xmlEscpape() + "\"" }
}

fileprivate struct quotedParseResult: itemParseResult {
    var value: String
    public var description: String { return "\"" + value.xmlEscpape() + "\"" }
}

fileprivate enum State {
    case TEXT
    case ENTITY
    case JUST_STARTED_WITH_LESS_THAN_SIGN
    case START_OR_EMPTY_TAG
    case EMPTY_TAG_FINISHING
    case END_TAG
    case UNKNOWN_DECLARATION_LIKE
    case PROCESSING_INSTRUCTION
    case XML_DECLARATION
    case XML_DECLARATION_FINISHING
    case COMMENT
    case CDATA_SECTION
    case ENTITY_DECLARATION
    case NOTATION_DECLARATION
    case ELEMENT_DECLARATION
    case ATTRIBUTE_LIST_DECLARATION
    case DOCUMENT_TYPE_DECLARATION_HEAD
    case INTERNAL_SUBSET
    case DOCUMENT_TYPE_DECLARATION_TAIL
}

fileprivate struct ParsingDataForSource {
    let binaryPosition: Int
    let parsedBefore: Int
    let mainParsedBefore: Int
    let mainStartLine: Int
    let mainStartColumn: Int
    let line: Int
    let lastLine: Int
    let column: Int
    let lastColumn: Int
    let lastCodePoint: UnicodeCodePoint
    let lastLastCodePoint: UnicodeCodePoint
}

public class XParser: Parser {
    
    let internalEntityAutoResolve: Bool
    let internalEntityResolver: InternalEntityResolver?
    let textAllowedInElementWithName: ((String) -> Bool)?
    let insertExternalParsedEntities: Bool
    let debugWriter: ((String) -> ())?
    
    public init(
        internalEntityAutoResolve: Bool = false,
        internalEntityResolver: InternalEntityResolver? = nil,
        textAllowedInElementWithName: ((String) -> Bool)? = nil,
        insertExternalParsedEntities: Bool = true,
        debugWriter: ((String) -> ())? = nil
    ) {
        self.internalEntityAutoResolve = internalEntityAutoResolve
        self.internalEntityResolver = internalEntityResolver
        self.textAllowedInElementWithName = textAllowedInElementWithName
        self.insertExternalParsedEntities = insertExternalParsedEntities
        self.debugWriter = debugWriter
    }
    
    public func parse(
        fromData _data: Data,
        sourceInfo: String? = nil,
        eventHandlers: [XEventHandler]
    ) throws {
        var line = 1; var lastLine = 1
        var column = 0; var lastColumn = 1
        
        let directoryURL: URL?
        if let theSourceInfo = sourceInfo {
            directoryURL = URL(fileURLWithPath: theSourceInfo).deletingLastPathComponent()
        }
        else {
            directoryURL = nil
        }
        
        var currentExternalParsedEntityURLs = [URL]()
        
        func error(_ message: String, negativeColumnOffset: Int = 0) throws {
            throw ParseError("\(sourceInfo != nil ? "\(sourceInfo ?? ""):" : "")\(line):\(column-negativeColumnOffset):E: \(message)")
        }
        
        func characterCitation(_ codePoint: UnicodeCodePoint) -> String {
            if codePoint >= U_SPACE && codePoint <= U_MAX_ASCII {
                return "\"\(Character(UnicodeScalar(codePoint)!))\""
            }
            else {
                return "character x\(String(format: "%X", codePoint))"
            }
        }
        
        func isNameStartCharacter(_ codePoint: UnicodeCodePoint) -> Bool {
            return (codePoint >= U_LATIN_SMALL_LETTER_A && codePoint <= U_LATIN_SMALL_LETTER_Z)
            || (codePoint >= U_LATIN_CAPITAL_LETTER_A && codePoint <= U_LATIN_CAPITAL_LETTER_Z)
            || codePoint == U_COLON || codePoint == U_LOW_LINE
            || (codePoint >= 0xC0 && codePoint <= 0xD6) || (codePoint >= 0xD8 && codePoint <= 0xF6)
            || (codePoint >= 0xF8 && codePoint <= 0x2FF) || (codePoint >= 0x370 && codePoint <= 0x37D)
            || (codePoint >= 0x37F && codePoint <= 0x1FFF) || (codePoint >= 0x200C && codePoint <= 0x200D)
            || (codePoint >= 0x2070 && codePoint <= 0x218F) || (codePoint >= 0x2C00 && codePoint <= 0x2FEF)
            || (codePoint >= 0x3001 && codePoint <= 0xD7FF) || (codePoint >= 0xF900 && codePoint <= 0xFDCF)
            || (codePoint >= 0xFDF0 && codePoint <= 0xFFFD) || (codePoint >= 0x10000 && codePoint <= 0xEFFFF)
        }

        func isNameCharacter(_ codePoint: UnicodeCodePoint) -> Bool {
            return codePoint == U_HYPHEN_MINUS || codePoint == U_FULL_STOP
            || (codePoint >= U_DIGIT_ZERO && codePoint <= U_DIGIT_NINE)
            || isNameStartCharacter(codePoint)
            || codePoint == 0xB7 || (codePoint >= 0x0300 && codePoint <= 0x036F)
            || (codePoint >= 0x203F && codePoint <= 0x2040)
        }
        
        func formatNonWhitespace(_ text: String) -> String {
            return text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        
        var binaryPosition = -1
        var parsedBefore = 0
        var mainParsedBefore = 0
        var mainStartLine = 1
        var mainStartColumn = 1
        
        // entities:
        var entityBinaryStart = 1
        var entityStartLine = 1
        var entityStartColumn = 1
        var beforeEntityLine = 1
        var beforeEntityColumn = 1
        
        var outerParsedBefore = 0
        var possibleState = _DECLARATION_LIKE
        var unkownDeclarationOffset = 0
        
        var elementLevel = 0
        
        var texts = [String]()
        var isWhitespace = true
        
        // for parsing of start tag:
        var tokenStart = -1
        var tokenEnd = -1
        var token: String? = nil
        var name: String? = nil
        var equalSignAfterToken = false
        var quoteSign: Data.Element = 0
        var items = [itemParseResult]()
        
        var externalEntityNames = Set<String>()
        
        var someDocumentTypeDeclaration = false
        var someElement = false
        var ancestors = Stack<String>()
        
        var state = State.TEXT
        var outerState = State.TEXT
        
        var attributes = [String:String]()

        var expectedUTF8Rest = 0
        
        var declaredEntityNames: Set<String> = []
        var internalEntityDatas = [String:Data]()
        var externalParsedEntityPaths = [String:String]() // entity name -> path to file
        var declaredNotationNames: Set<String> = []
        var declaredElementNames: Set<String> = []
        var declaredAttributeListNames: Set<String> = []
        var declaredParameterEntityNames: Set<String> = []
        
        @inline(__always) func setMainStart(delayed: Bool = false) {
            mainParsedBefore = binaryPosition + (delayed ? 1 : 0)
            mainStartLine = line
            mainStartColumn = column + (delayed ? 1 : 0)
        }
        
        @inline(__always) func broadcast(
            xTextRange: XTextRange, xDataRange: XDataRange,
            processEventHandlers: (XEventHandler,XTextRange,XDataRange) -> ()
        ) {
            eventHandlers.forEach { eventHandler in
                processEventHandlers(eventHandler,xTextRange,xDataRange)
            }
        }
        
        @inline(__always) func broadcast(
            endLine: Int = line, endColumn: Int = column, binaryUntil: Int = binaryPosition + 1,
            processEventHandlers: (XEventHandler,XTextRange,XDataRange) -> ()
        ) {
            let xTextRange = XTextRange(
                startLine: mainStartLine,
                startColumn: mainStartColumn,
                endLine: endLine,
                endColumn: endColumn
            )
            let xDataRange = XDataRange(
                binaryStart: mainParsedBefore,
                binaryUntil: binaryUntil
            )
            broadcast(
                xTextRange: xTextRange, xDataRange: xDataRange,
                processEventHandlers: processEventHandlers
            )
        }
        
        broadcast { (eventHandler,XTextRange,XDataRange) in
            eventHandler.documentStart()
        }
        
        var codePoint: UnicodeCodePoint = 0
        var lastCodePoint: UnicodeCodePoint = 0
        var lastLastCodePoint: UnicodeCodePoint = 0
        
        var shift = 0
        var binaryPositionOffset = 0
        
        typealias ElementLevel = Int
        
        enum DataSourceType { case internalSource; case externalSource }
        typealias SleepReasons = DataSourceType
        
        var sleepingDatas = [(Data,Data.Iterator,ElementLevel,SleepReasons)]()
        var data = _data
        var activeDataIterator = data.makeIterator()
        
        var sleepingParsingDatas = [ParsingDataForSource]()
        
        func newParsePosition() {
            sleepingParsingDatas.append(ParsingDataForSource(
                binaryPosition: binaryPosition,
                parsedBefore: parsedBefore,
                mainParsedBefore: mainParsedBefore,
                mainStartLine: mainStartLine,
                mainStartColumn: mainStartColumn,
                line: line,
                lastLine: lastLine,
                column: column,
                lastColumn: lastColumn,
                lastCodePoint: lastCodePoint,
                lastLastCodePoint: lastLastCodePoint
            ))
            binaryPosition = -1
            parsedBefore = 0
            mainParsedBefore = 0
            mainStartLine = 1
            mainStartColumn = 1
            line = 1
            lastLine = 1
            column = 0
            lastColumn = 1
            lastCodePoint = 0
            lastLastCodePoint = 0
        }
        
        func restoreParsePosition() {
            if let sleepingParsingData = sleepingParsingDatas.popLast() {
                binaryPosition = sleepingParsingData.binaryPosition
                parsedBefore = sleepingParsingData.parsedBefore
                mainParsedBefore = sleepingParsingData.mainParsedBefore
                mainStartLine = sleepingParsingData.mainStartLine
                mainStartColumn = sleepingParsingData.mainStartColumn
                line = sleepingParsingData.line
                lastLine = sleepingParsingData.lastLine
                column = sleepingParsingData.column
                lastColumn = sleepingParsingData.lastColumn
                lastCodePoint = sleepingParsingData.lastCodePoint
                lastLastCodePoint = sleepingParsingData.lastLastCodePoint
            }
        }
        
        func startNewData(newData: Data, dataSourceType: DataSourceType) {
            sleepingDatas.append((data,activeDataIterator,elementLevel,dataSourceType))
            data = newData
            activeDataIterator = data.makeIterator()
            newParsePosition()
        }
        
        var ignoreNextLinebreak = -1
        
        binaryLoop: while true {
            
            var nextB = activeDataIterator.next()
            while nextB == nil {
                if let (awakenedData,awakenedDataIterator,oldElementLevel,sleepReason) = sleepingDatas.popLast() {
                    if !(state == .TEXT && outerState == .TEXT) {
                        let baseMessage = "external parsed entity does not end in text mode"
                        if let currentExternalParsedEntityURL = currentExternalParsedEntityURLs.last {
                            try error("\(baseMessage): \(currentExternalParsedEntityURL.path)")
                        }
                        else {
                            try error(baseMessage)
                        }
                    }
                    else if elementLevel != oldElementLevel {
                        let baseMessage = "external parsed entity does not return to same element level"
                        if let currentExternalParsedEntityURL = currentExternalParsedEntityURLs.last {
                            try error("\(baseMessage): \(currentExternalParsedEntityURL.path)")
                        }
                        else {
                            try error(baseMessage)
                        }
                    }
                    else if expectedUTF8Rest > 0 {
                        let baseMessage = "external parsed entity has uncomplete UTF-8 codes at the end of file"
                        if let currentExternalParsedEntityURL = currentExternalParsedEntityURLs.last {
                            try error("\(baseMessage): \(currentExternalParsedEntityURL.path)")
                        }
                        else {
                            try error(baseMessage)
                        }
                    }
                    else {
                        binaryPosition += 1
                        if !texts.isEmpty || binaryPosition > parsedBefore {
                            broadcast(
                                endLine: lastLine, endColumn: lastColumn, binaryUntil: binaryPosition
                            ) { (eventHandler,textRange,dataRange) in
                                eventHandler.text(
                                    text: (texts.joined() + (binaryPosition > parsedBefore ? String(decoding: data.subdata(in: parsedBefore..<binaryPosition), as: UTF8.self) : "")).replacingOccurrences(of: "\r\n", with: "\n"),
                                    whitespace: isWhitespace ? .WHITESPACE : .NOT_WHITESPACE,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        texts.removeAll()
                    }
                    switch sleepReason {
                    case .internalSource:  broadcast() { (eventHandler,textRange,dataRange) in eventHandler.leaveInternalDataSource() }
                    case .externalSource:  broadcast() { (eventHandler,textRange,dataRange) in eventHandler.leaveExternalDataSource() }
                    }
                    data = awakenedData
                    activeDataIterator = awakenedDataIterator
                    if sleepReason == .externalSource {
                        _ = currentExternalParsedEntityURLs.popLast()
                    }
                    restoreParsePosition()
                    nextB = activeDataIterator.next()
                }
                else {
                    break binaryLoop
                }
            }
            
            if let b = nextB {
            
                binaryPosition += 1
                
                // check UTF-8 encoding:
                if expectedUTF8Rest > 0 {
                    if b & 0b10000000 == 0 || b & 0b01000000 > 0 {
                        try error("wrong UTF-8 encoding: expecting follow-up byte 10xxxxxx")
                    }
                    codePoint |= UnicodeCodePoint(UInt32(b & 0b00111111) << shift)
                    shift -= 6
                    expectedUTF8Rest -= 1
                }
                else if b & 0b10000000 > 0 {
                    codePoint = 0
                    if b & 0b01000000 > 0 {
                        if b & 0b00100000 == 0 {
                            shift = 6
                            codePoint |= UnicodeCodePoint(UInt32(b & 0b00011111) << shift)
                            shift -= 6
                            expectedUTF8Rest = 1
                            binaryPositionOffset = expectedUTF8Rest
                        }
                        else if b & 0b00010000 == 0 {
                            shift = 12
                            codePoint |= UnicodeCodePoint(UInt32(b & 0b00001111) << shift)
                            shift -= 6
                            expectedUTF8Rest = 2
                            binaryPositionOffset = expectedUTF8Rest
                        }
                        else if b & 0b00001000 == 0 {
                            shift = 18
                            codePoint |= UnicodeCodePoint(UInt32(b & 0b00000111) << shift)
                            shift -= 6
                            expectedUTF8Rest = 3
                            binaryPositionOffset = expectedUTF8Rest
                        }
                        else {
                            try error("wrong UTF-8 encoding: uncorrect leading byte")
                        }
                    }
                    else {
                        try error("wrong UTF-8 encoding: uncorrect leading byte")
                    }
                }
                else {
                    codePoint = UnicodeCodePoint(b)
                    binaryPositionOffset = 0
                }
                
                if expectedUTF8Rest > 0 {
                    continue binaryLoop
                }
                
                if lastCodePoint == U_LINE_FEED {
                    debugWriter?("new line")
                    line += 1
                    column = 0
                }
                
                if let unicodeScalar = UnicodeScalar(codePoint) {
                    let unicodeScalarProperties = unicodeScalar.properties
                    if !(unicodeScalarProperties.isDiacritic || unicodeScalarProperties.isVariationSelector) {
                        column += 1
                    }
                }
                else {
                    try error("x\(String(format: "%X", codePoint)) is not a Unicode codepoint")
                }
                
                if ignoreNextLinebreak == 0 {
                    setMainStart()
                    ignoreNextLinebreak = -1
                }
                
                debugWriter?("@ \(line):\(column) (#\(binaryPosition) in data): \(characterCitation(codePoint)) in \(state) in \(outerState) (whitespace was: \(isWhitespace)), main start: \(mainStartLine):\(mainStartColumn)")
                
                var ignore = false
                
                if ignoreNextLinebreak == 2 {
                    if b == U_LINE_FEED {
                        ignoreNextLinebreak = 0
                        ignore = true
                    }
                    else if b == U_CARRIAGE_RETURN {
                        ignoreNextLinebreak = 1
                        ignore = true
                    }
                    else {
                        ignoreNextLinebreak = 0
                    }
                }
                else if ignoreNextLinebreak == 1 {
                    if b == U_LINE_FEED {
                        ignoreNextLinebreak = 0
                        ignore = true
                    }
                    else {
                        ignoreNextLinebreak = 0
                    }
                }
                else if ignoreNextLinebreak == 0 {
                    ignoreNextLinebreak = -1
                }
                
                if ignore {
                    debugWriter?("ignore!")
                    parsedBefore = binaryPosition + 1
                    setMainStart(delayed: true)
                    lastLastCodePoint = lastCodePoint
                    lastCodePoint = codePoint
                    lastLine = line
                    lastColumn = column
                    continue binaryLoop
                }
                
                switch state {
                /* 1 */
                case .TEXT:
                    switch codePoint {
                    case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                        break
                    case U_QUOTATION_MARK, U_APOSTROPHE:
                        if elementLevel == 0 && outerState == .TEXT {
                            try error("non-whitespace \(characterCitation(codePoint)) outside elements")
                        }
                        else if codePoint == quoteSign {
                            if binaryPosition > parsedBefore {
                                texts.append(String(decoding: data.subdata(in: parsedBefore..<binaryPosition), as: UTF8.self))
                            }
                            if outerState == .START_OR_EMPTY_TAG || outerState == .XML_DECLARATION {
                                if !equalSignAfterToken {
                                    try error("attribute value is not assigned to an attribute name")
                                }
                                else if let theToken = token {
                                    attributes[theToken] = texts.joined()
                                    token = nil
                                }
                            }
                            else {
                                items.append(quotedParseResult(value: texts.joined()))
                                texts.removeAll()
                            }
                            texts.removeAll()
                            quoteSign = 0
                            state = outerState
                            outerState = .TEXT
                            parsedBefore = binaryPosition + 1
                        }
                        else {
                            isWhitespace = false
                        }
                    case U_AMPERSAND:
                        if binaryPosition > parsedBefore {
                            texts.append(String(decoding: data.subdata(in: parsedBefore..<binaryPosition), as: UTF8.self))
                        }
                        state = .ENTITY
                        entityBinaryStart = binaryPosition
                        entityStartLine = line
                        entityStartColumn = column
                        beforeEntityLine = lastLine
                        beforeEntityColumn = lastColumn
                        parsedBefore = binaryPosition + 1
                    case U_LESS_THAN_SIGN:
                        if outerState == .TEXT {
                            if binaryPosition > parsedBefore {
                                texts.append(String(decoding: data.subdata(in: parsedBefore..<binaryPosition), as: UTF8.self))
                            }
                            if !texts.isEmpty {
                                if elementLevel > 0 {
                                    if textAllowedInElementWithName?(ancestors.peek()!) == false {
                                        if !isWhitespace {
                                            try error("non-whitespace #1 text in \(ancestors.elements.joined(separator: " / ")): \"\(formatNonWhitespace(texts.joined()))\"")
                                        }
                                    }
                                    else {
                                        let text = texts.joined().replacingOccurrences(of: "\r\n", with: "\n")
                                        broadcast(
                                            endLine: lastLine, endColumn: lastColumn, binaryUntil: binaryPosition
                                        ) { (eventHandler,textRange,dataRange) in
                                            eventHandler.text(
                                                text: text,
                                                whitespace: isWhitespace ? .WHITESPACE : .NOT_WHITESPACE,
                                                textRange: textRange,
                                                dataRange: dataRange
                                            )
                                        }
                                    }
                                }
                                texts.removeAll()
                            }
                            isWhitespace = true
                            state = .JUST_STARTED_WITH_LESS_THAN_SIGN
                            parsedBefore = binaryPosition + 1
                            setMainStart()
                        }
                        else {
                            try error("illegal \(characterCitation(codePoint))")
                        }
                    default:
                        if elementLevel == 0 && outerState == .TEXT {
                            var whitespaceCheck = true
                            switch binaryPosition {
                            case 0: if b == U_BOM_1 { whitespaceCheck = false }
                            case 1: if b == U_BOM_2 && lastCodePoint == U_BOM_1 { whitespaceCheck = false}
                            case 2: if b == U_BOM_3 && lastCodePoint == U_BOM_2 && lastLastCodePoint == U_BOM_1 { whitespaceCheck = false }
                            default: break
                            }
                            if whitespaceCheck {
                                try error("non-whitespace \(characterCitation(codePoint)) outside elements")
                            }
                        }
                        else {
                            isWhitespace = false
                        }
                    }
                /* 2 */
                case .START_OR_EMPTY_TAG, .XML_DECLARATION:
                        switch codePoint {
                        case U_GREATER_THAN_SIGN:
                            if tokenStart >= 0 {
                                token = String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                                if name == nil {
                                    name = token
                                    token = nil
                                }
                                tokenStart = -1
                            }
                            if state == .XML_DECLARATION {
                                try error("illegal \(characterCitation(codePoint)) in declaration")
                                state = .XML_DECLARATION_FINISHING
                            }
                            else {
                                if name == nil {
                                    try error("missing element name")
                                }
                                if tokenStart >= 0 || token != nil {
                                    try error("misplaced token")
                                    tokenStart = -1
                                    token = nil
                                }
                                if elementLevel == 0 && someElement {
                                    try error("multiple root elements")
                                }
                                if attributes.isEmpty {
                                    broadcast { (eventHandler,textRange,dataRange) in
                                        eventHandler.elementStart(
                                            name: name ?? "",
                                            attributes: nil,
                                            textRange: textRange,
                                            dataRange: dataRange
                                        )
                                    }
                                }
                                else {
                                    broadcast { (eventHandler,textRange,dataRange) in
                                        eventHandler.elementStart(
                                            name: name ?? "",
                                            attributes: attributes,
                                            textRange: textRange,
                                            dataRange: dataRange
                                        )
                                    }
                                    attributes = [String:String]()
                                }
                                someElement = true
                                ancestors.push(name ?? "")
                                elementLevel += 1
                                name = nil
                                state = .TEXT
                                isWhitespace = true
                                parsedBefore = binaryPosition + 1
                                setMainStart(delayed: true)
                            }
                        case U_QUOTATION_MARK, U_APOSTROPHE:
                            if tokenStart > 0 {
                                try error("misplaced attribute value")
                            }
                            quoteSign = b
                            outerState = state
                            state = .TEXT
                            parsedBefore = binaryPosition + 1
                        case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION, U_SOLIDUS, U_QUESTION_MARK:
                            if tokenStart >= 0 {
                                token = texts.joined() + String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                                texts.removeAll()
                                if name == nil {
                                    name = token
                                    token = nil
                                }
                                tokenStart = -1
                            }
                            if state == .START_OR_EMPTY_TAG {
                                if codePoint == U_SOLIDUS {
                                    state = .EMPTY_TAG_FINISHING
                                }
                            }
                            else if codePoint == U_QUESTION_MARK {
                                state = .XML_DECLARATION_FINISHING
                            } else if codePoint == U_SOLIDUS {
                                try error("illegal \(characterCitation(codePoint))")
                            }
                        case U_EQUALS_SIGN:
                            if tokenStart >= 0 {
                                if token != nil {
                                    try error("multiple subsequent tokens")
                                }
                                token = String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                                tokenStart = -1
                            }
                            if token != nil {
                                equalSignAfterToken = true
                            }
                            else {
                                try error("misplaced EQUALS SIGN in start or empty tag")
                            }
                        default:
                            if tokenStart > 0 {
                                if !isNameCharacter(codePoint) {
                                    try error("illegal \(characterCitation(codePoint)) in token")
                                }
                            }
                            else {
                                if !isNameStartCharacter(codePoint) {
                                    try error("illegal \(characterCitation(codePoint)) at start of token")
                                }
                                tokenStart = binaryPosition - binaryPositionOffset
                            }
                        }
                /* 3 */
                case .END_TAG:
                    switch codePoint {
                    case U_GREATER_THAN_SIGN:
                        if tokenStart > 0 {
                            name = String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                            tokenStart = -1
                        }
                        if name == nil {
                            try error("missing element name")
                        }
                        if (name ?? "") != ancestors.peek() {
                            try error("name end tag \"\(name ?? "")\" does not match name of open element \"\(ancestors.peek() ?? "")\"")
                        }
                        broadcast { (eventHandler,textRange,dataRange) in
                            eventHandler.elementEnd(
                                name: name ?? "",
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        _ = ancestors.pop()
                        elementLevel -= 1
                        name = nil
                        state = .TEXT
                        isWhitespace = true
                        parsedBefore = binaryPosition + 1
                        setMainStart(delayed: true)
                    case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                        if tokenStart > 0 {
                            name = String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                            tokenStart = 0
                        }
                        else if name == nil {
                            try error("illegal space at beginning of end tag")
                        }
                    default:
                        if name == nil {
                            if tokenStart > 0 {
                                if !isNameCharacter(codePoint) {
                                    try error("illegal \(characterCitation(codePoint)) in element name")
                                }
                            }
                            else {
                                if !isNameStartCharacter(codePoint) {
                                    try error("illegal \(characterCitation(codePoint)) at start of element name")
                                }
                                tokenStart = binaryPosition - binaryPositionOffset
                            }
                        }
                        else {
                            try error("illegal \(characterCitation(codePoint)) after element name in end tag")
                        }
                    }
                /* 4 */
                case .JUST_STARTED_WITH_LESS_THAN_SIGN:
                    switch codePoint {
                    case U_SOLIDUS:
                        state = .END_TAG
                    case U_EXCLAMATION_MARK:
                        state = .UNKNOWN_DECLARATION_LIKE
                        outerParsedBefore = binaryPosition - 1
                    case U_QUESTION_MARK:
                        state = .PROCESSING_INSTRUCTION
                    default:
                        if isNameStartCharacter(codePoint) {
                            tokenStart = binaryPosition - binaryPositionOffset
                        }
                        else {
                            try error("illegal \(characterCitation(codePoint)) after \"<\"")
                        }
                        state = .START_OR_EMPTY_TAG
                    }
                /* 5 */
                case .ENTITY:
                    if codePoint == U_SEMICOLON {
                        let entityText = String(decoding: data.subdata(in: parsedBefore..<binaryPosition), as: UTF8.self)
                        if elementLevel == 0 && outerState == .TEXT {
                            try error("entity \"\(entityText)\" outside elements")
                        }
                        var resolution: String? = nil
                        var isExternal = false
                        switch entityText {
                        case "amp": resolution = "&"
                        case "lt": resolution = "<"
                        case "gt": resolution = ">"
                        case "apos": resolution = "'"
                        case "quot": resolution = "\""
                        default:
                            if entityText.starts(with: "#") {
                                var _uni: UnicodeScalar? = nil
                                let _codepoint = entityText.starts(with: "#x") ? Int(entityText.dropFirst(2), radix: 16) : Int(entityText.dropFirst(1), radix: 10)
                                if let codepoint = _codepoint {
                                    _uni = UnicodeScalar(codepoint)
                                }
                                if let uni = _uni {
                                    resolution = String(uni)
                                }
                                else {
                                    try error("numerical character reference &\(entityText); does not correspond to a valid Unicode codepoint")
                                }
                            }
                            else if outerState == .ENTITY_DECLARATION {
                                resolution = "&\(entityText);"
                            }
                            else {
                                isExternal = externalEntityNames.contains(entityText)
                                if !isExternal {
                                    if internalEntityAutoResolve, let autoResolutionData = internalEntityDatas[entityText] {
                                        if !texts.isEmpty {
                                            broadcast(
                                                endLine: beforeEntityLine, endColumn: beforeEntityColumn, binaryUntil: parsedBefore - 1
                                            ) { (eventHandler,textRange,dataRange) in
                                                eventHandler.text(
                                                    text: texts.joined().replacingOccurrences(of: "\r\n", with: "\n"),
                                                    whitespace: isWhitespace ? .WHITESPACE : .NOT_WHITESPACE,
                                                    textRange: textRange,
                                                    dataRange: dataRange
                                                )
                                            }
                                            texts.removeAll()
                                            
                                        }
                                        broadcast() { (eventHandler,textRange,dataRange) in
                                            eventHandler.enterInternalDataSource(data: autoResolutionData, entityName: entityText, textRange: textRange, dataRange: dataRange)
                                        }
                                        parsedBefore = binaryPosition + 1
                                        state = .TEXT
                                        setMainStart(delayed: true)
                                        startNewData(newData: autoResolutionData, dataSourceType: .internalSource)
                                        continue binaryLoop
                                    }
                                    else if let theInternalEntityResolver = internalEntityResolver {
                                        if outerState == .START_OR_EMPTY_TAG {
                                            if name == nil {
                                                try error("missing element name")
                                            }
                                            if token == nil {
                                                try error("missing attribute name")
                                            }
                                        }
                                        resolution = theInternalEntityResolver.resolve(entityWithName: entityText, forAttributeWithName: token, atElementWithName: name)
                                    }
                                }
                            }
                        }
                        if let theResolution = resolution {
                            texts.append(theResolution)
                            whitespaceTest: for c in theResolution {
                                if !(c == C_SPACE || c == C_LINE_FEED || c == C_CARRIAGE_RETURN || c == C_CHARACTER_TABULATION) {
                                    isWhitespace = false
                                    break whitespaceTest
                                }
                            }
                            state = .TEXT
                            parsedBefore = binaryPosition + 1
                        }
                        else if outerState == .TEXT || outerState == .ENTITY_DECLARATION {
                            if !texts.isEmpty {
                                let text = texts.joined()
                                if elementLevel > 0 {
                                    if textAllowedInElementWithName?(ancestors.peek()!) == false {
                                        if !isWhitespace {
                                            try error("non-whitespace #2 text in \(ancestors.elements.joined(separator: " / ")): \"\(formatNonWhitespace(text))\"")
                                        }
                                    }
                                    else {
                                        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
                                        broadcast(
                                            endLine: beforeEntityLine, endColumn: beforeEntityColumn, binaryUntil: entityBinaryStart
                                        ) { (eventHandler,textRange,dataRange) in
                                            eventHandler.text(
                                                text: text,
                                                whitespace: isWhitespace ? .WHITESPACE : .NOT_WHITESPACE,
                                                textRange: textRange,
                                                dataRange: dataRange
                                            )
                                        }
                                    }
                                }
                                texts.removeAll()
                                isWhitespace = true
                            }
                            mainParsedBefore = entityBinaryStart
                            mainStartLine = entityStartLine
                            mainStartColumn = entityStartColumn
                            if isExternal {
                                if insertExternalParsedEntities, let externalParsedEntityPath = externalParsedEntityPaths[entityText],
                                let theSourceURL = directoryURL {
                                    
                                    let url = theSourceURL.appendingPathComponent(externalParsedEntityPath)
                                    currentExternalParsedEntityURLs.append(url)
                                    let path = url.path
                                    
                                    let newData = try Data(contentsOf: URL(fileURLWithPath: path))
                                    
                                    broadcast() { (eventHandler,textRange,dataRange) in
                                        eventHandler.enterExternalDataSource(data: newData, entityName: entityText, url: url, textRange: textRange, dataRange: dataRange)
                                    }
                                    
                                    parsedBefore = binaryPosition + 1
                                    state = .TEXT
                                    setMainStart(delayed: true)
                                    startNewData(newData: newData, dataSourceType: .externalSource)
                                }
                                else {
                                    broadcast { (eventHandler,textRange,dataRange) in
                                        eventHandler.externalEntity(
                                            name: entityText,
                                            textRange: textRange,
                                            dataRange: dataRange
                                        )
                                    }
                                    parsedBefore = binaryPosition + 1
                                    state = .TEXT
                                    setMainStart(delayed: true)
                                }
                            }
                            else {
                                broadcast { (eventHandler,textRange,dataRange) in
                                    eventHandler.internalEntity(
                                        name: entityText,
                                        textRange: textRange,
                                        dataRange: dataRange
                                    )
                                }
                                parsedBefore = binaryPosition + 1
                                state = .TEXT
                                setMainStart(delayed: true)
                            }
                        }
                        else {
                            let descriptionStart = isExternal ? "misplaced external" : "remaining internal"
                            if outerState == .START_OR_EMPTY_TAG, let theElementName = name, let theAttributeName = token {
                                try error("\(descriptionStart) entity \"\(entityText)\" in attribute \"\(theAttributeName)\" of element \"\(theElementName)\"")
                            }
                            else {
                                try error("\(descriptionStart) entity \"\(entityText)\" in strictly textual content")
                            }
                        }
                    }
                /* 6 */
                case .EMPTY_TAG_FINISHING:
                    if codePoint == U_GREATER_THAN_SIGN {
                        if name == nil {
                            try error("missing element name")
                        }
                        if token != nil {
                            try error("misplaced token")
                            token = nil
                        }
                        if elementLevel == 0 && someElement {
                            try error("multiple root elements")
                        }
                        if attributes.isEmpty {
                            broadcast { (eventHandler,textRange,dataRange) in
                                eventHandler.elementStart(
                                    name: name ?? "",
                                    attributes: nil,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            broadcast { (eventHandler,textRange,dataRange) in
                                eventHandler.elementStart(
                                    name: name ?? "",
                                    attributes: attributes,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                            attributes = [String:String]()
                        }
                        broadcast { (eventHandler,textRange,dataRange) in
                            eventHandler.elementEnd(
                                name: name ?? "",
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        someElement = true
                        name = nil
                        state = .TEXT
                        isWhitespace = true
                        parsedBefore = binaryPosition + 1
                        setMainStart(delayed: true)
                    }
                    else {
                        try error("expecting \(characterCitation(U_GREATER_THAN_SIGN)) to end empty tag")
                    }
                /* 7 */
                case .PROCESSING_INSTRUCTION:
                    if tokenStart > -1 && !isNameCharacter(codePoint) {
                        name =  String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                        tokenStart = -1
                        tokenEnd = binaryPosition
                        parsedBefore = binaryPosition + 1
                        if name == "xml" {
                            if codePoint == U_SPACE || codePoint == U_LINE_FEED || codePoint == U_CARRIAGE_RETURN || codePoint == U_CHARACTER_TABULATION {
                                state = .XML_DECLARATION
                            }
                        }
                    }
                    else if codePoint == U_GREATER_THAN_SIGN && lastCodePoint == U_QUESTION_MARK {
                        if tokenStart > -1 {
                            name =  String(decoding: data.subdata(in: tokenStart..<binaryPosition-1), as: UTF8.self)
                            tokenStart = -1
                        }
                        if let target = name {
                            if name == "xml" {
                                try error("found XML declaration without version")
                            }
                            else {
                                let data = parsedBefore<binaryPosition-1 ? String(decoding: data.subdata(in: parsedBefore..<binaryPosition-1), as: UTF8.self): nil
                                broadcast { (eventHandler,textRange,dataRange) in
                                    eventHandler.processingInstruction(
                                        target: target,
                                        data: data,
                                        textRange: textRange,
                                        dataRange: dataRange
                                    )
                                }
                            }
                            name = nil
                        }
                        else {
                            try error("procesing instruction without target")
                        }
                        parsedBefore = binaryPosition + 1
                        setMainStart(delayed: true)
                        state = outerState
                        outerState = .TEXT
                    }
                    /*else if codePoint == U_QUESTION_MARK && lastCodePoint == U_LESS_THAN_SIGN {
                        try error("beginning of another processing instruction inside a processing instruction", negativeColumnOffset: 1)
                    }*/ // is allowed see https://www.w3.org/TR/xml/#sec-pi
                    else {
                        if name == nil {
                            if tokenStart < 0 {
                                if !isNameStartCharacter(codePoint) {
                                    try error("illegal character at start of processing instruction")
                                }
                                tokenStart = binaryPosition - binaryPositionOffset
                            }
                        }
                        else if binaryPosition == tokenEnd + 1 {
                            if !(lastCodePoint == U_SPACE || lastCodePoint == U_LINE_FEED || lastCodePoint == U_CARRIAGE_RETURN || lastCodePoint == U_CHARACTER_TABULATION) {
                                try error("missing space after target in processing instruction")
                            }
                        }
                    }
                /* 8 */
                case .CDATA_SECTION:
                    switch codePoint {
                    case U_GREATER_THAN_SIGN:
                        if lastCodePoint == U_RIGHT_SQUARE_BRACKET && lastLastCodePoint == U_RIGHT_SQUARE_BRACKET {
                            let text = String(decoding: data.subdata(in: parsedBefore..<binaryPosition-2), as: UTF8.self)
                            broadcast { (eventHandler,textRange,dataRange) in
                                eventHandler.cdataSection(
                                    text: text,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                            parsedBefore = binaryPosition + 1
                            setMainStart()
                            state = outerState
                            outerState = .TEXT
                        }
                    default:
                        break
                    }
                /* 9 */
                case .COMMENT:
                    if parsedBefore <= binaryPosition - 2 {
                        switch codePoint {
                        case U_GREATER_THAN_SIGN:
                            if lastCodePoint == U_HYPHEN_MINUS && lastLastCodePoint == U_HYPHEN_MINUS {
                                let text = String(decoding: data.subdata(in: parsedBefore..<binaryPosition-2), as: UTF8.self)
                                broadcast { (eventHandler,textRange,dataRange) in
                                    eventHandler.comment(
                                        text: text,
                                        textRange: textRange,
                                        dataRange: dataRange
                                    )
                                }
                                parsedBefore = binaryPosition + 1
                                setMainStart()
                                state = outerState
                                outerState = .TEXT
                            }
                        default:
                            if lastCodePoint == U_HYPHEN_MINUS && lastLastCodePoint == U_HYPHEN_MINUS && binaryPosition > parsedBefore {
                                try error("\"--\" in comment not marking the end of it")
                            }
                        }
                    }
                /* 10 */
                case .DOCUMENT_TYPE_DECLARATION_HEAD, .ENTITY_DECLARATION, .NOTATION_DECLARATION:
                    switch codePoint {
                    case U_LEFT_SQUARE_BRACKET, U_GREATER_THAN_SIGN:
                        if codePoint == U_LEFT_SQUARE_BRACKET && !(state == .DOCUMENT_TYPE_DECLARATION_HEAD) {
                            try error("illegal character \(characterCitation(codePoint))")
                            break
                        }
                        if tokenStart >= 0 {
                            items.append(tokenParseResult(value: String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)))
                            tokenStart = -1
                        }
                        
                        switch state {
                        case .DOCUMENT_TYPE_DECLARATION_HEAD:
                            if someElement {
                                try error("document type declaration after root element")
                            }
                            else if someDocumentTypeDeclaration  {
                                try error("multiple document type declarations")
                            }
                            if !items.isEmpty, let name = (items[0] as? tokenParseResult)?.value {
                                var success = false
                                if items.count >= 3, let theToken = (items[1] as? tokenParseResult)?.value {
                                    if theToken == "SYSTEM" {
                                        if items.count == 3,
                                           let publicID = (items[2] as? quotedParseResult)?.value
                                        {
                                            broadcast { (eventHandler,textRange,dataRange) in
                                                eventHandler.documentTypeDeclarationStart(
                                                    type: name,
                                                    publicID: publicID,
                                                    systemID: nil,
                                                    textRange: textRange,
                                                    dataRange: dataRange
                                                )
                                            }
                                            success = true
                                        }
                                    }
                                    else if theToken == "PUBLIC" {
                                        if items.count == 3 {
                                            if let publicID = (items[2] as? quotedParseResult)?.value
                                               {
                                                broadcast { (eventHandler,textRange,dataRange) in
                                                    eventHandler.documentTypeDeclarationStart(
                                                        type: name,
                                                        publicID: publicID,
                                                        systemID:  nil,
                                                        textRange: textRange,
                                                        dataRange: dataRange
                                                    )
                                                }
                                                success = true
                                            }
                                        }
                                        else if items.count == 4 {
                                            if let publicID = (items[2] as? quotedParseResult)?.value,
                                               let systemID = (items[3] as? quotedParseResult)?.value
                                            {
                                                broadcast { (eventHandler,textRange,dataRange) in
                                                    eventHandler.documentTypeDeclarationStart(
                                                        type: name,
                                                        publicID: publicID,
                                                        systemID: systemID,
                                                        textRange: textRange,
                                                        dataRange: dataRange
                                                    )
                                                }
                                                success = true
                                            }
                                        }
                                    }
                                }
                                else {
                                    broadcast { (eventHandler,textRange,dataRange) in
                                        eventHandler.documentTypeDeclarationStart(
                                            type: name,
                                            publicID: nil,
                                            systemID: nil,
                                            textRange: textRange,
                                            dataRange: dataRange
                                        )
                                    }
                                    success = true
                                }
                                if !success {
                                    try error("incorrect document type declaration")
                                }
                                someDocumentTypeDeclaration = true
                            }
                            else {
                                try error("missing type in document type declaration")
                            }
                            if codePoint == U_GREATER_THAN_SIGN {
                                broadcast { (eventHandler,textRange,dataRange) in
                                    eventHandler.documentTypeDeclarationEnd(
                                        textRange: textRange,
                                        dataRange: dataRange
                                    )
                                }
                                state = .TEXT
                            }
                            else {
                                state = .INTERNAL_SUBSET
                            }
                        case .ENTITY_DECLARATION:
                            var success = false
                            if !items.isEmpty, let entityName = (items[0] as? tokenParseResult)?.value {
                                if entityName.hasPrefix("%") {
                                    if entityName.count > 1 {
                                        try error("illegal \(characterCitation(U_PERCENT_SIGN)) in declaration")
                                    }
                                    if items.count == 3,
                                       let realEntityName = (items[1] as? tokenParseResult)?.value,
                                       let value = (items[2] as? quotedParseResult)?.value {
                                        if declaredParameterEntityNames.contains(realEntityName) {
                                            try error("parameter entity with name \"\(realEntityName)\" declared more than once")
                                        }
                                        broadcast { (eventHandler,textRange,dataRange) in
                                            eventHandler.parameterEntityDeclaration(
                                                name: realEntityName,
                                                value: value,
                                                textRange: textRange,
                                                dataRange: dataRange
                                            )
                                        }
                                        declaredParameterEntityNames.insert(realEntityName)
                                        success = true
                                    }
                                }
                                else if items.count == 2 {
                                    if let value = (items[1] as? quotedParseResult)?.value {
                                        if declaredEntityNames.contains(entityName) {
                                            try error("entity with name \"\(entityName)\" declared more than once")
                                        }
                                        if internalEntityAutoResolve {
                                            internalEntityDatas[entityName] = value.data(using: .utf8)
                                        }
                                        broadcast { (eventHandler,textRange,dataRange) in
                                            eventHandler.internalEntityDeclaration(
                                                name: entityName,
                                                value: value,
                                                textRange: textRange,
                                                dataRange: dataRange
                                            )
                                        }
                                        declaredEntityNames.insert(entityName)
                                        success = true
                                    }
                                }
                                else {
                                    let hasPublicToken = items.count >= 2 && (items[1] as? tokenParseResult)?.value == "PUBLIC"
                                    let hasSystemToken = items.count >= 2 && (items[1] as? tokenParseResult)?.value == "SYSTEM"
                                    let systemShift = hasPublicToken ? 1 : 0
                                    if hasPublicToken || hasSystemToken,
                                       items.count >= 3 + systemShift,
                                       let systemValue = (items[2 + systemShift] as? quotedParseResult)?.value
                                    {
                                        var publicValue: String? = nil
                                        if hasPublicToken, let _publicValue = (items[2] as? quotedParseResult)?.value {
                                            publicValue = _publicValue
                                        }
                                        if !hasPublicToken || publicValue != nil {
                                            if items.count == 5 + systemShift {
                                                if (items[3 + systemShift] as? tokenParseResult)?.value == "NDATA",
                                                   let notation = items[4 + systemShift] as? tokenParseResult {
                                                    if declaredEntityNames.contains(entityName) {
                                                        try error("entity with name \"\(entityName)\" declared more than once")
                                                    }
                                                    broadcast { (eventHandler,textRange,dataRange) in
                                                        eventHandler.unparsedEntityDeclaration(
                                                            name: entityName,
                                                            publicID: publicValue,
                                                            systemID: systemValue,
                                                            notation: notation.value,
                                                            textRange: textRange,
                                                            dataRange: dataRange
                                                        )
                                                    }
                                                    externalEntityNames.insert(entityName)
                                                    declaredEntityNames.insert(entityName)
                                                    success = true
                                                }
                                            }
                                            else if items.count == 3 + systemShift {
                                                if declaredEntityNames.contains(entityName) {
                                                    try error("entity with name \"\(entityName)\" declared more than once")
                                                }
                                                externalParsedEntityPaths[entityName] = systemValue
                                                broadcast { (eventHandler,textRange,dataRange) in
                                                    eventHandler.externalEntityDeclaration(
                                                        name: entityName,
                                                        publicID: publicValue,
                                                        systemID: systemValue,
                                                        textRange: textRange,
                                                        dataRange: dataRange
                                                    )
                                                }
                                                externalEntityNames.insert(entityName)
                                                declaredEntityNames.insert(entityName)
                                                success = true
                                            }
                                        }
                                    }
                                }
                            }
                            if (!success) {
                                try error("incorrect entity declaration")
                            }
                            state = .INTERNAL_SUBSET
                            outerState = .TEXT
                            parsedBefore = binaryPosition + 1
                            setMainStart()
                        case .NOTATION_DECLARATION:
                            var success = false
                            if !items.isEmpty, let notationName = (items[0] as? tokenParseResult)?.value {
                                let hasPublicToken = items.count >= 2 && (items[1] as? tokenParseResult)?.value == "PUBLIC"
                                let hasSystemToken = items.count >= 2 && (items[1] as? tokenParseResult)?.value == "SYSTEM"
                                if hasPublicToken || hasSystemToken {
                                    if items.count == 4 {
                                        if hasPublicToken,
                                           let publicValue = (items[2] as? quotedParseResult)?.value,
                                           let systemValue = (items[3] as? quotedParseResult)?.value
                                        {
                                            if declaredNotationNames.contains(notationName) {
                                                try error("notation \"\(notationName)\" declared more than once")
                                            }
                                            broadcast { (eventHandler,textRange,dataRange) in
                                                eventHandler.notationDeclaration(
                                                    name: notationName,
                                                    publicID: publicValue,
                                                    systemID: systemValue,
                                                    textRange: textRange,
                                                    dataRange: dataRange
                                                )
                                            }
                                            declaredNotationNames.insert(notationName)
                                            success = true
                                        }
                                    }
                                    else if items.count == 3 {
                                        if let publicOrSystemValue = (items[2] as? quotedParseResult)?.value
                                        {
                                            if declaredNotationNames.contains(notationName) {
                                                try error("notation \"\(notationName)\" declared more than once")
                                            }
                                            if hasPublicToken {
                                                broadcast { (eventHandler,textRange,dataRange) in
                                                    eventHandler.notationDeclaration(
                                                        name: notationName,
                                                        publicID: publicOrSystemValue,
                                                        systemID: nil,
                                                        textRange: textRange,
                                                        dataRange: dataRange
                                                    )
                                                }
                                            }
                                            else {
                                                broadcast { (eventHandler,textRange,dataRange) in
                                                    eventHandler.notationDeclaration(
                                                        name: notationName,
                                                        publicID: nil,
                                                        systemID: publicOrSystemValue,
                                                        textRange: textRange,
                                                        dataRange: dataRange
                                                    )
                                                }
                                            }
                                            declaredNotationNames.insert(notationName)
                                            success = true
                                        }
                                    }
                                }
                                state = .INTERNAL_SUBSET
                            }
                            if !success {
                                try error("incorrect notation declaration")
                            }
                            parsedBefore = binaryPosition + 1
                            setMainStart()
                        default:
                            try error("fatal program error: unexpected state")
                        }
                        items.removeAll()
                        parsedBefore = binaryPosition + 1
                    case U_QUOTATION_MARK, U_APOSTROPHE:
                        if tokenStart >= 0 {
                            try error("illegal \(characterCitation(codePoint))")
                            items.append(tokenParseResult(value: String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)))
                            tokenStart = -1
                        }
                        quoteSign = b
                        parsedBefore = binaryPosition + 1
                        outerState = state
                        state = .TEXT
                    case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                        if tokenStart >= 0 {
                            items.append(tokenParseResult(value: String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)))
                            tokenStart = -1
                        }
                    default:
                        if tokenStart > 0 {
                            if !isNameCharacter(codePoint) {
                                try error("illegal \(characterCitation(codePoint)) in element name")
                            }
                        }
                        else {
                            if !(isNameStartCharacter(codePoint) || (state == .ENTITY_DECLARATION && codePoint == U_PERCENT_SIGN && items.count == 0)) {
                                try error("illegal \(characterCitation(codePoint)) in declaration")
                            }
                            tokenStart = binaryPosition - binaryPositionOffset
                        }
                    }
                /* 11 */
                case .UNKNOWN_DECLARATION_LIKE:
                    switch unkownDeclarationOffset {
                    case 0:
                        if possibleState & _ENTITY_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_E {
                            possibleState ^= _ENTITY_DECLARATION
                        }
                        if possibleState & _COMMENT > 0 && codePoint != U_HYPHEN_MINUS {
                            possibleState ^= _COMMENT
                        }
                        if possibleState & _CDATA_SECTION > 0 && codePoint != U_LEFT_SQUARE_BRACKET {
                            possibleState ^= _CDATA_SECTION
                        }
                        if possibleState & _NOTATION_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_N {
                            possibleState ^= _NOTATION_DECLARATION
                        }
                        if possibleState & _ELEMENT_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_E {
                            possibleState ^= _ELEMENT_DECLARATION
                        }
                        if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_A {
                            possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                        }
                        if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && codePoint != U_LATIN_CAPITAL_LETTER_D {
                            possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                        }
                    case 1:
                        if possibleState & _ENTITY_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_N {
                            possibleState ^= _ENTITY_DECLARATION
                        }
                        if possibleState & _COMMENT > 0 {
                            if codePoint == U_HYPHEN_MINUS {
                                state = .COMMENT
                            }
                            else {
                                possibleState ^= _COMMENT
                            }
                        }
                        if possibleState & _CDATA_SECTION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_C {
                            possibleState ^= _CDATA_SECTION
                        }
                        if possibleState & _NOTATION_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_O {
                            possibleState ^= _NOTATION_DECLARATION
                        }
                        if possibleState & _ELEMENT_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_L {
                            possibleState ^= _ELEMENT_DECLARATION
                        }
                        if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                        }
                        if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && codePoint != U_LATIN_CAPITAL_LETTER_O {
                            possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                        }
                    case 2:
                        if possibleState & _CDATA_SECTION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_D {
                            possibleState ^= _CDATA_SECTION
                        }
                        if possibleState & _ENTITY_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _ENTITY_DECLARATION
                        }
                        if possibleState & _NOTATION_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _NOTATION_DECLARATION
                        }
                        if possibleState & _ELEMENT_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_E {
                            possibleState ^= _ELEMENT_DECLARATION
                        }
                        if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                        }
                        if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && codePoint != U_LATIN_CAPITAL_LETTER_C {
                            possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                        }
                    case 3:
                        if possibleState & _CDATA_SECTION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_A {
                            possibleState ^= _CDATA_SECTION
                        }
                        if possibleState & _ENTITY_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_I {
                            possibleState ^= _ENTITY_DECLARATION
                        }
                        if possibleState & _NOTATION_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_A {
                            possibleState ^= _NOTATION_DECLARATION
                        }
                        if possibleState & _ELEMENT_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_M {
                            possibleState ^= _ELEMENT_DECLARATION
                        }
                        if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_L {
                            possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                        }
                        if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                        }
                    case 4:
                        if possibleState & _CDATA_SECTION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _CDATA_SECTION
                        }
                        if possibleState & _ENTITY_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _ENTITY_DECLARATION
                        }
                        if possibleState & _NOTATION_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _NOTATION_DECLARATION
                        }
                        if possibleState & _ELEMENT_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_E {
                            possibleState ^= _ELEMENT_DECLARATION
                        }
                        if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_I {
                            possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                        }
                        if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && codePoint != U_LATIN_CAPITAL_LETTER_Y {
                            possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                        }
                    case 5:
                        if possibleState & _CDATA_SECTION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_A {
                            possibleState ^= _CDATA_SECTION
                        }
                        if possibleState & _ENTITY_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_Y {
                            possibleState ^= _ENTITY_DECLARATION
                        }
                        if possibleState & _NOTATION_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_I {
                            possibleState ^= _NOTATION_DECLARATION
                        }
                        if possibleState & _ELEMENT_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_N {
                            possibleState ^= _ELEMENT_DECLARATION
                        }
                        if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_S {
                            possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                        }
                        if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && codePoint != U_LATIN_CAPITAL_LETTER_P {
                            possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                        }
                    case 6:
                        if possibleState & _CDATA_SECTION > 0 {
                            if codePoint == U_LEFT_SQUARE_BRACKET {
                                state = .CDATA_SECTION
                                break
                            }
                            else {
                                possibleState ^= _CDATA_SECTION
                            }
                        }
                        if possibleState & _ENTITY_DECLARATION > 0 {
                            if codePoint == U_SPACE || codePoint == U_LINE_FEED || codePoint == U_CARRIAGE_RETURN || codePoint == U_CHARACTER_TABULATION {
                                state = .ENTITY_DECLARATION
                                break
                            }
                            else {
                                possibleState ^= _ENTITY_DECLARATION
                            }
                        }
                        if possibleState & _NOTATION_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_O {
                            possibleState ^= _NOTATION_DECLARATION
                        }
                        if possibleState & _ELEMENT_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _ELEMENT_DECLARATION
                        }
                        if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_T {
                            possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                        }
                        if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && codePoint != U_LATIN_CAPITAL_LETTER_E {
                            possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                        }
                    case 7:
                        if possibleState & _NOTATION_DECLARATION > 0 && codePoint != U_LATIN_CAPITAL_LETTER_N {
                            possibleState ^= _NOTATION_DECLARATION
                        }
                        if possibleState & _ELEMENT_DECLARATION > 0 {
                            if codePoint == U_SPACE || codePoint == U_LINE_FEED || codePoint == U_CARRIAGE_RETURN || codePoint == U_CHARACTER_TABULATION {
                                state = .ELEMENT_DECLARATION
                                break
                            }
                            else {
                                possibleState ^= _ELEMENT_DECLARATION
                            }
                        }
                        if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 {
                            if codePoint == U_SPACE || codePoint == U_LINE_FEED || codePoint == U_CARRIAGE_RETURN || codePoint == U_CHARACTER_TABULATION {
                                state = .ATTRIBUTE_LIST_DECLARATION
                                break
                            }
                            else {
                                possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                            }
                        }
                        if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 {
                            if codePoint == U_SPACE || codePoint == U_LINE_FEED || codePoint == U_CARRIAGE_RETURN || codePoint == U_CHARACTER_TABULATION {
                                state = .DOCUMENT_TYPE_DECLARATION_HEAD
                                break
                            }
                            else {
                                possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                            }
                        }
                    case 8:
                        if possibleState & _NOTATION_DECLARATION > 0 {
                            if codePoint == U_SPACE || codePoint == U_LINE_FEED || codePoint == U_CARRIAGE_RETURN || codePoint == U_CHARACTER_TABULATION {
                                state = .NOTATION_DECLARATION
                                break
                            }
                            else {
                                possibleState ^= _NOTATION_DECLARATION
                            }
                        }
                    default:
                        break
                    }
                    if state == .UNKNOWN_DECLARATION_LIKE {
                        if possibleState & _DECLARATION_LIKE == _EMPTY {
                            try error("incorrect declaration")
                        }
                        unkownDeclarationOffset += 1
                    }
                    else {
                        possibleState = _DECLARATION_LIKE
                        unkownDeclarationOffset = 0
                    }
                    parsedBefore = binaryPosition + 1
                /* 12 */
                case .INTERNAL_SUBSET:
                    switch codePoint {
                    case U_RIGHT_SQUARE_BRACKET:
                        state = .DOCUMENT_TYPE_DECLARATION_TAIL
                        parsedBefore = binaryPosition + 1
                        setMainStart()
                    case U_LESS_THAN_SIGN:
                        state = .JUST_STARTED_WITH_LESS_THAN_SIGN
                        outerState = .INTERNAL_SUBSET
                        parsedBefore = binaryPosition + 1
                        setMainStart()
                    case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION, U_SOLIDUS:
                        if lastCodePoint == U_LESS_THAN_SIGN {
                            try error("illegal \(U_LESS_THAN_SIGN) in internal subset")
                        }
                    default:
                        if lastCodePoint == U_LESS_THAN_SIGN {
                            try error("illegal \(U_LESS_THAN_SIGN) in internal subset")
                        }
                        try error("illegal \(characterCitation(codePoint)) in internal subset")
                    }
                /* 13 */
                case .ELEMENT_DECLARATION, .ATTRIBUTE_LIST_DECLARATION:
                    switch codePoint {
                    case U_LEFT_PARENTHESIS:
                        if quoteSign == 0 && tokenStart >= 0 {
                            token = String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                            tokenStart = -1
                        }
                    case U_GREATER_THAN_SIGN:
                        if quoteSign == 0 {
                            if tokenStart >= 0 {
                                token = String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                                tokenStart = -1
                            }
                            if state == .ELEMENT_DECLARATION {
                                if outerState != .INTERNAL_SUBSET {
                                    try error("element declaration outside internal subset")
                                }
                                if let theToken = token {
                                    if declaredElementNames.contains(theToken) {
                                        try error("element type \"\(theToken)\" declared more than once")
                                    }
                                    let literal = String(decoding: data.subdata(in: outerParsedBefore..<binaryPosition+1), as: UTF8.self)
                                    broadcast { (eventHandler,textRange,dataRange) in
                                        eventHandler.elementDeclaration(
                                            name: theToken,
                                            literal: literal,
                                            textRange: textRange,
                                            dataRange: dataRange
                                        )
                                    }
                                    declaredElementNames.insert(theToken)
                                }
                                else {
                                    try error("element declaration without name")
                                }
                                token = nil
                            }
                            else {
                                if outerState != .INTERNAL_SUBSET {
                                    try error("attribute list declaration outside internal subset")
                                }
                                if let theToken = token {
                                    if declaredAttributeListNames.contains(theToken) {
                                        try error("attribute list for element type \"\(theToken)\" declared more than once")
                                    }
                                    let literal = String(decoding: data.subdata(in: outerParsedBefore..<binaryPosition+1), as: UTF8.self)
                                    broadcast { (eventHandler,textRange,dataRange) in
                                        eventHandler.attributeListDeclaration(
                                            name: theToken,
                                            literal: literal,
                                            textRange: textRange,
                                            dataRange: dataRange
                                        )
                                    }
                                    declaredAttributeListNames.insert(theToken)
                                }
                                else {
                                    try error("attribute list declaration without name")
                                }
                                
                                token = nil
                            }
                            parsedBefore = binaryPosition + 1
                            state = outerState; outerState = .TEXT
                        }
                    case U_QUOTATION_MARK, U_APOSTROPHE:
                        if codePoint == quoteSign {
                            quoteSign = 0
                        }
                        else {
                            if tokenStart >= 0 {
                                token = String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                                tokenStart = -1
                            }
                            quoteSign = b
                        }
                    case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                        if tokenStart >= 0 {
                            token = String(decoding: data.subdata(in: tokenStart..<binaryPosition), as: UTF8.self)
                            tokenStart = -1
                        }
                    default:
                        if token == nil && tokenStart < 0 {
                            tokenStart = binaryPosition - binaryPositionOffset
                        }
                    }
                /* 14 */
                case .XML_DECLARATION_FINISHING:
                    if codePoint == U_GREATER_THAN_SIGN {
                        let correctPlacedInExternalEntity = !sleepingParsingDatas.isEmpty && mainParsedBefore == 0
                        if !correctPlacedInExternalEntity && (someDocumentTypeDeclaration || someElement) {
                            try error("misplaced XML declaration")
                        }
                        if token != nil {
                            try error("misplaced token")
                            token = nil
                        }
                        var version: String? = nil
                        var encoding: String? = nil
                        var standalone: String? = nil
                        try attributes.forEach { attributeName, attributeValue in
                            switch attributeName {
                            case "version": version = attributeValue
                            case "encoding": encoding = attributeValue
                            case "standalone": standalone = attributeValue
                            default: try error("unkonwn attribute \"\(attributeName)\" in XML declaration")
                            }
                        }
                        if correctPlacedInExternalEntity {
                            if let theEncoding = encoding, !["ascii", "us-ascii", "utf8", "utf-8"].contains(theEncoding.lowercased()) {
                                let baseMessage = "uncorrect encoding \"\(theEncoding)\" noted via text declaration in external parsed entity"
                                if let currentExternalParsedEntityURL = currentExternalParsedEntityURLs.last {
                                    try error("\(baseMessage): \(currentExternalParsedEntityURL.path)")
                                }
                                else {
                                    try error(baseMessage)
                                }
                            }
                            ignoreNextLinebreak = 2
                        }
                        else if let theVersion = version {
                            broadcast { (eventHandler,textRange,dataRange) in
                                eventHandler.xmlDeclaration(
                                    version: theVersion,
                                    encoding: encoding,
                                    standalone: standalone,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            try error("uncomplete XML declaration, at least the version should be set")
                        }
                        name = nil
                        attributes = [String:String]()
                        state = .TEXT
                        isWhitespace = true
                        parsedBefore = binaryPosition + 1
                        setMainStart(delayed: true)
                    }
                    else {
                        try error("expecting \(characterCitation(U_GREATER_THAN_SIGN)) to end XML declaration")
                    }
                /* 15 */
                case .DOCUMENT_TYPE_DECLARATION_TAIL:
                    switch codePoint {
                    case U_GREATER_THAN_SIGN:
                        broadcast { (eventHandler,textRange,dataRange) in
                            eventHandler.documentTypeDeclarationEnd(
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        state = .TEXT
                        isWhitespace = true
                        parsedBefore = binaryPosition + 1
                    case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION, U_SOLIDUS:
                        break
                    default:
                        try error("illegal \(characterCitation(codePoint)) in document type declaration after internal subset")
                    }
                }
                
                lastLastCodePoint = lastCodePoint
                lastCodePoint = codePoint
                lastLine = line
                lastColumn = column
            }
            else {
                break binaryLoop
            }
        }
        binaryPosition += 1
        column += 1
        
        if elementLevel > 0 {
            try error("document is not finished: \(elementLevel > 1 ? "elements" : "element") \(ancestors.peekAll().reversed().map{ "\"\($0)\"" }.joined(separator: ", ")) \(elementLevel > 1 ? "are" : "is") not closed")
        }
        else if state != .TEXT {
            try error("junk at end of document")
        }
        
        broadcast { (eventHandler,textRange,dataRange) in
            eventHandler.documentEnd()
        }
    }
}
