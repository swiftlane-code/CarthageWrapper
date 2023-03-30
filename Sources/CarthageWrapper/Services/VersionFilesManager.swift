//

import SwiftlaneLogging
import SwiftlanePaths

struct VersionFilesManager {
	let fileManager: FSManager
	let logger: Logging
	let carthageBuildDir: AbsolutePath
	let versionFileExtension: String = "smversion"

	func calculateVersionFilePathFor(libName: String) throws -> AbsolutePath {
		return try carthageBuildDir.appending(path: "\(libName).\(versionFileExtension)")
	}

	func isLocalLibVersionEquals(for lib: Lib) throws -> Bool {
		let versionFilePath = try calculateVersionFilePathFor(libName: lib.name)

		guard fileManager.fileExists(versionFilePath) else {
			return false
		}

		let rawVersionContent = try fileManager.readText(versionFilePath, log: false)
		let localLibVersion = rawVersionContent.split(whereSeparator: \.isNewline).first!

		return lib.version == String(localLibVersion)
	}

	func deleteVersionFileFor(libName: String) throws {
		let filePath = try calculateVersionFilePathFor(libName: libName)
		if fileManager.fileExists(filePath) {
			try fileManager.delete(filePath)
		}
	}

	func saveLibVersionFor(_ lib: Lib) throws {
		let versionFilePath = try calculateVersionFilePathFor(libName: lib.name)
		try fileManager.write(versionFilePath, text: lib.version)
	}

	func cleanUnusedSmversionFiles(libs: [Lib]) throws {
		logger.important("🧹 Cleaning non-required \(versionFileExtension) files...")

		let dependeciesVersionFiles = try libs.map { lib in
			try calculateVersionFilePathFor(libName: lib.name)
		}

		guard fileManager.directoryExists(carthageBuildDir) else {
			return
		}

		let existingVersionFiles = try fileManager.find(carthageBuildDir).filter { path in
			path.hasSuffix(".\(versionFileExtension)")
		}

		try existingVersionFiles.forEach { existingFilePath in
			if !dependeciesVersionFiles.contains(existingFilePath) {
				logger.important("🧹 Removing potentially malformed \(versionFileExtension) file: \(existingFilePath)")
				try fileManager.delete(existingFilePath)
			}
		}
	}
}
