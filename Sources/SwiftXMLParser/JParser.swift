//
//  JParser.swift
//
//  Created 2021 by Stefan Springer, https://stefanspringer.com
//  License: Apache License 2.0

import Foundation
import SwiftXMLInterfaces

public extension String {
    
    func toJSONText() -> String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\u{8}", with: "\\b")
            .replacingOccurrences(of: "\u{C}", with: "\\f")
            .replacingOccurrences(of: "\u{A}", with: "\\n")
            .replacingOccurrences(of: "\u{D}", with: "\\r")
            .replacingOccurrences(of: "\u{9}", with: "\\t")
            .replacingOccurrences(of: "\u{22}", with: "\\b")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    func fromJSONText() -> String {
        self
            .replacingOccurrences(of: "\\b", with: "\u{8}")
            .replacingOccurrences(of: "\\f", with: "\u{C}")
            .replacingOccurrences(of: "\\n", with: "\u{A}")
            .replacingOccurrences(of: "\\r", with: "\u{D}")
            .replacingOccurrences(of: "\\t", with: "\u{9}")
            .replacingOccurrences(of: "\\b", with: "\u{22}")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
    
}

public class JParser: Parser {
    
    let rootName: String
    let arrayItemName: String
    
    public init(rootName: String? = nil, arrayItemName: String? = nil) {
        self.rootName = rootName ?? "root"
        self.arrayItemName = arrayItemName ?? "x"
    }
    
