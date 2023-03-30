//

import Foundation
import SwiftlaneCoreServices
import SwiftlaneLogging
import SwiftlanePaths
import SwiftlaneShell
import Yams

/// Main App code.
struct BootstrapCommandRunner {
	let wrapperVersion: String = "2"

	let exitor: Exiting
	let filesManager: FSManaging
	let logger: Logging
	let shell: ShellExecuting
	let versionFilesManager: VersionFilesManager
	let cartFilesParser: CartFilesParser
	let cartXCConfigGenerator: CartXCConfigGenerator
	let carthageRunner: CarthageRunner
	let localCache: LocalArtifactsCache
	let remoteArtifactsCache: RemoteArtifactsCache
	let carthageFrameworksInstaller: CarthageFrameworksInstaller
	let fatBinariesConverter: CarthageFatBinariesConverter
	let zipper: Zipper

	let projectDir: AbsolutePath
	let tempDir: AbsolutePath
	let carthageBuildDir: AbsolutePath
	let cartfileResolvedPath: AbsolutePath
	let cartfileBinaryPath: AbsolutePath
	let downloadingAllowed: Bool
	let uploadingAllowed: Bool

	/// Called when app is being runned.
	func run() throws {
		try carthageRunner.bootstrap()

		let swiftVersionDetector = SwiftVerionsDetector(shell: shell)
		let swiftVersion = try swiftVersionDetector.getSystemSwiftVersion()
		logger.important("ℹ️  Current Swift version: \(swiftVersion)\n\n")

		let buildableLibs = try cartFilesParser.parseCartfileResolved(filePath: cartfileResolvedPath)
		let binaryLibs = try cartFilesParser.parseBinaryCartfile(filePath: cartfileBinaryPath)

		let allLibs = buildableLibs + binaryLibs

		try versionFilesManager.cleanUnusedSmversionFiles(libs: allLibs)

		let enrichedBuildableLibs = enrichVersionsOfLibs(
			buildableLibs,
			swiftVersion: swiftVersion,
			wrapperVersion: wrapperVersion
		)

		logger.important("🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻 Preparing carthage frameworks... 🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻 ")
		logger.important("")

		try prepareBuildableLibs(enrichedBuildableLibs, logger: logger)

		logger.important("🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻 Downloading binary only frameworks... 🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻🧑🏻‍💻 ")
		logger.important("")

		try downloadBinaryOnlyFrameworks(binaryLibs)

		try fatBinariesConverter.convert()
	}

	func downloadBinaryOnlyFrameworks(_ libs: [Lib]) throws {
		let libsAmount = libs.count
		try libs.enumerated().forEach { item in
			let position = item.offset + 1
			let lib = item.element
			logger.important("🔍 [Binary only frameworks] Processing \(lib.name) (\(position)/\(libsAmount))")

			if try !downloadAndInstallLibIfNeeded(lib) {
				logger.error("Unable to download binary only lib \(lib.name) \(lib.version) from \(lib.url?.quoted ?? "<nil>")")
				exitor.exit(with: 1)
			}
		}
	}

	func prepareBuildableLibs(_ libs: [Lib], logger: Logging) throws {
		let libsAmount = libs.count
		try libs.enumerated().forEach { item in
			let position = item.offset + 1
			let lib = item.element
			logger.important("🔍 [Buildable frameworks] Processing \(lib.name) (\(position)/\(libsAmount))")

			try downloadOrBuildLib(lib)
		}
	}

	func downloadOrBuildLib(_ lib: Lib) throws {
		if try !downloadAndInstallLibIfNeeded(lib) {
			try buildAndUploadLib(lib)
		}
	}

	/// Returns `true` if lib was downloaded and installed.
	func downloadAndInstallLibIfNeeded(_ lib: Lib) throws -> Bool {
		if try versionFilesManager.isLocalLibVersionEquals(for: lib) {
			return true
		}

		try versionFilesManager.deleteVersionFileFor(libName: lib.name)

		func getCachedOrDownload() -> AbsolutePath? {
			if let cachedZipPath = try? localCache.cachedFile(for: lib) {
				logger.important("Using cached file \(cachedZipPath.string.quoted)")
				return cachedZipPath
			}
			guard downloadingAllowed else {
				logger.warn("Downloading is disabled.")
				return nil
			}
			return remoteArtifactsCache.download(lib: lib)
		}

		guard let zipPath = getCachedOrDownload() else {
			return false
		}

		try install(lib: lib, from: zipPath)
		try versionFilesManager.saveLibVersionFor(lib)
		try localCache.moveToCache(file: zipPath, lib: lib)
		return true
	}

