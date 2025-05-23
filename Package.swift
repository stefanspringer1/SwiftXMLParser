// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftXMLParser",
    products: [
        .library(
            name: "SwiftXMLParser",
            targets: ["SwiftXMLParser"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stefanspringer1/SwiftXMLInterfaces", from: "5.0.3"),
    ],
    targets: [
        .target(
            name: "SwiftXMLParser",
            dependencies: ["SwiftXMLInterfaces"]),
        .testTarget(
            name: "SwiftXMLParserTests",
            dependencies: ["SwiftXMLParser"]),
    ]
)