    public func parse(
        fromData data: Data,
        sourceInfo: String? = nil,
        eventHandlers: [XEventHandler]
    ) throws {
        
        var line = 1
        var column = 0
        
        func error(_ message: String, offset: Int = 0) throws {
            throw ParseError("\(sourceInfo != nil ? "\(sourceInfo ?? ""):" : "")\(max(1,line-offset)):\(column):E: \(message)")
        }
        
        func characterCitation(_ codePoint: UnicodeCodePoint) -> String {
            if codePoint >= U_SPACE && codePoint <= U_MAX_ASCII {
                return "\"\(Character(UnicodeScalar(codePoint)!))\""
            }
            else {
                return "character x\(String(format: "%X", codePoint))"
            }
        }
        
        var binaryPosition = -1
        
        var valueStart = -1
        
        enum State {
            case OBJECT_AWAITING_NAME
            case OBJECT_AWAITING_COLON
            case OBJECT_AWAITING_VALUE
            case OBJECT_AWAITING_COMMA_OR_END
            case ARRAY_AWAITING_THING
            case ARRAY_AWAITING_COMMA_OR_END
            case TEXT
            case TEXT_ESCAPE
            case NON_TEXT_VALUE
        }

        var elementNames = Stack<String>()
        
        var states = Stack<State>()
        states.push(.ARRAY_AWAITING_THING)
        
        var expectedUTF8Rest = 0
        
        var bracketLevel = 0
        
        do {
            let startTextRange = XTextRange(startLine: 0, startColumn: 0, endLine: 0, endColumn: 0)
            let startDataRange = XDataRange(binaryStart: 0, binaryUntil: 0)
            eventHandlers.forEach { eventHandler in
                eventHandler.elementStart(
                    name: rootName,
                    attributes: nil,
                    textRange: startTextRange,
                    dataRange: startDataRange
                )
            }
        }
        
        func getValue() throws -> String {
            if valueStart < 0 {
                try error("wrong start index of value") // should not happen
            }
            let value = String(decoding: data.subdata(in: valueStart..<binaryPosition), as: UTF8.self)
            valueStart = -1
            return value
        }
        
        eventHandlers.forEach { eventHandler in eventHandler.documentStart() }
        
        var codePoint: UnicodeCodePoint = 0
        var lastCodePoint: UnicodeCodePoint = 0
        
        var shift = 0
        var binaryPositionOffset = 0
        
        binaryLoop: for b in data {
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
            
//            if b != U_SPACE, let state = states.peek() {
//                print("### \(state) / bracket level: \(bracketLevel) -> \(characterCitation(b))")
//            }
            
            switch states.peek() {
            case .ARRAY_AWAITING_THING:
                switch codePoint {
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                case U_LEFT_CURLY_BRACKET:
                    states.change(.ARRAY_AWAITING_COMMA_OR_END)
                    states.push(.OBJECT_AWAITING_NAME)
                    bracketLevel += 1
                case U_LEFT_SQUARE_BRACKET:
                    states.change(.ARRAY_AWAITING_COMMA_OR_END)
                    states.push(.ARRAY_AWAITING_THING)
                    bracketLevel += 1
                case U_QUOTATION_MARK:
                    states.push(.TEXT)
                    valueStart = binaryPosition + 1 - binaryPositionOffset
                case U_RIGHT_SQUARE_BRACKET:
                    _ = states.pop()
                    bracketLevel -= 1
                    switch states.pop() {
                    case .OBJECT_AWAITING_VALUE:
                        if let theElementName = elementNames.pop() {
                            let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                            let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                            eventHandlers.forEach { eventHandler in
                                eventHandler.elementEnd(
                                    name: theElementName,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.push(.OBJECT_AWAITING_COMMA_OR_END)
                    case .ARRAY_AWAITING_THING:
                        states.push(.ARRAY_AWAITING_COMMA_OR_END)
                    default:
                        try error("undefined state") // should not happen
                    }
                default:
                    var skip = false
                    if (binaryPosition < 3) {
                        switch binaryPosition {
                        case 0: if b == U_BOM_1 { skip = true }
                        case 1: if b == U_BOM_2 && data[0] == U_BOM_1 { skip = true }
                        case 2: if b == U_BOM_3 && data[1] == U_BOM_2 && data[0] == U_BOM_1 { skip = true }
                        default: break
                        }
                    }
                    if !skip {
                        states.push(.NON_TEXT_VALUE)
                        valueStart = binaryPosition - binaryPositionOffset
                    }
                }
            case .OBJECT_AWAITING_NAME:
                switch codePoint {
                case U_QUOTATION_MARK:
                    states.push(.TEXT)
                    valueStart = binaryPosition + 1 - binaryPositionOffset
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                default:
                    try error("invalid character \(characterCitation(codePoint)) in object")
                }
            case .OBJECT_AWAITING_COLON:
                switch codePoint {
                case U_COLON:
                    states.change(.OBJECT_AWAITING_VALUE)
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                default:
                    try error("invalid character \(characterCitation(codePoint)) in object")
                    break
                }
            case .OBJECT_AWAITING_VALUE:
                switch codePoint {
                case U_QUOTATION_MARK:
                    valueStart = binaryPosition + 1 - binaryPositionOffset
                    states.push(.TEXT)
                case U_LEFT_CURLY_BRACKET:
                    states.push(.OBJECT_AWAITING_NAME)
                    bracketLevel += 1
                case U_LEFT_SQUARE_BRACKET:
                    states.push(.ARRAY_AWAITING_THING)
                    bracketLevel += 1
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                default:
                    states.push(.NON_TEXT_VALUE)
                    valueStart = binaryPosition - binaryPositionOffset
                }
            case .NON_TEXT_VALUE:
                switch codePoint {
                case U_COMMA:
                    _ = states.pop()
                    switch states.pop() {
                    case .ARRAY_AWAITING_THING:
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementStart(
                                name: arrayItemName,
                                attributes: nil,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        try eventHandlers.forEach { eventHandler in
                            eventHandler.text(
                                text: try getValue(),
                                whitespace: .UNKNOWN,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementEnd(
                                name: arrayItemName,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        states.push(.ARRAY_AWAITING_THING)
                    case .OBJECT_AWAITING_VALUE:
                        let value = try getValue()
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in
                                eventHandler.text(
                                    text: value,
                                    whitespace: .UNKNOWN,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in
                                eventHandler.elementEnd(
                                    name: theElementName,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.push(.OBJECT_AWAITING_NAME)
                    default:
                        try error("misplaced comma")
                    }
                case U_RIGHT_SQUARE_BRACKET:
                    _ = states.pop()
                    switch states.pop() {
                    case .ARRAY_AWAITING_THING:
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementStart(
                                name: arrayItemName,
                                attributes: nil,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        let value = try getValue()
                        if value != "null" {
                            eventHandlers.forEach {
                                eventHandler in eventHandler.text(
                                    text: value,
                                    whitespace: .UNKNOWN,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementEnd(
                                name: arrayItemName,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        bracketLevel -= 1
                        switch states.pop() {
                        case .OBJECT_AWAITING_VALUE:
                            states.push(.OBJECT_AWAITING_COMMA_OR_END)
                        case .ARRAY_AWAITING_THING:
                            states.push(.ARRAY_AWAITING_COMMA_OR_END)
                        default:
                            try error("undefined state") // should not happen
                        }
                    default:
                        try error("misplaced right square breacket")
                    }
                case U_RIGHT_CURLY_BRACKET:
                    _ = states.pop()
                    switch states.pop() {
                    case .OBJECT_AWAITING_VALUE:
                        let value = try getValue()
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in
                                eventHandler.text(
                                    text: value,
                                    whitespace: .UNKNOWN,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in
                                eventHandler.elementEnd(
                                    name: theElementName,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                    default:
                        try error("misplaced right square breacket")
                    }
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    _ = states.pop()
                    switch states.pop() {
                    case .OBJECT_AWAITING_VALUE:
                        let value = try getValue()
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in
                                eventHandler.text(
                                    text: value,
                                    whitespace: .UNKNOWN,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in
                                eventHandler.elementEnd(
                                    name: theElementName,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.push(.OBJECT_AWAITING_COMMA_OR_END)
                    case .ARRAY_AWAITING_THING:
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementStart(
                                name: arrayItemName,
                                attributes: nil,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        let value = try getValue()
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in
                                eventHandler.text(
                                    text: value,
                                    whitespace: .UNKNOWN,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementEnd(
                                name: arrayItemName,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        states.push(.ARRAY_AWAITING_COMMA_OR_END)
                    default:
                        try error("undefined state") // should not happen
                    }
                default:
                    break
                }
            case .TEXT:
                switch codePoint {
                case U_REVERSE_SOLIDUS:
                    states.push(.TEXT_ESCAPE)
                case U_QUOTATION_MARK:
                    let text = try getValue().fromJSONText()
                    valueStart = -1
                    _ = states.pop()
                    switch states.pop() {
                    case .ARRAY_AWAITING_THING:
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementStart(
                                name: arrayItemName,
                                attributes: nil,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        eventHandlers.forEach { eventHandler in
                            eventHandler.text(
                                text: text,
                                whitespace: .UNKNOWN,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementEnd(
                                name: arrayItemName,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        states.push(.ARRAY_AWAITING_COMMA_OR_END)
                    case .OBJECT_AWAITING_NAME:
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        eventHandlers.forEach { eventHandler in
                            eventHandler.elementStart(
                                name: text,
                                attributes: nil,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        elementNames.push(text)
                        states.push(.OBJECT_AWAITING_COLON)
                    case .OBJECT_AWAITING_VALUE:
                        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                        eventHandlers.forEach { eventHandler in
                            eventHandler.text(
                                text: text,
                                whitespace: .UNKNOWN,
                                textRange: textRange,
                                dataRange: dataRange
                            )
                        }
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in
                                eventHandler.elementEnd(
                                    name: theElementName,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.push(.OBJECT_AWAITING_COMMA_OR_END)
                    default:
                        try error("undefined state") // should not happen
                    }
                default:
                    break
                }
            case .ARRAY_AWAITING_COMMA_OR_END:
                switch codePoint {
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                case U_COMMA:
                    _ = states.pop()
                    states.push(.ARRAY_AWAITING_THING)
                case U_RIGHT_SQUARE_BRACKET:
                    _ = states.pop()
                    if states.peek() == .OBJECT_AWAITING_VALUE {
                        if let theElementName = elementNames.pop() {
                            let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                            let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                            eventHandlers.forEach { eventHandler in
                                eventHandler.elementEnd(
                                    name: theElementName,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.change(.OBJECT_AWAITING_COMMA_OR_END)
                    }
                    bracketLevel -= 1
                default:
                    try error("invalid character \(characterCitation(codePoint)) in array")
                }
            case .OBJECT_AWAITING_COMMA_OR_END:
                switch codePoint {
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                case U_COMMA:
                    _ = states.pop()
                    states.push(.OBJECT_AWAITING_NAME)
                case U_RIGHT_CURLY_BRACKET:
                    _ = states.pop()
                    if states.peek() == .OBJECT_AWAITING_VALUE {
                        if let theElementName = elementNames.pop() {
                            let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
                            let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
                            eventHandlers.forEach { eventHandler in
                                eventHandler.elementEnd(
                                    name: theElementName,
                                    textRange: textRange,
                                    dataRange: dataRange
                                )
                            }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.change(.OBJECT_AWAITING_COMMA_OR_END)
                    }
                    bracketLevel -= 1
                default:
                    try error("invalid character \(characterCitation(codePoint)) in object")
                }
            case .TEXT_ESCAPE:
                _ = states.pop()
            case .none:
                try error("undefined state") // should not happen
            }
            lastCodePoint = codePoint
        }
        binaryPosition += 1
        
        if bracketLevel > 0 {
            try error("document not finished")
        }
        
        let textRange = XTextRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
        let dataRange = XDataRange(binaryStart: binaryPosition - binaryPositionOffset, binaryUntil: binaryPosition - binaryPositionOffset)
        eventHandlers.forEach { eventHandler in
            eventHandler.elementEnd(
                name: rootName,
                textRange: textRange,
                dataRange: dataRange
            )
        }
    }
}
