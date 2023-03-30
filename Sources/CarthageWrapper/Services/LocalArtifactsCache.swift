//

import Foundation
import SwiftlanePaths

struct LocalArtifactsCache {
	let filesManager: FSManaging
	let localCacheDir: AbsolutePath

	private func cacheFilePath(for lib: Lib) throws -> AbsolutePath {
		try localCacheDir.appending(path: lib.name + "@" + lib.version + Constants.dotZipExtension)
	}

	func moveToCache(file: AbsolutePath, lib: Lib) throws {
		let cachedFilePath = try cacheFilePath(for: lib)
		if file == cachedFilePath {
			return
		}
		if filesManager.fileExists(cachedFilePath) {
			try filesManager.delete(cachedFilePath)
		}
		if !filesManager.directoryExists(cachedFilePath.deletingLastComponent) {
			try filesManager.mkdir(cachedFilePath.deletingLastComponent)
		}
		try filesManager.move(file, newPath: cachedFilePath)
	}

	func cachedFile(for lib: Lib) throws -> AbsolutePath? {
		let path = try cacheFilePath(for: lib)
		guard filesManager.fileExists(path) else {
			return nil
		}
		return path
	}
}
