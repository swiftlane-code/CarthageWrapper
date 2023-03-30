//

import SwiftlanePaths
import SwiftlaneShell

struct CarthageRunner {
	let projectDir: AbsolutePath
	let shell: ShellExecuting
	let carthageCommand: String

	func bootstrap() throws {
		try shell.run(
			"cd \(projectDir) && \(carthageCommand) bootstrap --no-build --no-use-binaries --use-ssh",
			log: .commandAndOutput(outputLogLevel: .important)
		)
	}

	func build(xcconfigPath: AbsolutePath, libName: String) throws {
		try shell.run(
			"cd \(projectDir) && XCODE_XCCONFIG_FILE=\(xcconfigPath) \(carthageCommand) build \(libName) --use-xcframeworks --no-use-binaries --platform iOS",
			log: .commandAndOutput(outputLogLevel: .important)
		)
	}
}
