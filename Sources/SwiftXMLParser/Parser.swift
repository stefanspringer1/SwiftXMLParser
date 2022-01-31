//
//  Parser.swift
//
//  Created 2021 by Stefan Springer, https://stefanspringer.com
//  License: Apache License 2.0

import Foundation
import SwiftXMLInterfaces

protocol Parser {
    func parse(fromData: Data, sourceInfo: String?, eventHandlers: [XEventHandler]) throws
}

class ConvenienceParser {
    
    let parser: Parser
    let mainEventHandler: XEventHandler
    
    public init(parser: Parser, mainEventHandler: XEventHandler) {
        self.parser = parser
        self.mainEventHandler = mainEventHandler
    }
    
    public func parse(
        fromPath path: String,
        sourceInfo: String? = nil,
        eventHandlers: [XEventHandler]? = nil
    ) throws {
        try autoreleasepool {
            let data: Data = try Data(contentsOf: URL(fileURLWithPath: path)/*, options: [.alwaysMapped]*/)
            try parse(fromData: data, sourceInfo: sourceInfo ?? path, eventHandlers: eventHandlers)
        }
    }

    public func parse(
        fromText text: String,
        sourceInfo: String? = nil,
        eventHandlers: [XEventHandler]? = nil
    ) throws {
        let _data = text.data(using: .utf8)
        if let data = _data {
            try parse(fromData: data, sourceInfo: sourceInfo, eventHandlers: eventHandlers)
        }
        else {
            throw XParseError("fatal error: could not get binary data from text") // should never happen
        }
    }
    
    public func parse(
        fromData data: Data,
        sourceInfo: String? = nil,
        eventHandlers: [XEventHandler]? = nil
    ) throws {
        let handlers: [XEventHandler]
        if let theEventHandlers = eventHandlers {
            handlers = [mainEventHandler] + theEventHandlers
        }
        else {
            handlers = [mainEventHandler]
        }
        try parser.parse(fromData: data, sourceInfo: sourceInfo, eventHandlers: handlers)
    }

}
