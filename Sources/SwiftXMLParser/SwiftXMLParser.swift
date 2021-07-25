//
//  SwiftXMLParser.swift
//
//  Created 2021 by Stefan Springer, https://stefanspringer.com
//  License: Apache License 2.0

import Foundation
import XMLInterfaces

fileprivate let UTF8_TEMPLATE: UInt8 = 0b10000000

// XML whitespace:
fileprivate let U_CHARACTER_TABULATION: UInt8 = 9
fileprivate let U_LINE_FEED: UInt8 = 10
fileprivate let U_CARRIAGE_RETURN: UInt8 = 13
fileprivate let U_SPACE: UInt8 = 32

// XML whitespaces as characters:
fileprivate let C_CHARACTER_TABULATION = Character(UnicodeScalar(U_CHARACTER_TABULATION))
fileprivate let C_LINE_FEED = Character(UnicodeScalar(U_LINE_FEED))
fileprivate let C_CARRIAGE_RETURN = Character(UnicodeScalar(U_CARRIAGE_RETURN))
fileprivate let C_SPACE = Character(UnicodeScalar(U_SPACE))

// other characters:
fileprivate let U_EXCLAMATION_MARK: UInt8 = 33
fileprivate let U_QUOTATION_MARK: UInt8 = 34
fileprivate let U_NUMBER_SIGN: UInt8 = 35
fileprivate let U_PERCENT_SIGN: UInt8 = 37
fileprivate let U_AMPERSAND: UInt8 = 38
fileprivate let U_APOSTROPHE: UInt8 = 39
fileprivate let U_HYPHEN_MINUS: UInt8 = 45
fileprivate let U_FULL_STOP: UInt8 = 46
fileprivate let U_SOLIDUS: UInt8 = 47
fileprivate let U_DIGIT_ZERO: UInt8 = 47
fileprivate let U_DIGIT_NINE: UInt8 = 57
fileprivate let U_COLON: UInt8 = 58
fileprivate let U_SEMICOLON: UInt8 = 59
fileprivate let U_LESS_THAN_SIGN: UInt8 = 60
fileprivate let U_EQUALS_SIGN: UInt8 = 61
fileprivate let U_GREATER_THAN_SIGN: UInt8 = 62
fileprivate let U_QUESTION_MARK: UInt8 = 63
fileprivate let U_LATIN_CAPITAL_LETTER_A: UInt8 = 65
fileprivate let U_LATIN_CAPITAL_LETTER_C: UInt8 = 67
fileprivate let U_LATIN_CAPITAL_LETTER_D: UInt8 = 68
fileprivate let U_LATIN_CAPITAL_LETTER_E: UInt8 = 69
fileprivate let U_LATIN_CAPITAL_LETTER_I: UInt8 = 73
fileprivate let U_LATIN_CAPITAL_LETTER_L: UInt8 = 76
fileprivate let U_LATIN_CAPITAL_LETTER_M: UInt8 = 77
fileprivate let U_LATIN_CAPITAL_LETTER_N: UInt8 = 78
fileprivate let U_LATIN_CAPITAL_LETTER_O: UInt8 = 79
fileprivate let U_LATIN_CAPITAL_LETTER_P: UInt8 = 80
fileprivate let U_LATIN_CAPITAL_LETTER_S: UInt8 = 83
fileprivate let U_LATIN_CAPITAL_LETTER_T: UInt8 = 84
fileprivate let U_LATIN_CAPITAL_LETTER_Y: UInt8 = 89
fileprivate let U_LATIN_CAPITAL_LETTER_Z: UInt8 = 90
fileprivate let U_LEFT_SQUARE_BRACKET: UInt8 = 91
fileprivate let U_RIGHT_SQUARE_BRACKET: UInt8 = 93
fileprivate let U_LOW_LINE: UInt8 = 95
fileprivate let U_LATIN_SMALL_LETTER_A: UInt8 = 97
fileprivate let U_LATIN_SMALL_LETTER_L: UInt8 = 108
fileprivate let U_LATIN_SMALL_LETTER_M: UInt8 = 109
fileprivate let U_LATIN_SMALL_LETTER_X: UInt8 = 120
fileprivate let U_LATIN_SMALL_LETTER_Z: UInt8 = 122
fileprivate let U_BOM_1: UInt8 = 239
fileprivate let U_BOM_2: UInt8 = 187
fileprivate let U_BOM_3: UInt8 = 191

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

