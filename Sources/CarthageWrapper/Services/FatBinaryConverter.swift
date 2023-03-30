//

import Foundation
import SwiftlaneLogging
import SwiftlanePaths
import SwiftlaneShell

struct FatBinaryConverter {
	enum Errors: Error {
		case notAFramework
		case binaryNotFound
		case outputPathIsNotXCFramework
	}

	enum Architecture: String {
		case arm64
		case x86_64
	}

	let logger: Logging
	let shell: ShellExecuting
	let filesManager: FSManaging

	func convertToXCFramework(
		frameworkPath: AbsolutePath,
		outputPath: AbsolutePath
	) throws {
		guard frameworkPath.pathExtension == Constants.framework else {
			logger.error("\(frameworkPath.string.quoted) is not a path to *.\(Constants.framework)")
			throw Errors.notAFramework
		}

		guard outputPath.pathExtension == Constants.xcframework else {
			logger.error("Output path \(frameworkPath.string.quoted) should have \".\(Constants.xcframework)\" extension.")
			throw Errors.outputPathIsNotXCFramework
		}

		// swiftformat:disable:next wrap
		logger.important("👀 Converting fat binary framework \(frameworkPath.string.quoted) to xcframework \(outputPath.string.quoted)")

		let frameworkName = frameworkPath.lastComponent.deletingExtension
		let binaryPath = frameworkPath.appending(path: frameworkName)

		logger.important("👀 Assuming that binary path is \(binaryPath.string.quoted)")

		// Print fat binary info
		try shell.run("xcrun lipo -info " + binaryPath.string.quoted, log: .commandAndOutput(outputLogLevel: .debug))

		// === Create thinned binaries ===

		var thinnedFrameworks = [AbsolutePath]()

		let slicedDir = try frameworkPath.deletingLastComponent.appending(path: "sliced")

		if filesManager.directoryExists(slicedDir) {
			try filesManager.delete(slicedDir)
		}

		func slice(arch: Architecture) throws {
			let thinnedVariantDir = try slicedDir
				.appending(path: frameworkName)
				.appending(path: arch.rawValue)

			let thinnedFramework = thinnedVariantDir.appending(path: frameworkPath.lastComponent)
			let thinnedBinary = thinnedFramework.appending(path: frameworkName)

			logger.important("👀 Creating thinned \(arch) version...")

			try filesManager.mkdir(thinnedVariantDir)
			try filesManager.copy(frameworkPath, to: thinnedFramework)

			try shell.run(
				[
					"xcrun lipo -thin",
					arch.rawValue,
					thinnedBinary.string.quoted,
					"-o",
					thinnedBinary.string.quoted,
				],
				log: .commandAndOutput(outputLogLevel: .debug)
			)

			try shell.run(
				[
					"xcrun lipo -info",
					thinnedBinary.string.quoted,
				],
				log: .commandAndOutput(outputLogLevel: .debug)
			)

			thinnedFrameworks.append(thinnedFramework)
		}

		// Fat binaries can not contain same architecture multiple times for different platforms
		// so x86_64 is always built for simulator and arm64 is always built for device.
		try slice(arch: .x86_64)
		try slice(arch: .arm64)

		// === Create xcframework ===

		logger.important("👀 Creating \(outputPath.string.quoted)...")

		try shell.run(
			[
				"xcodebuild -create-xcframework",
				thinnedFrameworks
					.map { "-framework " + $0.string.quoted }
					.joined(separator: " "),
				"-output",
				outputPath.string.quoted,
			],
			log: .commandAndOutput(outputLogLevel: .important)
		)

		logger.success("Successfully created \(outputPath.string.quoted)")

		try filesManager.delete(slicedDir)
	}
}
