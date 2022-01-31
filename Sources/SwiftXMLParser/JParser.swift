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
        var row = 0
        
        func error(_ message: String, offset: Int = 0) throws {
            throw ParseError("\(sourceInfo != nil ? "\(sourceInfo ?? ""):" : "")\(max(1,line-offset)):\(row):E: \(message)")
        }
        
        func characterCitation(_ b: Data.Element) -> String {
            if b & UTF8_TEMPLATE == 0 && b >= U_SPACE {
                return "\"\(Character(UnicodeScalar(b)))\""
            }
            else {
                return "character x\(String(format: "%X", b))"
            }
        }
        
        var pos = -1
        
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
        
        eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: rootName, attributes: nil) }
        
        func getValue() throws -> String {
            if valueStart < 0 {
                try error("wrong start index of value") // should not happen
            }
            let value = String(decoding: data.subdata(in: valueStart..<pos), as: UTF8.self)
            valueStart = -1
            return value
        }
        
        eventHandlers.forEach { eventHandler in eventHandler.documentStart() }
        
        var lastB: Data.Element = 0
        
        for b in data {
            pos += 1
            if lastB == U_LINE_FEED {
                line += 1
                row = 0
            }
            
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
            
            if expectedUTF8Rest == 0 {
                row += 1
            }
            
//            if b != U_SPACE, let state = states.peek() {
//                print("### \(state) / bracket level: \(bracketLevel) -> \(characterCitation(b))")
//            }
            
            switch states.peek() {
            case .ARRAY_AWAITING_THING:
                switch b {
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
                    valueStart = pos + 1
                case U_RIGHT_SQUARE_BRACKET:
                    _ = states.pop()
                    bracketLevel -= 1
                    switch states.pop() {
                    case .OBJECT_AWAITING_VALUE:
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: theElementName) }
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
                    if (pos < 3) {
                        switch pos {
                        case 0: if b == U_BOM_1 { skip = true }
                        case 1: if b == U_BOM_2 && data[0] == U_BOM_1 { skip = true }
                        case 2: if b == U_BOM_3 && data[1] == U_BOM_2 && data[0] == U_BOM_1 { skip = true }
                        default: break
                        }
                    }
                    if !skip {
                        states.push(.NON_TEXT_VALUE)
                        valueStart = pos
                    }
                }
            case .OBJECT_AWAITING_NAME:
                switch b {
                case U_QUOTATION_MARK:
                    states.push(.TEXT)
                    valueStart = pos + 1
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                default:
                    try error("invalid character \(characterCitation(b)) in object")
                }
            case .OBJECT_AWAITING_COLON:
                switch b {
                case U_COLON:
                    states.change(.OBJECT_AWAITING_VALUE)
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                default:
                    try error("invalid character \(characterCitation(b)) in object")
                    break
                }
            case .OBJECT_AWAITING_VALUE:
                switch b {
                case U_QUOTATION_MARK:
                    valueStart = pos + 1
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
                    valueStart = pos
                }
            case .NON_TEXT_VALUE:
                switch b {
                case U_COMMA:
                    _ = states.pop()
                    switch states.pop() {
                    case .ARRAY_AWAITING_THING:
                        eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: arrayItemName, attributes: nil) }
                        try eventHandlers.forEach { eventHandler in eventHandler.text(text: try getValue(), whitespace: .UNKNOWN) }
                        eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: arrayItemName) }
                        states.push(.ARRAY_AWAITING_THING)
                    case .OBJECT_AWAITING_VALUE:
                        let value = try getValue()
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in eventHandler.text(text: value, whitespace: .UNKNOWN) }
                        }
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: theElementName) }
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
                        eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: arrayItemName, attributes: nil) }
                        let value = try getValue()
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in eventHandler.text(text: value, whitespace: .UNKNOWN) }
                        }
                        eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: arrayItemName) }
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
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in eventHandler.text(text: value, whitespace: .UNKNOWN) }
                        }
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: theElementName) }
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
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in eventHandler.text(text: value, whitespace: .UNKNOWN) }
                        }
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: theElementName) }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.push(.OBJECT_AWAITING_COMMA_OR_END)
                    case .ARRAY_AWAITING_THING:
                        eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: arrayItemName, attributes: nil) }
                        let value = try getValue()
                        if value != "null" {
                            eventHandlers.forEach { eventHandler in eventHandler.text(text: value, whitespace: .UNKNOWN) }
                        }
                        eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: arrayItemName) }
                        states.push(.ARRAY_AWAITING_COMMA_OR_END)
                    default:
                        try error("undefined state") // should not happen
                    }
                default:
                    break
                }
            case .TEXT:
                switch b {
                case U_REVERSE_SOLIDUS:
                    states.push(.TEXT_ESCAPE)
                case U_QUOTATION_MARK:
                    let text = try getValue().fromJSONText()
                    valueStart = -1
                    _ = states.pop()
                    switch states.pop() {
                    case .ARRAY_AWAITING_THING:
                        eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: arrayItemName, attributes: nil) }
                        eventHandlers.forEach { eventHandler in eventHandler.text(text: text, whitespace: .UNKNOWN) }
                        eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: arrayItemName) }
                        states.push(.ARRAY_AWAITING_COMMA_OR_END)
                    case .OBJECT_AWAITING_NAME:
                        eventHandlers.forEach { eventHandler in eventHandler.elementStart(name: text, attributes: nil) }
                        elementNames.push(text)
                        states.push(.OBJECT_AWAITING_COLON)
                    case .OBJECT_AWAITING_VALUE:
                        eventHandlers.forEach { eventHandler in eventHandler.text(text: text, whitespace: .UNKNOWN) }
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: theElementName) }
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
                switch b {
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                case U_COMMA:
                    _ = states.pop()
                    states.push(.ARRAY_AWAITING_THING)
                case U_RIGHT_SQUARE_BRACKET:
                    _ = states.pop()
                    if states.peek() == .OBJECT_AWAITING_VALUE {
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: theElementName) }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.change(.OBJECT_AWAITING_COMMA_OR_END)
                    }
                    bracketLevel -= 1
                default:
                    try error("invalid character \(characterCitation(b)) in array")
                }
            case .OBJECT_AWAITING_COMMA_OR_END:
                switch b {
                case U_SPACE, U_LINE_FEED, U_CARRIAGE_RETURN, U_CHARACTER_TABULATION:
                    break
                case U_COMMA:
                    _ = states.pop()
                    states.push(.OBJECT_AWAITING_NAME)
                case U_RIGHT_CURLY_BRACKET:
                    _ = states.pop()
                    if states.peek() == .OBJECT_AWAITING_VALUE {
                        if let theElementName = elementNames.pop() {
                            eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: theElementName) }
                        }
                        else {
                            try error("undefined state") // should not happen
                        }
                        states.change(.OBJECT_AWAITING_COMMA_OR_END)
                    }
                    bracketLevel -= 1
                default:
                    try error("invalid character \(characterCitation(b)) in object")
                }
            case .TEXT_ESCAPE:
                _ = states.pop()
            case .none:
                try error("undefined state") // should not happen
            }
            lastB = b
        }
        pos += 1
        
        if bracketLevel > 0 {
            try error("document not finished")
        }
        
        eventHandlers.forEach { eventHandler in eventHandler.elementEnd(name: rootName) }
    }
}