fileprivate func getFileAsData(path: String) -> Data? {
    do {
        let rawData: Data = try Data(contentsOf: URL(fileURLWithPath: path))
        return rawData
    } catch {
        return nil
    }
}

fileprivate func getFileAsBytes(path: String) -> [UInt8]? {
    do {
        let rawData: Data = try Data(contentsOf: URL(fileURLWithPath: path))
        return [UInt8](rawData)
    } catch {
        return nil
    }
}

fileprivate func getFileAsText(path: String) -> String? {
    do {
        let text: String = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        return text
    } catch {
        return nil
    }
}

public func parse(
    path: String,
    eventHandler: XMLInterfaces.XMLEventHandler,
    resolveInternalEntity: ((_ entityName:String, _ attributeContext: String?, _ attributeName: String?) -> String?)? = nil
) throws {
    let _data = getFileAsData(path: path)
    if let data = _data {
        try parse(data: data, pathInfo: path, eventHandler: eventHandler, resolveInternalEntity: resolveInternalEntity)
    }
    else {
        print("ERROR")
    }
}

public func parse(
    text: String,
    eventHandler: XMLInterfaces.XMLEventHandler,
    resolveInternalEntity: ((_ entityName:String, _ attributeContext: String?, _ attributeName: String?) -> String?)? = nil
) throws {
    let _data = text.data(using: .utf8)
    if let data = _data {
        try parse(data: data, eventHandler: eventHandler, resolveInternalEntity: resolveInternalEntity)
    }
    else {
        print("ERROR")
    }
}

public struct XMLParseError: LocalizedError {
    
    private let message: String

    init(_ message: String) {
        self.message = message
    }
    
    public var errorDescription: String? {
        return message
    }
}

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

fileprivate struct Stack<Element> {
    var elements = [Element]()
    mutating func push(_ item: Element) {
        elements.append(item)
    }
    mutating func pop() -> Element? {
        if elements.isEmpty {
            return nil
        }
        else {
            return elements.removeLast()
        }
    }
    func peek() -> Element? {
        return elements.last
    }
    func peekAll() -> [Element] {
        return elements
    }
}

