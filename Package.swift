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
        .package(url: "https://github.com/stefanspringer1/XMLInterfaces", from: "0.1.5"),
    ],
    targets: [
        .target(
            name: "SwiftXMLParser",
            dependencies: ["XMLInterfaces"]),
        .testTarget(
            name: "SwiftXMLParserTests",
            dependencies: ["SwiftXMLParser"]),
    ]
)
