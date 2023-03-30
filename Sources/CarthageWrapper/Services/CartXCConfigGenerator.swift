//

import SwiftlanePaths

struct CartXCConfigGenerator {
	let fileManager: FSManaging

	func generate(
		directory: AbsolutePath,
		fileName: String = "carthage.xcconfig"
	) throws -> AbsolutePath {
		let absFilePath = try directory.appending(path: fileName)

		// swiftformat:disable indent
		let buildOptions = """
			SWIFT_SERIALIZE_DEBUGGING_OPTIONS = NO
			OTHER_SWIFT_FLAGS = $(inherited) -Xfrontend -no-serialize-debugging-options
		"""
		// swiftformat:enable indent
		try fileManager.write(absFilePath, text: buildOptions)

		return absFilePath
	}
}
