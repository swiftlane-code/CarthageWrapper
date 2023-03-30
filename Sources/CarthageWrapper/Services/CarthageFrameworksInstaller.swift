//

import Foundation
import SwiftlaneLogging
import SwiftlanePaths

struct CarthageFrameworksInstaller {
	let logger: Logging
	let filesManager: FSManaging

	let carthageBuildDir: AbsolutePath

	func installFrameworks(from directory: AbsolutePath) throws {
		let xcframeworksDir = carthageBuildDir
		let frameworksDir = try xcframeworksDir.appending(path: "iOS")

		if !filesManager.directoryExists(xcframeworksDir) {
			try filesManager.mkdir(xcframeworksDir)
		}
		if !filesManager.directoryExists(frameworksDir) {
			try filesManager.mkdir(frameworksDir)
		}

		logger.important("Moving xcframeworks to \(xcframeworksDir.string.quoted)...")

		try filesManager.find(directory)
			.filter { $0.hasSuffix(".xcframework") }
			.forEach { xcPath in
				logger.important("\t* " + xcPath.lastComponent.string)

				let xcDestination = xcframeworksDir.appending(path: xcPath.lastComponent)
				if filesManager.directoryExists(xcDestination) {
					try filesManager.delete(xcDestination)
				}
				try filesManager.move(xcPath, newPath: xcDestination)

				// TODO: crutch

				if xcPath.lastComponent.string == "FirebaseCrashlytics.xcframework" {
					let firebaseCrashlyticsPath = xcPath.deletingLastComponent // <- "FirebaseCrashlytics"
					let crashlyticsUtilsDestination = try xcframeworksDir.appending(path: "FirebaseCrashlyticsUtils")
					try filesManager.delete(crashlyticsUtilsDestination)
					try filesManager.move(firebaseCrashlyticsPath, newPath: crashlyticsUtilsDestination)
				}
			}

		logger.important("Moving frameworks to \(frameworksDir.string.quoted)...")

		try filesManager.find(directory)
			.filter { $0.hasSuffix(".framework") }
			.forEach { frameworkPath in
				logger.important("\t* " + frameworkPath.lastComponent.string)

				let destination = frameworksDir.appending(path: frameworkPath.lastComponent)
				if filesManager.directoryExists(destination) {
					try filesManager.delete(destination)
				}
				try filesManager.move(frameworkPath, newPath: destination)
			}
	}
}