public func parse(
    data: Data,
    pathInfo: String? = nil,
    eventHandler: XMLInterfaces.XMLEventHandler,
    resolveInternalEntity: ((_ entityName:String, _ attributeContext: String?, _ attributeName: String?) -> String?)? = nil
) throws {
    
    let startTime = DispatchTime.now()
    
    var line = 1
    var row = 0
    
    func error(_ message: String, offset: Int = 0) throws {
        throw XMLParseError("\(pathInfo != nil ? "\(pathInfo ?? ""):" : "")\(max(1,line-offset)):\(row):E: \(message)")
    }
    
    func characterCitation(_ b: Data.Element) -> String {
        if b & UTF8_TEMPLATE == 0 && b >= U_SPACE {
            return "\"\(Character(UnicodeScalar(b)))\""
        }
        else {
            return "\"x\(String(format: "%X", b))\""
        }
    }
    
    func isNameStartCharacter(_ b: Data.Element) -> Bool {
        return (b >= U_LATIN_SMALL_LETTER_A && b <= U_LATIN_SMALL_LETTER_Z)
           || (b >= U_LATIN_CAPITAL_LETTER_A && b <= U_LATIN_CAPITAL_LETTER_Z)
           || b == U_COLON || b == U_LOW_LINE || b & UTF8_TEMPLATE > 0
    }

    func isNameCharacter(_ b: Data.Element) -> Bool {
        return isNameStartCharacter(b) || b == U_HYPHEN_MINUS || b == U_FULL_STOP ||
            (b >= U_DIGIT_ZERO && b <= U_DIGIT_NINE)
    }
    
    var pos = -1
    var parsedBefore = 0
    var outerParsedBefore = 0
    var possibleState = _DECLARATION_LIKE
    var unkownDeclarationOffset = 0
    
    var lastB: Data.Element = 0
    var lastLastB: Data.Element = 0
    
    var elementLevel = 0
    
    var texts = [String]()
    var isWhitespace = true
    
    // for parsing of start tag:
    var tokenStart = -1
    var token: String? = nil
    var name: String? = nil
    var equalSignAfterToken = false
    var quoteSign: Data.Element = 0
    var items = [itemParseResult]()
    
    var externalEntityNames = Set<String>()
    
    var someDocumentTypeDeclaration = false
    var someElement = false
    var ancestors = Stack<String>()
    
    enum State {
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
    
    var state = State.TEXT
    var outerState = State.TEXT
    
    var attributes = [String:String]()

    var expectedUTF8Rest = 0
    
    for b in data {
        pos += 1
        if b == U_LINE_FEED {
            line += 1
            row = 0
        }
        row += 1
        
        // check UTF-8 encoding:
        if expectedUTF8Rest > 0 {
            if b & 0b10000000 == 0 || b & 0b01000000 > 0 {
                try error("wrong UTF-8 encoding: expecting follow-up byte 10xxxxxx")
            }
            expectedUTF8Rest -= 1
        }
        else if b & 0b10000000 > 0 {
            if b & 0b01000000 > 0 {
                if b & 0b00100000 == 0 {
                    expectedUTF8Rest = 1
                }
                else if b & 0b00010000 == 0 {
                    expectedUTF8Rest = 2
                }
                else if b & 0b00001000 == 0 {
                    expectedUTF8Rest = 3
                }
                else {
                    try error("wrong UTF-8 encoding: uncorrect leading byte")
                }
            }
            else {
                try error("wrong UTF-8 encoding: uncorrect leading byte")
            }
        }
        
        //print("### \(outerState)/\(state): \(characterCitation(b))")
        
        switch state {
        case .TEXT:
            switch b {
            case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                break
            case U_QUOTATION_MARK, U_APOSTROPHE:
                if elementLevel == 0 && outerState == .TEXT {
                    try error("non-whitespace \(characterCitation(b)) outside elements")
                }
                else if b == quoteSign {
                    if pos > parsedBefore {
                        texts.append(String(decoding: data.subdata(in: parsedBefore..<pos), as: UTF8.self))
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
                        items.append(quotedParseResult(value: String(decoding: data.subdata(in: parsedBefore..<pos), as: UTF8.self)))
                    }
                    texts.removeAll()
                    quoteSign = 0
                    state = outerState
                    outerState = .TEXT
                    parsedBefore = pos + 1
                }
                else {
                    isWhitespace = false
                }
            case U_AMPERSAND:
                if pos > parsedBefore {
                    texts.append(String(decoding: data.subdata(in: parsedBefore..<pos), as: UTF8.self))
                }
                state = .ENTITY
                parsedBefore = pos + 1
            case U_LESS_THAN_SIGN:
                if outerState == .TEXT {
                    if pos > parsedBefore {
                        texts.append(String(decoding: data.subdata(in: parsedBefore..<pos), as: UTF8.self))
                    }
                    if !texts.isEmpty {
                        if elementLevel > 0 {
                            eventHandler.text(text: texts.joined(), isWhitespace: isWhitespace)
                            isWhitespace = true
                        }
                        texts.removeAll()
                    }
                    state = .JUST_STARTED_WITH_LESS_THAN_SIGN
                    parsedBefore = pos + 1
                }
                else {
                    try error("illegal \(characterCitation(b))")
                }
            default:
                if elementLevel == 0 && outerState == .TEXT {
                    var whitespaceCheck = true
                    switch pos {
                    case 0: if b == U_BOM_1 { whitespaceCheck = false }
                    case 1: if b == U_BOM_2 && lastB == U_BOM_1 { whitespaceCheck = false}
                    case 2: if b == U_BOM_3 && lastB == U_BOM_2 && lastLastB == U_BOM_1 { whitespaceCheck = false }
                    default: break
                    }
                    if whitespaceCheck {
                        try error("non-whitespace \(characterCitation(b)) outside elements")
                    }
                }
                else {
                    isWhitespace = false
                }
            }
        /* 2 */
        case .START_OR_EMPTY_TAG, .XML_DECLARATION:
                switch b {
                case U_GREATER_THAN_SIGN:
                    if tokenStart >= 0 {
                        token = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                        if name == nil {
                            name = token
                            token = nil
                        }
                        tokenStart = -1
                    }
                    if state == .XML_DECLARATION {
                        try error("illegal \(characterCitation(b)) in processing instruction")
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
                        eventHandler.elementStart(name: name ?? "", attributes: &attributes)
                        someElement = true
                        ancestors.push(name ?? "")
                        elementLevel += 1
                        name = nil
                        attributes = [String:String]()
                        state = .TEXT
                        parsedBefore = pos + 1
                    }
                case U_QUOTATION_MARK, U_APOSTROPHE:
                    if tokenStart > 0 {
                        try error("misplaced attribute value")
                    }
                    quoteSign = b
                    outerState = state
                    state = .TEXT
                    parsedBefore = pos + 1
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION, U_SOLIDUS, U_QUESTION_MARK:
                    if tokenStart >= 0 {
                        token = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                        if name == nil {
                            name = token
                            token = nil
                        }
                        tokenStart = -1
                    }
                    if state == .START_OR_EMPTY_TAG {
                        if b == U_SOLIDUS {
                            state = .EMPTY_TAG_FINISHING
                        }
                    }
                    else if b == U_QUESTION_MARK {
                        state = .XML_DECLARATION_FINISHING
                    } else if b == U_SOLIDUS {
                        try error("illegal \(characterCitation(b)) in processing instruction")
                    }
                case U_EQUALS_SIGN:
                    if tokenStart >= 0 {
                        if token != nil {
                            try error("multiple subsequent tokens")
                        }
                        token = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
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
                        if !isNameCharacter(b) {
                            try error("illegal \(characterCitation(b)) in token")
                        }
                    }
                    else {
                        if !isNameStartCharacter(b) {
                            try error("illegal \(characterCitation(b)) at start of token")
                        }
                        tokenStart = pos
                    }
                }
        /* 3 */
        case .END_TAG:
            switch b {
            case U_GREATER_THAN_SIGN:
                if tokenStart > 0 {
                    name = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                    tokenStart = 0
                }
                if name == nil {
                    try error("missing element name")
                }
                if (name ?? "") != ancestors.peek() {
                    try error("name end tag \"\(name ?? "")\" does not match name of open element \"\(ancestors.peek() ?? "")\"")
                }
                eventHandler.elementEnd(name: name ?? "")
                _ = ancestors.pop()
                elementLevel -= 1
                name = nil
                state = .TEXT
                parsedBefore = pos + 1
            case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                if tokenStart > 0 {
                    name = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                    tokenStart = 0
                }
                else if name == nil {
                    try error("illegal space at beginning of end tag")
                }
            default:
                if name == nil {
                    if tokenStart > 0 {
                        if !isNameCharacter(b) {
                            try error("illegal \(characterCitation(b)) in element name")
                        }
                    }
                    else {
                        if !isNameStartCharacter(b) {
                            try error("illegal \(characterCitation(b)) at start of element name")
                        }
                        tokenStart = pos
                    }
                }
                else {
                    try error("illegal \(characterCitation(b)) after element name in end tag")
                }
            }
        /* 4 */
        case .JUST_STARTED_WITH_LESS_THAN_SIGN:
            switch b {
            case U_SOLIDUS:
                state = .END_TAG
            case U_EXCLAMATION_MARK:
                state = .UNKNOWN_DECLARATION_LIKE
                outerParsedBefore = pos - 1
            case U_QUESTION_MARK:
                state = .PROCESSING_INSTRUCTION
            default:
                if isNameCharacter(b) {
                    tokenStart = pos
                }
                else {
                    try error("illegal \(characterCitation(b)) after \"<\"")
                }
                state = .START_OR_EMPTY_TAG
            }
        /* 5 */
        case .ENTITY:
            if b == U_SEMICOLON {
                let entityText = String(decoding: data.subdata(in: parsedBefore..<pos), as: UTF8.self)
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
                            try error("could not convert numerical character reference &\(entityText);")
                        }
                    }
                    else {
                        isExternal = externalEntityNames.contains(entityText)
                        if !isExternal, let doResolveInternalEntity = resolveInternalEntity {
                            resolution = doResolveInternalEntity(entityText, name, token)
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
                }
                else if outerState == .TEXT {
                    if !texts.isEmpty {
                        let text = texts.joined()
                        if elementLevel > 0 {
                            eventHandler.text(text: text, isWhitespace: isWhitespace)
                            isWhitespace = true
                        }
                        texts.removeAll()
                    }
                    if isExternal {
                        eventHandler.externalEntity(name: entityText)
                    }
                    else {
                        eventHandler.internalEntity(name: entityText)
                    }
                }
                else if isExternal {
                    try error("misplaced external entity \"\(entityText)\"")
                }
                else {
                    try error("remaining internal entity \"\(entityText)\"")
                }
                state = .TEXT
                parsedBefore = pos + 1
            }
        /* 6 */
        case .EMPTY_TAG_FINISHING:
            if b == U_GREATER_THAN_SIGN {
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
                eventHandler.elementStart(name: name ?? "", attributes: &attributes)
                eventHandler.elementEnd(name: name ?? "")
                someElement = true
                name = nil
                attributes = [String:String]()
                state = .TEXT
                parsedBefore = pos + 1
            }
            else {
                try error("expecting \(characterCitation(U_GREATER_THAN_SIGN)) to end empty tag")
            }
        /* 7 */
        case .PROCESSING_INSTRUCTION:
            switch b {
            case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                if tokenStart > -1 {
                    name =  String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                    tokenStart = -1
                    parsedBefore = pos + 1
                    if name == "xml" {
                        state = .XML_DECLARATION
                    }
                }
                else if name == nil {
                    try error("illegal space at start of processing instruction")
                }
            case U_GREATER_THAN_SIGN:
                if lastB == U_QUOTATION_MARK {
                    if tokenStart >= 0 {
                        name =  String(decoding: data.subdata(in: tokenStart..<pos-1), as: UTF8.self)
                        tokenStart = -1
                    }
                    if let target = name {
                        eventHandler.processingInstruction(target: target, content: String(decoding: data.subdata(in: parsedBefore..<pos-1), as: UTF8.self))
                    }
                    else {
                        try error("procesing instruction without target")
                    }
                    state = outerState
                    outerState = .TEXT
                }
            default:
                if name == nil {
                    if tokenStart < 0 {
                        if !isNameStartCharacter(b) {
                            try error("illegal character at start of processing instruction")
                        }
                        tokenStart = pos
                    }
                    else if !isNameCharacter(b) {
                        try error("illegal \(characterCitation(b)) in processing instruction target")
                    }
                }
            }
        /* 8 */
        case .CDATA_SECTION:
            switch b {
            case U_GREATER_THAN_SIGN:
                if lastB == U_RIGHT_SQUARE_BRACKET && lastLastB == U_RIGHT_SQUARE_BRACKET {
                    eventHandler.cdataSection(text: String(decoding: data.subdata(in: parsedBefore..<pos-2), as: UTF8.self))
                    parsedBefore = pos + 1
                    state = outerState
                    outerState = .TEXT
                }
            default:
                break
            }
        /* 9 */
        case .COMMENT:
            switch b {
            case U_GREATER_THAN_SIGN:
                if lastB == U_HYPHEN_MINUS && lastLastB == U_HYPHEN_MINUS {
                    eventHandler.comment(text: String(decoding: data.subdata(in: parsedBefore..<pos-2), as: UTF8.self))
                    parsedBefore = pos + 1
                    state = outerState
                    outerState = .TEXT
                }
            default:
                if lastB == U_HYPHEN_MINUS && lastLastB == U_HYPHEN_MINUS {
                    try error("\"--\" in comment not marking the end of it")
                }
            }
        /* 10 */
        case .DOCUMENT_TYPE_DECLARATION_HEAD, .ENTITY_DECLARATION, .NOTATION_DECLARATION:
            switch b {
            case U_LEFT_SQUARE_BRACKET, U_GREATER_THAN_SIGN:
                if b == U_LEFT_SQUARE_BRACKET && !(state == .DOCUMENT_TYPE_DECLARATION_HEAD) {
                    try error("illegal character \(characterCitation(b))")
                    break
                }
                if tokenStart >= 0 {
                    items.append(tokenParseResult(value: String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)))
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
                                    eventHandler.documentTypeDeclaration(type: name, publicID: publicID, systemID: nil)
                                    success = true
                                }
                            }
                            else if theToken == "PUBLIC" {
                                if items.count == 3 {
                                    if let publicID = (items[2] as? quotedParseResult)?.value
                                       {
                                        eventHandler.documentTypeDeclaration(type: name, publicID: publicID, systemID:  nil)
                                        success = true
                                    }
                                }
                                else if items.count == 4 {
                                    if let publicID = (items[2] as? quotedParseResult)?.value,
                                       let systemID = (items[3] as? quotedParseResult)?.value
                                    {
                                        eventHandler.documentTypeDeclaration(type: name, publicID: publicID, systemID: systemID)
                                        success = true
                                    }
                                }
                            }
                        }
                        else {
                            eventHandler.documentTypeDeclaration(type: name, publicID: nil, systemID: nil)
                            success = true
                        }
                        if success {
                            someDocumentTypeDeclaration = true
                        }
                        else {
                            try error("incorrect document type declaration")
                        }
                    }
                    else {
                        try error("missing type in document type declaration")
                    }
                    state = b == U_LEFT_SQUARE_BRACKET ? .INTERNAL_SUBSET : .TEXT
                    parsedBefore = pos + 1
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
                                eventHandler.parameterEntityDeclaration(name: realEntityName, value: value)
                                success = true
                            }
                        }
                        else if items.count == 2 {
                            if let value = (items[1] as? quotedParseResult)?.value {
                                eventHandler.internalEntityDeclaration(name: entityName, value: value)
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
                                            eventHandler.unparsedEntityDeclaration(name: entityName, publicID: publicValue, systemID: systemValue, notation: notation.value)
                                            externalEntityNames.insert(entityName)
                                            success = true
                                        }
                                    }
                                    else if items.count == 3 + systemShift {
                                        eventHandler.externalEntityDeclaration(name: entityName, publicID: publicValue, systemID: systemValue)
                                        externalEntityNames.insert(entityName)
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
                                    eventHandler.notationDeclaration(name: notationName, publicID: publicValue, systemID: systemValue)
                                    success = true
                                }
                            }
                            else if items.count == 3 {
                                if let publicOrSystemValue = (items[2] as? quotedParseResult)?.value
                                {
                                    if hasPublicToken {
                                        eventHandler.notationDeclaration(name: notationName, publicID: publicOrSystemValue, systemID: nil)
                                    }
                                    else {
                                        eventHandler.notationDeclaration(name: notationName, publicID: nil, systemID: publicOrSystemValue)
                                    }
                                    success = true
                                }
                            }
                        }
                    }
                    if !success {
                        try error("incorrect notation declaration")
                    }
                default:
                    try error("fatal program error: unexpected state")
                }
                items.removeAll()
                state = .INTERNAL_SUBSET
                outerState = .TEXT
                parsedBefore = pos + 1
            case U_QUOTATION_MARK, U_APOSTROPHE:
                if tokenStart >= 0 {
                    try error("illegal \(characterCitation(b))")
                    items.append(tokenParseResult(value: String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)))
                    tokenStart = -1
                }
                quoteSign = b
                parsedBefore = pos + 1
                outerState = state
                state = .TEXT
            case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                if tokenStart >= 0 {
                    items.append(tokenParseResult(value: String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)))
                    tokenStart = -1
                }
            default:
                if tokenStart > 0 {
                    if !isNameCharacter(b) {
                        try error("illegal \(characterCitation(b)) in element name")
                    }
                }
                else {
                    if !(isNameStartCharacter(b) || (state == .ENTITY_DECLARATION && b == U_PERCENT_SIGN && items.count == 0)) {
                        try error("illegal \(characterCitation(b)) in declaration")
                    }
                    tokenStart = pos
                }
            }
        /* 11 */
        case .UNKNOWN_DECLARATION_LIKE:
            switch unkownDeclarationOffset {
            case 0:
                if possibleState & _ENTITY_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_E {
                    possibleState ^= _ENTITY_DECLARATION
                }
                if possibleState & _COMMENT > 0 && b != U_HYPHEN_MINUS {
                    possibleState ^= _COMMENT
                }
                if possibleState & _CDATA_SECTION > 0 && b != U_LEFT_SQUARE_BRACKET {
                    possibleState ^= _CDATA_SECTION
                }
                if possibleState & _NOTATION_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_N {
                    possibleState ^= _NOTATION_DECLARATION
                }
                if possibleState & _ELEMENT_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_E {
                    possibleState ^= _ELEMENT_DECLARATION
                }
                if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_A {
                    possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                }
                if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && b != U_LATIN_CAPITAL_LETTER_D {
                    possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                }
            case 1:
                if possibleState & _ENTITY_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_N {
                    possibleState ^= _ENTITY_DECLARATION
                }
                if possibleState & _COMMENT > 0 {
                    if b == U_HYPHEN_MINUS {
                        state = .COMMENT
                    }
                    else {
                        possibleState ^= _COMMENT
                    }
                }
                if possibleState & _CDATA_SECTION > 0 && b != U_LATIN_CAPITAL_LETTER_C {
                    possibleState ^= _CDATA_SECTION
                }
                if possibleState & _NOTATION_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_O {
                    possibleState ^= _NOTATION_DECLARATION
                }
                if possibleState & _ELEMENT_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_L {
                    possibleState ^= _ELEMENT_DECLARATION
                }
                if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                }
                if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && b != U_LATIN_CAPITAL_LETTER_O {
                    possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                }
            case 2:
                if possibleState & _CDATA_SECTION > 0 && b != U_LATIN_CAPITAL_LETTER_D {
                    possibleState ^= _CDATA_SECTION
                }
                if possibleState & _ENTITY_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _ENTITY_DECLARATION
                }
                if possibleState & _NOTATION_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _NOTATION_DECLARATION
                }
                if possibleState & _ELEMENT_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_E {
                    possibleState ^= _ELEMENT_DECLARATION
                }
                if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                }
                if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && b != U_LATIN_CAPITAL_LETTER_C {
                    possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                }
            case 3:
                if possibleState & _CDATA_SECTION > 0 && b != U_LATIN_CAPITAL_LETTER_A {
                    possibleState ^= _CDATA_SECTION
                }
                if possibleState & _ENTITY_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_I {
                    possibleState ^= _ENTITY_DECLARATION
                }
                if possibleState & _NOTATION_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_A {
                    possibleState ^= _NOTATION_DECLARATION
                }
                if possibleState & _ELEMENT_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_M {
                    possibleState ^= _ELEMENT_DECLARATION
                }
                if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_L {
                    possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                }
                if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                }
            case 4:
                if possibleState & _CDATA_SECTION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _CDATA_SECTION
                }
                if possibleState & _ENTITY_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _ENTITY_DECLARATION
                }
                if possibleState & _NOTATION_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _NOTATION_DECLARATION
                }
                if possibleState & _ELEMENT_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_E {
                    possibleState ^= _ELEMENT_DECLARATION
                }
                if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_I {
                    possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                }
                if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && b != U_LATIN_CAPITAL_LETTER_Y {
                    possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                }
            case 5:
                if possibleState & _CDATA_SECTION > 0 && b != U_LATIN_CAPITAL_LETTER_A {
                    possibleState ^= _CDATA_SECTION
                }
                if possibleState & _ENTITY_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_Y {
                    possibleState ^= _ENTITY_DECLARATION
                }
                if possibleState & _NOTATION_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_I {
                    possibleState ^= _NOTATION_DECLARATION
                }
                if possibleState & _ELEMENT_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_N {
                    possibleState ^= _ELEMENT_DECLARATION
                }
                if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_S {
                    possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                }
                if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && b != U_LATIN_CAPITAL_LETTER_P {
                    possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                }
            case 6:
                if possibleState & _CDATA_SECTION > 0 {
                    if b == U_LEFT_SQUARE_BRACKET {
                        state = .CDATA_SECTION
                        break
                    }
                    else {
                        possibleState ^= _CDATA_SECTION
                    }
                }
                if possibleState & _ENTITY_DECLARATION > 0 {
                    if b == U_SPACE || b == U_LINE_FEED || b == U_CARRIAGE_RETURN || b == U_CHARACTER_TABULATION {
                        state = .ENTITY_DECLARATION
                        break
                    }
                    else {
                        possibleState ^= _ENTITY_DECLARATION
                    }
                }
                if possibleState & _NOTATION_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_O {
                    possibleState ^= _NOTATION_DECLARATION
                }
                if possibleState & _ELEMENT_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _ELEMENT_DECLARATION
                }
                if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_T {
                    possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                }
                if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 && b != U_LATIN_CAPITAL_LETTER_E {
                    possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                }
            case 7:
                if possibleState & _NOTATION_DECLARATION > 0 && b != U_LATIN_CAPITAL_LETTER_N {
                    possibleState ^= _NOTATION_DECLARATION
                }
                if possibleState & _ELEMENT_DECLARATION > 0 {
                    if b == U_SPACE || b == U_LINE_FEED || b == U_CARRIAGE_RETURN || b == U_CHARACTER_TABULATION {
                        state = .ELEMENT_DECLARATION
                        break
                    }
                    else {
                        possibleState ^= _ELEMENT_DECLARATION
                    }
                }
                if possibleState & _ATTRIBUTE_LIST_DECLARATION > 0 {
                    if b == U_SPACE || b == U_LINE_FEED || b == U_CARRIAGE_RETURN || b == U_CHARACTER_TABULATION {
                        state = .ATTRIBUTE_LIST_DECLARATION
                        break
                    }
                    else {
                        possibleState ^= _ATTRIBUTE_LIST_DECLARATION
                    }
                }
                if possibleState & _DOCUMENT_TYPE_DECLARATION_HEAD > 0 {
                    if b == U_SPACE || b == U_LINE_FEED || b == U_CARRIAGE_RETURN || b == U_CHARACTER_TABULATION {
                        state = .DOCUMENT_TYPE_DECLARATION_HEAD
                        break
                    }
                    else {
                        possibleState ^= _DOCUMENT_TYPE_DECLARATION_HEAD
                    }
                }
            case 8:
                if possibleState & _NOTATION_DECLARATION > 0 {
                    if b == U_SPACE || b == U_LINE_FEED || b == U_CARRIAGE_RETURN || b == U_CHARACTER_TABULATION {
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
            
            parsedBefore = pos + 1
        /* 12 */
        case .INTERNAL_SUBSET:
            switch b {
            case U_RIGHT_SQUARE_BRACKET:
                state = .DOCUMENT_TYPE_DECLARATION_TAIL
            case U_LESS_THAN_SIGN:
                state = .JUST_STARTED_WITH_LESS_THAN_SIGN
                outerState = .INTERNAL_SUBSET
            case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION, U_SOLIDUS:
                if lastB == U_LESS_THAN_SIGN {
                    try error("illegal \(U_LESS_THAN_SIGN) in internal subset")
                }
            default:
                if lastB == U_LESS_THAN_SIGN {
                    try error("illegal \(U_LESS_THAN_SIGN) in internal subset")
                }
                try error("illegal \(characterCitation(b)) in internal subset")
            }
        /* 13 */
        case .ELEMENT_DECLARATION, .ATTRIBUTE_LIST_DECLARATION:
            switch b {
            case U_GREATER_THAN_SIGN:
                if quoteSign == 0 {
                    if state == .ELEMENT_DECLARATION {
                        if outerState != .INTERNAL_SUBSET {
                            try error("element declaration outside internal subset")
                        }
                        eventHandler.elementDeclaration(text: String(decoding: data.subdata(in: outerParsedBefore..<pos+1), as: UTF8.self))
                    }
                    else {
                        if outerState != .INTERNAL_SUBSET {
                            try error("attribute list declaration outside internal subset")
                        }
                        eventHandler.attributeListDeclaration(text: String(decoding: data.subdata(in: outerParsedBefore..<pos+1), as: UTF8.self))
                    }
                    parsedBefore = pos + 1
                    state = outerState; outerState = .TEXT
                }
            case U_QUOTATION_MARK, U_APOSTROPHE:
                if b == quoteSign {
                    quoteSign = 0
                }
                else {
                    quoteSign = b
                }
            default:
                break
            }
        /* 14 */
        case .XML_DECLARATION_FINISHING:
            if b == U_GREATER_THAN_SIGN {
                if someDocumentTypeDeclaration || someElement {
                    try error("misplaced XML declaration")
                }
                if token != nil {
                    try error("misplaced token")
                    token = nil
                }
                var version: String? = nil
                var encoding: String? = nil
                var standalone: String? = nil
                try attributes.keys.forEach { attributeName in
                    switch attributeName {
                    case "version": version = attributes["version"]
                    case "encoding": encoding = attributes["encoding"]
                    case "standalone": standalone = attributes["standalone"]
                    default: try error("unkonwn attribute \"\(attributeName)\" in XML declaration")
                    }
                }
                if let theVersion = version {
                    eventHandler.xmlDeclaration(version: theVersion, encoding: encoding, standalone: standalone)
                }
                else {
                    try error("uncomplete XML declaration, at least the version should be set")
                }
                name = nil
                attributes = [String:String]()
                state = .TEXT
                parsedBefore = pos + 1
            }
            else {
                try error("expecting \(characterCitation(U_GREATER_THAN_SIGN)) to end XML declaration")
            }
        /* 15 */
        case .DOCUMENT_TYPE_DECLARATION_TAIL:
            switch b {
            case U_GREATER_THAN_SIGN:
                state = .TEXT
                parsedBefore = pos + 1
            case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION, U_SOLIDUS:
                break
            default:
                try error("illegal \(characterCitation(b)) in document type declaration after internal subset")
            }
        }
        
        lastLastB = lastB
        lastB = b
    }
    pos += 1
    
    if elementLevel > 0 {
        try error("document not finished, elements \(ancestors.peekAll().reversed().map{ "\"\($0)\"" }.joined(separator: ", ")) are not closed")
    }
    else if state != .TEXT {
        try error("junk at end of document")
    }
    
    let end = DispatchTime.now()
    let nanoTime = end.uptimeNanoseconds - startTime.uptimeNanoseconds
    eventHandler.parsingTime(seconds: Double(nanoTime) / 1_000_000_000)
}
