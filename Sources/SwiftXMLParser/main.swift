//
//  File.swift
//  
//
//  Created by Stefan Springer on 03.07.22.
//

import Foundation

let path = "/Users/stefan/Projekte/Beuth-Content/minimal 2/00000000.x0000000/d0000000.xml"

let data: Data = try Data(contentsOf: URL(fileURLWithPath: path))

data.forEach { print($0) }

xParseTest(forData: data, sourceInfo: path, fullDebugOutput: true)
