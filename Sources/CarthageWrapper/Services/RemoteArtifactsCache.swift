//

import Combine
import Foundation
import GitLabAPI
import Networking
import SwiftlaneLogging
import SwiftlanePaths
import SwiftlaneShell

struct RemoteArtifactsCache {
	let shell: ShellExecuting
	let logger: Logging
	let filesManager: FSManaging
	let gitlabPackages: GitLabPackagesRegistry
	let progressLogger: NetworkingProgressLogger

	let tempDir: AbsolutePath
	let timeout: TimeInterval

	func download(lib: Lib) -> AbsolutePath? {
		do {
			logger.important("🌍 Downloading \(lib.name) \(lib.version)...")
			
			let downloadedZipFile = try tempDir.appending(path: lib.name + Constants.dotZipExtension)

			if lib.url != nil {
				try downloadFromInternet(lib: lib, to: downloadedZipFile)
			} else {
				try gitlabPackages.download(lib: lib, to: downloadedZipFile)
			}
			return downloadedZipFile
		} catch {
			logger.warn("Download failed: \(error.localizedDescription)")
			return nil
		}
	}

	func isUploadNeeded(of lib: Lib) -> Bool {
		do {
			return try !gitlabPackages.packageExists(lib: lib)
		} catch {
			logger.error("Error checking existing gitlab package: \(String(reflecting: error))")
			return false
		}
	}

	/// ⚠️ Check if uploading is needed beforehand using `isUploadNeeded(of:)`!
	func upload(lib: Lib, file: AbsolutePath) throws {
		logger.important("⏫ Uploading \(lib.name) \(lib.version) as \(file.string.quoted)...")

		try gitlabPackages.upload(lib: lib, packageFile: file)
	}
}

private extension RemoteArtifactsCache {
	private func downloadFromInternet(lib: Lib, to downloadedFilePath: AbsolutePath) throws {
		let libURL = try lib.url.unwrap(errorDescription: "\(lib) has no url.")
		logger.important("Downloading from \(libURL.quoted)")
		let url = try URL(string: libURL).unwrap(errorDescription: "\(libURL.quoted) is not a valid URL.")
		let request = URLRequest(url: url, timeoutInterval: timeout)
		let publisher = URLSession.shared.dataTaskPublisherWithProgress(for: request)

		let data: Data = try progressLogger.performLoggingDoubleProgress(
			description: "Downloading \(lib.name) \(lib.version): ",
			publisher: publisher.map {
				switch $0 {
				case let .progress(task):
					return .progress(task.progress.fractionCompleted)
				case let .result(data, _):
					return .result(data)
				}
			}.eraseToAnyPublisher(),
			timeout: timeout
		)

		try filesManager.write(downloadedFilePath, data: data)
	}
}
