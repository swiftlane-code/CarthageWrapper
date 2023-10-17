// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "CarthageWrapper",
	platforms: [.macOS(.v12)],
    products: [
        .executable(name: "CarthageWrapper", targets: ["CarthageWrapper"]),
    ],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser", "1.1.4"..<"1.2.0"), // 1.2.0 Bugs (default value for @Flag)
		.package(url: "https://github.com/swiftlane-code/SwiftlaneCore.git", from: "0.9.0"),
		.package(url: "https://github.com/swiftlane-code/Swiftlane.git", from: "0.9.0"),
	],
	targets: [
		.executableTarget(
			name: "CarthageWrapper",
			dependencies: [
				.product(name: "SwiftlaneLogging", package: "SwiftlaneCore"),
				.product(name: "SwiftlaneShell", package: "SwiftlaneCore"),
				.product(name: "SwiftlaneCoreServices", package: "SwiftlaneCore"),
				.product(name: "Networking", package: "Swiftlane"),
				.product(name: "GitLabAPI", package: "Swiftlane"),
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
			]
		),
		.testTarget(
			name: "CarthageWrapperTests",
			dependencies: ["CarthageWrapper"]
		),
	]
)
