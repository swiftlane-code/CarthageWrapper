//

import Foundation
import SwiftlaneShell

protocol SwiftVerionsDetectorDetecting {
	func getSystemSwiftVersion() throws -> String
}

struct SwiftVerionsDetector {
	let shell: ShellExecuting

	internal init(shell: ShellExecuting) {
		self.shell = shell
	}
}

extension SwiftVerionsDetector {
	enum Errors: Error {
		case undefined
	}
}

extension SwiftVerionsDetector: SwiftVerionsDetectorDetecting {
	func getSystemSwiftVersion() throws -> String {
		let swiftVersionOutput = try shell.run(
			"swift --version",
			log: .commandAndOutput(outputLogLevel: .important)
		).stdoutText!

		let expression = try NSRegularExpression(
			pattern: #"(\d+(\.\d)+)"#,
			options: .anchorsMatchLines
		)

		guard
			let swiftVersion = expression.firstMatchString(in: swiftVersionOutput)
		else {
			throw Errors.undefined
		}

		return swiftVersion
	}
}