	private func install(lib: Lib, from zipFile: AbsolutePath) throws {
		logger.important("Installing \(lib.name) \(lib.version) from \(zipFile.string.quoted)...")

		let unzippedDir = try zipFile.deletingLastComponent
			.appending(path: "unzipped_" + zipFile.lastComponent.deletingExtension.string)

		try unzip(file: zipFile, to: unzippedDir)
		try carthageFrameworksInstaller.installFrameworks(from: unzippedDir)
		try filesManager.delete(unzippedDir)
	}

	private func unzip(file: AbsolutePath, to unzippedDestination: AbsolutePath) throws {
		try filesManager.delete(unzippedDestination)
		try filesManager.mkdir(unzippedDestination)

		logger.debug("Unzipping \(file) to \(unzippedDestination)...")
		try zipper.unzip(file: file, to: unzippedDestination)
		try filesManager.delete(unzippedDestination.appending(path: "__MACOSX"))
	}

	private func buildAndUploadLib(_ lib: Lib) throws {
		try versionFilesManager.deleteVersionFileFor(libName: lib.name)

		var frameworksModificationTimes = [AbsolutePath: Date]()

		if filesManager.directoryExists(carthageBuildDir) {
			try filesManager.ls(carthageBuildDir).forEach { path in
				let attributes = try filesManager.stat(
					path,
					keys: Set([.contentModificationDateKey, .isDirectoryKey])
				)

				guard attributes.isDirectory == true else {
					return
				}

				guard path.hasSuffix(".xcframework") else {
					return
				}

				return frameworksModificationTimes[path] = attributes.contentModificationDate!
			}
		}
		logger.important("🛠  Building \(lib.name)...")

		let xcconfigPath = try cartXCConfigGenerator.generate(directory: carthageBuildDir)
		try carthageRunner.build(xcconfigPath: xcconfigPath, libName: lib.name)

		logger.important("Build succeeded.")

		try versionFilesManager.saveLibVersionFor(lib)

		let modifiedFrameworks = try filesManager.ls(carthageBuildDir).filter { item in
			let attributes = try filesManager.stat(item, keys: Set([.contentModificationDateKey, .isDirectoryKey]))

			guard attributes.isDirectory == true else {
				return false
			}

			guard item.hasSuffix(".xcframework") else {
				return false
			}

			let previousModificationTime = frameworksModificationTimes[item]
			let currentModificationTime = attributes.contentModificationDate

			if currentModificationTime != previousModificationTime {
				logger.debug("🧑🏻‍💻 changed \(item):")
				logger.debug("\told modified date: \(String(describing: previousModificationTime))")
				logger.debug("\tnew modified date: \(String(describing: currentModificationTime))")
				return true
			}

			return false
		}

		try uploadLibIfNeeded(lib: lib, frameworks: modifiedFrameworks)
	}

	private func uploadLibIfNeeded(lib: Lib, frameworks: [AbsolutePath]) throws {
		let zipPath = try tempDir.appending(path: lib.name + Constants.dotZipExtension)
		defer {
			try? localCache.moveToCache(file: zipPath, lib: lib)
			// nothing to delete if it was eventually moved to cache.
			try? filesManager.delete(zipPath)
		}
		try zipper.zip(files: frameworks, into: zipPath)
		
		guard uploadingAllowed else {
			logger.warn("Uploading is disabled.")
			return
		}
		
		guard remoteArtifactsCache.isUploadNeeded(of: lib) else {
			logger.important("Uploading to GitLab packages skipped because this package already exists.")
			return
		}

		try remoteArtifactsCache.upload(lib: lib, file: zipPath)
	}

	func enrichVersionsOfLibs(_ libs: [Lib], swiftVersion: String, wrapperVersion: String) -> [Lib] {
		return libs.map { lib in
			Lib(
				name: lib.name,
				version: "\(lib.version)_swift-\(swiftVersion)_builder-\(wrapperVersion)",
				url: lib.url
			)
		}
	}
}
