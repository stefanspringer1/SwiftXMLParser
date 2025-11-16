// swift-tools-version:6.0
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
        .package(url: "https://github.com/stefanspringer1/SwiftXMLInterfaces", from: "8.0.1"),
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
