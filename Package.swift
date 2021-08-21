// swift-tools-version:5.4.0
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
        .package(url: "https://github.com/stefanspringer1/SwiftXMLInterfaces", from: "0.1.26"),
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
