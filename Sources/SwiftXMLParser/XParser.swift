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

public class XParser: Parser {
    
    let internalEntityResolver: InternalEntityResolver?
    
    let textAllowed: (() -> Bool)?
    
    public init(internalEntityResolver: InternalEntityResolver? = nil, textAllowed: (() -> Bool)? = nil) {
        self.internalEntityResolver = internalEntityResolver
        self.textAllowed = textAllowed
    }
    
    public func parse(
        fromData data: Data,
        sourceInfo: String? = nil,
        eventHandlers: [XEventHandler]
    ) throws {
        var line = 1
        var row = 0
        
        func error(_ message: String, offset: Int = 0) throws {
            throw ParseError("\(sourceInfo != nil ? "\(sourceInfo ?? ""):" : "")\(max(1,line-offset)):\(row):E: \(message)")
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
        
        var pos = -1
        var parsedBefore = 0
        var outerParsedBefore = 0
        var possibleState = _DECLARATION_LIKE
        var unkownDeclarationOffset = 0
        
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
        
        var declaredEntityNames: Set<String> = []
        var declaredNotationNames: Set<String> = []
        var declaredElementNames: Set<String> = []
        var declaredAttributeListNames: Set<String> = []
        var declaredParameterEntityNames: Set<String> = []
        
        eventHandlers.forEach { eventHandler in eventHandler.documentStart() }
        
        var codePoint: UnicodeCodePoint = 0
        var lastCodePoint: UnicodeCodePoint = 0
        var lastLastCodePoint: UnicodeCodePoint = 0
        
        binaryLoop: for b in data {
            pos += 1
            
            // check UTF-8 encoding:
            if expectedUTF8Rest > 0 {
                if b & 0b10000000 == 0 || b & 0b01000000 > 0 {
                    try error("wrong UTF-8 encoding: expecting follow-up byte 10xxxxxx")
                }
                codePoint |= UnicodeCodePoint(b << 2)
                expectedUTF8Rest -= 1
            }
            else if b & 0b10000000 > 0 {
                codePoint = 0
                if b & 0b01000000 > 0 {
                    if b & 0b00100000 == 0 {
                        codePoint |= UnicodeCodePoint(b << 3)
                        expectedUTF8Rest = 1
                    }
                    else if b & 0b00010000 == 0 {
                        codePoint |= UnicodeCodePoint(b << 4)
                        expectedUTF8Rest = 2
                    }
                    else if b & 0b00001000 == 0 {
                        codePoint |= UnicodeCodePoint(b << 5)
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
            else {
                codePoint = UnicodeCodePoint(b)
            }
            
            if expectedUTF8Rest > 0 {
                break binaryLoop
            }
            
            if lastCodePoint == U_LINE_FEED {
                line += 1
                row = 0
            }
            
            if let unicodeScalar = UnicodeScalar(codePoint) {
                let unicodeScalarProperties = unicodeScalar.properties
                if !(unicodeScalarProperties.isDiacritic || unicodeScalarProperties.isVariationSelector) {
                    row += 1
                }
            }
            else {
                try error("x\(String(format: "%X", codePoint)) is not a Unicode codepoint")
            }
            
            //print("### \(outerState)/\(state): \(characterCitation(codePoint)) (WHITESPACE: \(isWhitespace))")
            
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
                                if textAllowed?() == false {
                                    if !isWhitespace {
                                        try error("non-whitespace #1 text in \(ancestors.elements.joined(separator: " / ")): \"\(formatNonWhitespace(texts.joined()))\"")
                                    }
                                }
                                else {
                                    eventHandlers.forEach { eventHandler in eventHandler.text(text: texts.joined().replacingOccurrences(of: "\r\n", with: "\n"), whitespace: isWhitespace ? .WHITESPACE : .NOT_WHITESPACE) }
                                }
                            }
                            texts.removeAll()
                        }
                        isWhitespace = true
                        state = .JUST_STARTED_WITH_LESS_THAN_SIGN
                        parsedBefore = pos + 1
                    }
                    else {
                        try error("illegal \(characterCitation(codePoint))")
                    }
                default:
                    if elementLevel == 0 && outerState == .TEXT {
                        var whitespaceCheck = true
                        switch pos {
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
                            token = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
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
                                eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: name ?? "", attributes: nil) }
                            }
                            else {
                                eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: name ?? "", attributes: attributes) }
                                attributes = [String:String]()
                            }
                            someElement = true
                            ancestors.push(name ?? "")
                            elementLevel += 1
                            name = nil
                            state = .TEXT
                            isWhitespace = true
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
                            try error("illegal \(characterCitation(codePoint))")
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
                            if !isNameCharacter(codePoint) {
                                try error("illegal \(characterCitation(codePoint)) in token")
                            }
                        }
                        else {
                            if !isNameStartCharacter(codePoint) {
                                try error("illegal \(characterCitation(codePoint)) at start of token")
                            }
                            tokenStart = pos
                        }
                    }
            /* 3 */
            case .END_TAG:
                switch codePoint {
                case U_GREATER_THAN_SIGN:
                    if tokenStart > 0 {
                        name = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                        tokenStart = -1
                    }
                    if name == nil {
                        try error("missing element name")
                    }
                    if (name ?? "") != ancestors.peek() {
                        try error("name end tag \"\(name ?? "")\" does not match name of open element \"\(ancestors.peek() ?? "")\"")
                    }
                    eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: name ?? "") }
                    _ = ancestors.pop()
                    elementLevel -= 1
                    name = nil
                    state = .TEXT
                    isWhitespace = true
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
                            if !isNameCharacter(codePoint) {
                                try error("illegal \(characterCitation(codePoint)) in element name")
                            }
                        }
                        else {
                            if !isNameStartCharacter(codePoint) {
                                try error("illegal \(characterCitation(codePoint)) at start of element name")
                            }
                            tokenStart = pos
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
                    outerParsedBefore = pos - 1
                case U_QUESTION_MARK:
                    state = .PROCESSING_INSTRUCTION
                default:
                    if isNameCharacter(codePoint) {
                        tokenStart = pos
                    }
                    else {
                        try error("illegal \(characterCitation(codePoint)) after \"<\"")
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
                            if !isExternal, let theInternalEntityResolver = internalEntityResolver {
                                if outerState == .START_OR_EMPTY_TAG {
                                    if name == nil {
                                        try error("missing element name")
                                    }
                                    if token == nil {
                                        try error("missing attribute name")
                                    }
                                }
                                resolution = theInternalEntityResolver.resolve(entityWithName: entityText, forAttributeName: token, atElement: name)
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
                                if textAllowed?() == false {
                                    if !isWhitespace {
                                        try error("non-whitespace #2 text in \(ancestors.elements.joined(separator: " / ")): \"\(formatNonWhitespace(text))\"")
                                    }
                                }
                                else {
                                    eventHandlers.forEach { eventHandler in eventHandler.text(text: text.replacingOccurrences(of: "\r\n", with: "\n"), whitespace: isWhitespace ? .WHITESPACE : .NOT_WHITESPACE) }
                                }
                            }
                            texts.removeAll()
                            isWhitespace = true
                        }
                        if isExternal {
                            eventHandlers.forEach { eventHandler in eventHandler.externalEntity(name: entityText) }
                        }
                        else {
                            eventHandlers.forEach { eventHandler in eventHandler.internalEntity(name: entityText) }
                        }
                    }
                    else {
                        let descriptionStart = isExternal ? "misplaced external" : "remaining internal"
                        if outerState == .START_OR_EMPTY_TAG, let theElementName = name, let theAttributeName = token {
                            try error("\(descriptionStart) entity \"\(entityText)\" in attribute \"\(theAttributeName)\" of element \"\(theElementName)\"")
                        }
                        else {
                            try error("\(descriptionStart) entity \"\(entityText)\" in striclty textual content")
                        }
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
                    if attributes.isEmpty {
                        eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: name ?? "", attributes: nil) }
                    }
                    else {
                        eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: name ?? "", attributes: attributes) }
                        attributes = [String:String]()
                    }
                    eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: name ?? "") }
                    someElement = true
                    name = nil
                    state = .TEXT
                    isWhitespace = true
                    parsedBefore = pos + 1
                }
                else {
                    try error("expecting \(characterCitation(U_GREATER_THAN_SIGN)) to end empty tag")
                }
            /* 7 */
            case .PROCESSING_INSTRUCTION:
                switch codePoint {
                case U_QUESTION_MARK, U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
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
                    if lastCodePoint == U_QUESTION_MARK {
                        if tokenStart >= 0 {
                            name =  String(decoding: data.subdata(in: tokenStart..<pos-1), as: UTF8.self)
                            tokenStart = -1
                        }
                        if let target = name {
                            eventHandlers.forEach { eventHandler in eventHandler.processingInstruction(target: target, data: parsedBefore<pos-1 ? String(decoding: data.subdata(in: parsedBefore..<pos-1), as: UTF8.self): nil) }
                            name = nil
                        }
                        else {
                            try error("procesing instruction without target")
                        }
                        parsedBefore = pos + 1
                        state = outerState
                        outerState = .TEXT
                    }
                default:
                    if name == nil {
                        if tokenStart < 0 {
                            if !isNameStartCharacter(codePoint) {
                                try error("illegal character at start of processing instruction")
                            }
                            tokenStart = pos
                        }
                        else if !isNameCharacter(codePoint) {
                            try error("illegal \(characterCitation(codePoint)) in processing instruction target")
                        }
                    }
                }
            /* 8 */
            case .CDATA_SECTION:
                switch codePoint {
                case U_GREATER_THAN_SIGN:
                    if lastCodePoint == U_RIGHT_SQUARE_BRACKET && lastLastCodePoint == U_RIGHT_SQUARE_BRACKET {
                        eventHandlers.forEach { eventHandler in eventHandler.cdataSection(text: String(decoding: data.subdata(in: parsedBefore..<pos-2), as: UTF8.self)) }
                        parsedBefore = pos + 1
                        state = outerState
                        outerState = .TEXT
                    }
                default:
                    break
                }
            /* 9 */
            case .COMMENT:
                switch codePoint {
                case U_GREATER_THAN_SIGN:
                    if lastCodePoint == U_HYPHEN_MINUS && lastLastCodePoint == U_HYPHEN_MINUS {
                        eventHandlers.forEach { eventHandler in eventHandler.comment(text: String(decoding: data.subdata(in: parsedBefore..<pos-2), as: UTF8.self)) }
                        parsedBefore = pos + 1
                        state = outerState
                        outerState = .TEXT
                    }
                default:
                    if lastCodePoint == U_HYPHEN_MINUS && lastLastCodePoint == U_HYPHEN_MINUS && pos > parsedBefore {
                        try error("\"--\" in comment not marking the end of it")
                    }
                }
            /* 10 */
            case .DOCUMENT_TYPE_DECLARATION_HEAD, .ENTITY_DECLARATION, .NOTATION_DECLARATION:
                switch codePoint {
                case U_LEFT_SQUARE_BRACKET, U_GREATER_THAN_SIGN:
                    if b == U_LEFT_SQUARE_BRACKET && !(state == .DOCUMENT_TYPE_DECLARATION_HEAD) {
                        try error("illegal character \(characterCitation(codePoint))")
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
                                        eventHandlers.forEach { eventHandler in eventHandler.documentTypeDeclaration(type: name, publicID: publicID, systemID: nil) }
                                        success = true
                                    }
                                }
                                else if theToken == "PUBLIC" {
                                    if items.count == 3 {
                                        if let publicID = (items[2] as? quotedParseResult)?.value
                                           {
                                            eventHandlers.forEach { eventHandler in eventHandler.documentTypeDeclaration(type: name, publicID: publicID, systemID:  nil) }
                                            success = true
                                        }
                                    }
                                    else if items.count == 4 {
                                        if let publicID = (items[2] as? quotedParseResult)?.value,
                                           let systemID = (items[3] as? quotedParseResult)?.value
                                        {
                                            eventHandlers.forEach { eventHandler in eventHandler.documentTypeDeclaration(type: name, publicID: publicID, systemID: systemID) }
                                            success = true
                                        }
                                    }
                                }
                            }
                            else {
                                eventHandlers.forEach { eventHandler in eventHandler.documentTypeDeclaration(type: name, publicID: nil, systemID: nil) }
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
                                    if declaredParameterEntityNames.contains(realEntityName) {
                                        try error("parameter entity with name \"\(realEntityName)\" declared more than once")
                                    }
                                    eventHandlers.forEach { eventHandler in eventHandler.parameterEntityDeclaration(name: realEntityName, value: value) }
                                    declaredParameterEntityNames.insert(realEntityName)
                                    success = true
                                }
                            }
                            else if items.count == 2 {
                                if let value = (items[1] as? quotedParseResult)?.value {
                                    if declaredEntityNames.contains(entityName) {
                                        try error("entity with name \"\(entityName)\" declared more than once")
                                    }
                                    eventHandlers.forEach { eventHandler in eventHandler.internalEntityDeclaration(name: entityName, value: value) }
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
                                                eventHandlers.forEach { eventHandler in eventHandler.unparsedEntityDeclaration(name: entityName, publicID: publicValue, systemID: systemValue, notation: notation.value) }
                                                externalEntityNames.insert(entityName)
                                                declaredEntityNames.insert(entityName)
                                                success = true
                                            }
                                        }
                                        else if items.count == 3 + systemShift {
                                            if declaredEntityNames.contains(entityName) {
                                                try error("entity with name \"\(entityName)\" declared more than once")
                                            }
                                            eventHandlers.forEach { eventHandler in eventHandler.externalEntityDeclaration(name: entityName, publicID: publicValue, systemID: systemValue) }
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
                                        eventHandlers.forEach { eventHandler in eventHandler.notationDeclaration(name: notationName, publicID: publicValue, systemID: systemValue) }
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
                                            eventHandlers.forEach { eventHandler in eventHandler.notationDeclaration(name: notationName, publicID: publicOrSystemValue, systemID: nil) }
                                        }
                                        else {
                                            eventHandlers.forEach { eventHandler in eventHandler.notationDeclaration(name: notationName, publicID: nil, systemID: publicOrSystemValue) }
                                        }
                                        declaredNotationNames.insert(notationName)
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
                        try error("illegal \(characterCitation(codePoint))")
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
                        if !isNameCharacter(codePoint) {
                            try error("illegal \(characterCitation(codePoint)) in element name")
                        }
                    }
                    else {
                        if !(isNameStartCharacter(codePoint) || (state == .ENTITY_DECLARATION && b == U_PERCENT_SIGN && items.count == 0)) {
                            try error("illegal \(characterCitation(codePoint)) in declaration")
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
                switch codePoint {
                case U_RIGHT_SQUARE_BRACKET:
                    state = .DOCUMENT_TYPE_DECLARATION_TAIL
                case U_LESS_THAN_SIGN:
                    state = .JUST_STARTED_WITH_LESS_THAN_SIGN
                    outerState = .INTERNAL_SUBSET
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
                        token = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                        tokenStart = -1
                    }
                case U_GREATER_THAN_SIGN:
                    if quoteSign == 0 {
                        if tokenStart >= 0 {
                            token = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
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
                                eventHandlers.forEach { eventHandler in eventHandler.elementDeclaration(name: theToken, literal: String(decoding: data.subdata(in: outerParsedBefore..<pos+1), as: UTF8.self)) }
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
                                eventHandlers.forEach { eventHandler in eventHandler.attributeListDeclaration(name: theToken, literal: String(decoding: data.subdata(in: outerParsedBefore..<pos+1), as: UTF8.self)) }
                                declaredAttributeListNames.insert(theToken)
                            }
                            else {
                                try error("element declaration without name")
                            }
                            
                            token = nil
                        }
                        parsedBefore = pos + 1
                        state = outerState; outerState = .TEXT
                    }
                case U_QUOTATION_MARK, U_APOSTROPHE:
                    if b == quoteSign {
                        quoteSign = 0
                    }
                    else {
                        if tokenStart >= 0 {
                            token = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                            tokenStart = -1
                        }
                        quoteSign = b
                    }
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    if tokenStart >= 0 {
                        token = String(decoding: data.subdata(in: tokenStart..<pos), as: UTF8.self)
                        tokenStart = -1
                    }
                default:
                    if token == nil && tokenStart < 0 {
                        tokenStart = pos
                    }
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
                    try attributes.forEach { attributeName, attributeValue in
                        switch attributeName {
                        case "version": version = attributeValue
                        case "encoding": encoding = attributeValue
                        case "standalone": standalone = attributeValue
                        default: try error("unkonwn attribute \"\(attributeName)\" in XML declaration")
                        }
                    }
                    if let theVersion = version {
                        eventHandlers.forEach { eventHandler in eventHandler.xmlDeclaration(version: theVersion, encoding: encoding, standalone: standalone) }
                    }
                    else {
                        try error("uncomplete XML declaration, at least the version should be set")
                    }
                    name = nil
                    attributes = [String:String]()
                    state = .TEXT
                    isWhitespace = true
                    parsedBefore = pos + 1
                }
                else {
                    try error("expecting \(characterCitation(U_GREATER_THAN_SIGN)) to end XML declaration")
                }
            /* 15 */
            case .DOCUMENT_TYPE_DECLARATION_TAIL:
                switch codePoint {
                case U_GREATER_THAN_SIGN:
                    state = .TEXT
                    isWhitespace = true
                    parsedBefore = pos + 1
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION, U_SOLIDUS:
                    break
                default:
                    try error("illegal \(characterCitation(codePoint)) in document type declaration after internal subset")
                }
            }
            
            lastLastCodePoint = lastCodePoint
            lastCodePoint = codePoint
        }
        pos += 1
        
        if elementLevel > 0 {
            try error("document is not finished: \(elementLevel > 1 ? "elements" : "element") \(ancestors.peekAll().reversed().map{ "\"\($0)\"" }.joined(separator: ", ")) \(elementLevel > 1 ? "are" : "is") not closed")
        }
        else if state != .TEXT {
            try error("junk at end of document")
        }
        
        eventHandlers.forEach { eventHandler in eventHandler.documentEnd() }
    }
}
