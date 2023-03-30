//

import ArgumentParser
import Foundation

struct RootCommand: ParsableCommand {
	// swiftformat:disable indent
	static var configuration = CommandConfiguration(
		commandName: "CarthageWrapper",
		abstract:
			"CarthageWrapper is utility that wraps Carthage. " +
			"This utility allows prebuilding and caching of binaries.",
		version: UTILL_VERSION,
		subcommands: [
			BootstrapCommand.self,
			UploadFrameworkCommand.self,
		],
		defaultSubcommand: BootstrapCommand.self
	)
	// swiftformat:enable indent
}
