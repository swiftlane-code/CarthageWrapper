//

import Foundation
import SwiftlanePaths
import SwiftlaneShell

struct Zipper {
	let shell: ShellExecuting

	func zip(files: [AbsolutePath], into zipPath: AbsolutePath) throws {
		try shell.run(
			[
				"zip -rTyq",
				zipPath.string.quoted,
			] + files.map(\.string.quoted), log: .commandAndOutput(outputLogLevel: .important)
		)
	}

	func unzip(file: AbsolutePath, to unzippedDestination: AbsolutePath) throws {
		try shell.run(
			[
				"unzip -q",
				file.string.quoted,
				"-d",
				unzippedDestination.string.quoted,
			],
			log: .silent
		)
	}
}
