//

import Foundation
import SwiftlaneLogging
import SwiftlanePaths
import Yams

struct UploadFrameworkCommandRunner {
	enum Errors: Error {
		case isNotADirectory(path: AbsolutePath)
		case infoPlistNotFound(frameworkPath: AbsolutePath)
		case infoPlistVersionNotSet(plistPath: AbsolutePath)
		case packageAlreadyExists(lib: Lib, frameworkPath: AbsolutePath)
	}

	let filesManager: FSManaging
	let logger: Logging
	let gitlabPackages: GitLabPackagesRegistry
	let zipper: Zipper
	let frameworksToUpload: [AbsolutePath]

	func run() throws {
		try frameworksToUpload.forEach(uploadFramework(_:))
	}

	func uploadFramework(_ frameworkPath: AbsolutePath) throws {
		logger.important("Processing \(frameworkPath.string.quoted)...")

		guard filesManager.directoryExists(frameworkPath) else {
			logger.error("\(frameworkPath.string.quoted) is not a directory.")
			throw Errors.isNotADirectory(path: frameworkPath)
		}

		let lib = Lib(
			name: frameworkPath.lastComponent.string,
			version: try parseFrameworkVersion(frameworkPath),
			url: nil
		)

		if try gitlabPackages.packageExists(lib: lib) {
			logger.error("Package \(lib.name) \(lib.version) already exists in GitLab packages registry.")
			throw Errors.packageAlreadyExists(lib: lib, frameworkPath: frameworkPath)
		}

		let zipFile = frameworkPath.appending(suffix: Constants.dotZipExtension)
		defer {
			try? filesManager.delete(zipFile)
		}
		try zipper.zip(files: [frameworkPath], into: zipFile)
		try gitlabPackages.upload(lib: lib, packageFile: zipFile)
	}

	// swiftformat:disable indent
	func parseFrameworkVersion(_ frameworkPath: AbsolutePath) throws -> String {
		/// xcframework contains a plist file in its root (e.g. `Lib.xcframework/Info.plist`)
		/// but this plist doesn't have version info.
		/// So we look for `Info.plist` file inside a `"*.framework"` folder.
		let plistPath = try filesManager.find(frameworkPath)
			.filter {
				$0.lastComponent.string == "Info.plist" &&
				$0.deletingLastComponent.pathExtension == Constants.framework
			}
			.first
		guard let plistPath = plistPath else {
			logger.error("Info.plist not found in \(frameworkPath.string.quoted).")
			throw Errors.infoPlistNotFound(frameworkPath: frameworkPath)
		}

		let plistData = try filesManager.readData(plistPath, log: false)
		let plistModel = try PropertyListDecoder().decode(InfoPlistModel.self, from: plistData)
		guard let version = plistModel.CFBundleShortVersionString else {
			logger.error("Info.plist doesn't have CFBundleShortVersionString value at \(plistPath.string.quoted).")
			throw Errors.infoPlistVersionNotSet(plistPath: plistPath)
		}

		return version
	}
	// swiftformat:enable indent
}

private struct InfoPlistModel: Decodable {
	let CFBundleShortVersionString: String?
}
