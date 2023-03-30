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

struct BootstrapCommand: ParsableCommand {
	// swiftformat:disable indent
	static var configuration = CommandConfiguration(
		commandName: "bootstrap",
		abstract: "Bootstrap dependencies. For now this tool supports only iOS frameworks.",
		discussion: """
			How it works:
			1) Execute "$ carthage bootstrap --no-build".
			2) Parse "Cartfile.resolved" and "CartfileBinary.yml"
			3) Try to download prebuilt binaries of required libraries from (2):
			   * prebuilt binaries are either downloaded from url
				 specified in "CartfileBinary.yml" or from GitLab Packages Registry.
			4) If downloading of a prebuilt binary failed
			   execute "$ carthage build ... --use-xcframeworks" to build it
			   and upload built binaries to GitLab Packages Registry.
			5) Slice fat binaries in "Carthage/Build/iOS" and create respective
			   xcframeworks in "Carthage/Build".

			Notes:
			   * "*.smversion" files stored in "Carthage/Build" folder
				 are used to track versions of binaries which are ready
				 to be used in "Carthage/Build" folder.
			   * local swift version is taken into account when building
				 or downloading prebuilt binaries.
		"""
	)
	// swiftformat:enable indent

	@Option(help: "Project dir path. Absolute and relative paths are supported.")
	var projectDir: Path

	@Option(help: "Absolute or project dir related Cartfile.resolved file path")
	var cartfileResolvedPath: Path = try! Path("Cartfile.resolved")

	@Option(help: "Absolute or project dir related CartfileBinary.yml file path")
	var cartfileBinaryPath: Path = try! Path("CartfileBinary.yml")

	@Option(
		help: """
			Custom carthage command. Helpful in case using non standart Carthage install path.
			This options support project relative paths.
		"""
	)
	var carthageCommand: String = "carthage"

	@Option(help: "GitLab API URL for caching prebuilt dependencies")
	var gitlabApiUrl: URL

	@Option(help: "GitLab Project ID with enabled packages feature for caching prebuilt dependencies")
	var gitlabProjectID: Int

	@Option(help: "GitLab API Token for caching prebuilt dependencies")
	var gitlabApiToken: String

	@Option(help: "Path to \"Carthage/Build\" folder. Paths relative to --project-dir are supported.")
	var carthageBuildPath: Path = try! Path("Carthage/Build")

	@Option(help: "Path to folder where cached .zip packages are stored. Paths relative to --project-dir are supported.")
	var packagesCachePath: Path = try! Path("etc/cached-binaries")

	@Option(help: "Path to folder where temporary stuff is stored. Paths relative to --project-dir are supported.")
	var tempPath: Path = try! Path("Carthage/temp")

	@Option(help: "Upload and download requests' timeout in seconds.")
	var timeout: TimeInterval = 1200
	
	@Flag(help: "Control how network connection is used.")
	var networkingMode: NetworkingMode = .online
	
	enum NetworkingMode: String, EnumerableFlag {
		case online
		case noUpload
		case offline
		
		var uploadEnabled: Bool {
			return self == .online
		}
		
		var downloadEnabled: Bool {
			return self == .online || self == .noUpload
		}
		
		static func help(for value: BootstrapCommand.NetworkingMode) -> ArgumentHelp? {
			switch value {
			case .online:
				return "Default mode. Try to download prebuilt binaries and upload ones built locally if needed."
			case .noUpload:
				return "Download prebuilt binaries. Do not upload the ones built locally."
			case .offline:
				return "Completely offline. This will only succeed if you have all required binaries in the cache directory."
			}
		}
	}

	@OptionGroup var commonOptions: CommonCommandOptions

	mutating func run() throws {
		let logger: Logging = commonOptions.verbose ? DetailedLogger(logLevel: .verbose) : SimpleLogger(logLevel: .info)

		let filesManager = FSManager(
			logger: logger,
			fileManager: FileManager.default
		)

		let curWorkDir = try filesManager.pwd()

		let absProjectDir = projectDir.makeAbsoluteIfIsnt(relativeTo: curWorkDir)

		let absCartfileResolvedPath = cartfileResolvedPath.makeAbsoluteIfIsnt(relativeTo: absProjectDir)
		let absCartfileBinaryPath = cartfileBinaryPath.makeAbsoluteIfIsnt(relativeTo: absProjectDir)

		let sigIntHandler = SigIntHandler(logger: logger)
		let xcodeChecker = XcodeChecker()
		let shell: ShellExecuting = ShellExecutor(
			sigIntHandler: sigIntHandler,
			logger: logger,
			xcodeChecker: xcodeChecker,
			filesManager: filesManager
		)

		let catrFilesParser = CartFilesParser(
			logger: logger,
			filesManager: filesManager,
			makeURLRequest: {
				URLSession.shared.dataTaskPublisher(for: $0)
					.map { $0.data }
					.mapError { $0 as Error }
					.eraseToAnyPublisher()
			}
		)

		let carthageBuildDir = carthageBuildPath.makeAbsoluteIfIsnt(relativeTo: absProjectDir)
		let versionFilesManager = VersionFilesManager(
			fileManager: filesManager,
			logger: logger,
			carthageBuildDir: carthageBuildDir
		)

		let cartXCConfigGenerator = CartXCConfigGenerator(
			fileManager: filesManager
		)

		let carthageRunner = CarthageRunner(
			projectDir: absProjectDir,
			shell: shell,
			carthageCommand: carthageCommand
		)

		let localArtifactsCache = LocalArtifactsCache(
			filesManager: filesManager,
			localCacheDir: packagesCachePath.makeAbsoluteIfIsnt(relativeTo: absProjectDir)
		)

		let tempDir = tempPath.makeAbsoluteIfIsnt(relativeTo: absProjectDir)

		if !filesManager.directoryExists(tempDir) {
			try filesManager.mkdir(tempDir)
		}

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

		let remoteArtifactsCache = RemoteArtifactsCache(
			shell: shell,
			logger: logger,
			filesManager: filesManager,
			gitlabPackages: gitlabPackages,
			progressLogger: networkingProgressLogger,
			tempDir: tempDir,
			timeout: timeout
		)

		let fatBinariesConvertor = CarthageFatBinariesConverter(
			logger: logger,
			shell: shell,
			filesManager: filesManager,
			converter: FatBinaryConverter(
				logger: logger,
				shell: shell,
				filesManager: filesManager
			),
			carthageBuildDir: carthageBuildDir
		)

		let app = BootstrapCommandRunner(
			exitor: Exitor(),
			filesManager: filesManager,
			logger: logger,
			shell: shell,
			versionFilesManager: versionFilesManager,
			cartFilesParser: catrFilesParser,
			cartXCConfigGenerator: cartXCConfigGenerator,
			carthageRunner: carthageRunner,
			localCache: localArtifactsCache,
			remoteArtifactsCache: remoteArtifactsCache,
			carthageFrameworksInstaller: CarthageFrameworksInstaller(
				logger: logger,
				filesManager: filesManager,
				carthageBuildDir: carthageBuildDir
			),
			fatBinariesConverter: fatBinariesConvertor,
			zipper: Zipper(shell: shell),
			projectDir: absProjectDir,
			tempDir: tempDir,
			carthageBuildDir: carthageBuildDir,
			cartfileResolvedPath: absCartfileResolvedPath,
			cartfileBinaryPath: absCartfileBinaryPath,
			downloadingAllowed: networkingMode.downloadEnabled,
			uploadingAllowed: networkingMode.uploadEnabled
		)

		try app.run()
	}
}
