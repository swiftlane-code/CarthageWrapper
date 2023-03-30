//

import class Foundation.Bundle

private class BundleAnchor {}

extension Foundation.Bundle {
	/// Returns the resource bundle associated with the current Swift module.
	static var current: Bundle = {
		let curFilePath = #file

		let pathComponents = curFilePath.split(separator: "/")
		let sourcesIndex = pathComponents.firstIndex(of: "Sources")!
		let packageName = pathComponents[sourcesIndex - 1]
		let targetName = pathComponents[sourcesIndex + 1]

		let bundleName = "\(packageName)_\(targetName)"

		let candidates = [
			Bundle.main.resourceURL,
			Bundle(for: BundleAnchor.self).resourceURL,
			Bundle.main.bundleURL,
		]

		for candidate in candidates {
			let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
			if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
				return bundle
			}
		}

		return Bundle(for: BundleAnchor.self)
	}()
}
