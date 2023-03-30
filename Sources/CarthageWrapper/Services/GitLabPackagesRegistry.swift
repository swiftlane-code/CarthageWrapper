//

import Combine
import Foundation
import GitLabAPI
import Networking
import SwiftlaneLogging
import SwiftlanePaths

struct GitLabPackagesRegistry {
	enum Errors: Error {
		case unexpectedPackageUploadResult(message: String, expectedMessage: String)
	}

	let logger: Logging
	let gitlabAPI: GitLabAPIClientProtocol
	let filesManager: FSManaging
	let progressLogger: NetworkingProgressLogger

	let gitlabProjectID: Int
	let timeout: TimeInterval

	func packageExists(lib: Lib) throws -> Bool {
		let packages = try gitlabAPI.listPackages(
			space: .project(id: gitlabProjectID),
			request: PackagesListRequest.make {
				$0.package_name = lib.name
			}
		).await()

		return packages.contains { $0.version == lib.version }
	}

	func upload(lib: Lib, packageFile: AbsolutePath) throws {
		let data = try filesManager.readData(packageFile, log: false)

		let publisher = gitlabAPI.uploadPackage(
			space: .project(id: gitlabProjectID),
			name: lib.name,
			version: lib.version,
			fileName: lib.name + Constants.dotZipExtension,
			data: data,
			timeout: timeout
		)

		let response = try progressLogger.performLoggingProgress(
			description: "Uploading \(lib.name) \(lib.version) (\(data.humanSize())): ",
			publisher: publisher,
			timeout: timeout
		)

		let expectedMessage = PackageUploadResult.successMessage
		if response.message != expectedMessage {
			throw Errors.unexpectedPackageUploadResult(
				message: response.message,
				expectedMessage: expectedMessage
			)
		}

		logger.success("\(lib.name) \(lib.version) has been uploaded successfully.")
	}

	func download(lib: Lib, to downloadedFilePath: AbsolutePath) throws {
		let publisher = gitlabAPI.downloadPackage(
			space: .project(id: gitlabProjectID),
			name: lib.name,
			version: lib.version,
			fileName: lib.name + Constants.dotZipExtension,
			timeout: timeout
		)

		let data = try progressLogger.performLoggingProgress(
			description: "Downloading \(lib.name) \(lib.version): ",
			publisher: publisher,
			timeout: timeout
		)

		try filesManager.write(downloadedFilePath, data: data)

		logger.success("\(lib.name) \(lib.version) has been downloaded successfully.")
	}
}
