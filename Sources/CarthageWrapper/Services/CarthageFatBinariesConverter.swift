//

import SwiftlaneLogging
import SwiftlanePaths
import SwiftlaneShell

struct CarthageFatBinariesConverter {
	let logger: Logging
	let shell: ShellExecuting
	let filesManager: FSManaging
	let converter: FatBinaryConverter

	let carthageBuildDir: AbsolutePath

	func convert() throws {
		logger.important("Converting fat binaries to xcframeworks...")

		let frameworksDir = try carthageBuildDir.appending(path: "iOS")
		let outputDir = frameworksDir.deletingLastComponent

		try filesManager.ls(frameworksDir)
			.filter { $0.hasSuffix(".framework") }
			.forEach { frameworkPath in
				if frameworkPath.lastComponent.string == "Firebase.framework" {
					logger.important("👀 Skipped Firebase.framework")
					return
				}

				let tmpXCFrameworkPath = try outputDir
					.appending(path: "tmp_" + frameworkPath.lastComponent.string)
					.replacingExtension(with: ".xcframework")

				let finalXCFrameworkPath = outputDir
					.appending(path: frameworkPath.lastComponent)
					.replacingExtension(with: ".xcframework")

				if filesManager.directoryExists(tmpXCFrameworkPath) {
					try filesManager.delete(tmpXCFrameworkPath)
				}

				if filesManager.directoryExists(finalXCFrameworkPath) {
					try filesManager.delete(finalXCFrameworkPath)
				}

				try converter.convertToXCFramework(
					frameworkPath: frameworkPath,
					outputPath: tmpXCFrameworkPath
				)

				try filesManager.move(tmpXCFrameworkPath, newPath: finalXCFrameworkPath)
				try filesManager.delete(frameworkPath)
			}
	}
}
