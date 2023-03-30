//

import ArgumentParser
import Foundation
import GitLabAPI
import Networking
import PerfectRainbow
import SwiftlaneCoreServices
import SwiftlaneLogging
import SwiftlanePaths
import SwiftlaneShell

struct UploadFrameworkCommand: ParsableCommand {
	// swiftformat:disable indent
	static var configuration = CommandConfiguration(
		commandName: "upload",
		abstract: "Zip and upload a framework to GitLab Package Registry.",
		discussion: """
			* All specified frameworks are uploaded as separate GitLab Packages.
			* Version of each framework is parsed from the Info.plist inside it
			  under CFBundleShortVersionString key.
			* Presence of a package with the same name and version
			  is checked in GitLab Package Registry before uploading it.
		"""
	)
	// swiftformat:enable indent

	@Option(help: "GitLab API URL for caching prebuilt dependencies")
	var gitlabApiUrl: URL

	@Option(help: "GitLab Project ID with enabled packages feature for caching prebuilt dependencies")
	var gitlabProjectID: Int

	@Option(help: "GitLab API Token for caching prebuilt dependencies")
	var gitlabApiToken: String

	@Option(help: "GitLab API request timeout.")
	var timeout: TimeInterval = 1200

	@Argument(help: "Path to a framework or xcframework (directory itself, not a .zip archive) to upload.")
	var frameworks: [Path]

	@OptionGroup var commonOptions: CommonCommandOptions

	mutating func run() throws {
		let logger: Logging = commonOptions.verbose ? DetailedLogger(logLevel: .verbose) : SimpleLogger(logLevel: .info)

		let filesManager = FSManager(
			logger: logger,
			fileManager: FileManager.default
		)

		let curWorkDir = try filesManager.pwd()

		let sigIntHandler = SigIntHandler(logger: logger)
		let xcodeChecker = XcodeChecker()
		let shell: ShellExecuting = ShellExecutor(
			sigIntHandler: sigIntHandler,
			logger: logger,
			xcodeChecker: xcodeChecker,
			filesManager: filesManager
		)

		let gitlabAPI = GitLabAPIClient(
			baseURL: gitlabApiUrl,
			accessToken: gitlabApiToken,
			logger: logger
		)

		let networkingProgressLogger = NetworkingProgressLogger(
			progressLogger: ProgressLogger(
				winsizeReader: WinSizeReader()
			)
		)

		let gitlabPackages = GitLabPackagesRegistry(
			logger: logger,
			gitlabAPI: gitlabAPI,
			filesManager: filesManager,
			progressLogger: networkingProgressLogger,
			gitlabProjectID: gitlabProjectID,
			timeout: timeout
		)

		let app = UploadFrameworkCommandRunner(
			filesManager: filesManager,
			logger: logger,
			gitlabPackages: gitlabPackages,
			zipper: Zipper(shell: shell),
			frameworksToUpload: frameworks.map {
				$0.makeAbsoluteIfIsnt(relativeTo: curWorkDir)
			}
		)

		try app.run()
	}
}
