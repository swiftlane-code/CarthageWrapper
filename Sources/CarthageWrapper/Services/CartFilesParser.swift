//

import Combine
import Foundation
import SwiftlaneCoreServices
import SwiftlaneLogging
import SwiftlanePaths
import Yams

struct CartFilesParser {
	enum Errors: Error {
		case wrongDependencyFormat(String)
		case urlNotSpecified(lib: PublicBinaryLib)
	}

	let logger: Logging
	let filesManager: FSManaging
	let makeURLRequest: (URL) -> AnyPublisher<Data, Error>

	func parseCartfileResolved(
		filePath: AbsolutePath
	) throws -> [Lib] {
		let rawContent = try filesManager.readText(filePath, log: false)

		let lines = rawContent.split(whereSeparator: \.isNewline).map { line in
			line.trimmingCharacters(in: .whitespaces)
		}

		let dependenciesLines = lines.filter { line in
			line.hasPrefix("git")
		}

		let libs = try dependenciesLines.map { line -> Lib in
			let dependenciesMeta = line.components(separatedBy: .whitespaces).map { component in
				component.trimmingCharacters(in: .init(charactersIn: #"'""#))
			}

			let version = dependenciesMeta[2]
			let url = dependenciesMeta[1]

			guard
				let name = url.split(separator: "/").last?.map(String.init).joined().deletingSuffix(".git")
			else {
				throw Errors.wrongDependencyFormat(url)
			}

			return Lib(name: name, version: version, url: nil)
		}

		return libs
	}

	func parseBinaryCartfile(
		filePath: AbsolutePath
	) throws -> [Lib] {
		let ymlData = try filesManager.readData(filePath, log: false)

		let dependencies = try YAMLDecoder().decode(BinaryDependencies.self, from: ymlData)

		let publicLibs: [Lib] = try dependencies.public.map { dependency in
			let url = try resolvePublicBinaryURL(dependency: dependency)
			return Lib(name: dependency.name, version: dependency.version, url: url)
		}

		let privateLibs: [Lib] = dependencies.private.map { dependency in
			Lib(name: dependency.name, version: dependency.version, url: nil)
		}

		return publicLibs + privateLibs
	}

	private func resolvePublicBinaryURL(dependency: PublicBinaryLib) throws -> String {
		if let url = dependency.url {
			return url
		}
		if let jsonURLString = dependency.jsonURL {
			let jsonURL = try URL(string: jsonURLString).unwrap(
				errorDescription: "\(jsonURLString.quoted) is not a valid URL."
			)
			return try getBinaryURL(from: jsonURL, dependency: dependency)
		}
		logger.error("Either \"\(\PublicBinaryLib.url)\" or \"\(\PublicBinaryLib.jsonURL)\" should be specified.")
		throw Errors.urlNotSpecified(lib: dependency)
	}

	private func getBinaryURL(from jsonURL: URL, dependency: PublicBinaryLib) throws -> String {
		let jsonData = try makeURLRequest(jsonURL).await(timeout: 10)
		// swiftformat:disable:next spaceAroundOperators
		let versionsAndURLs = try JSONDecoder().decode([String:String].self, from: jsonData)
		let binaryURL = try versionsAndURLs[dependency.version].unwrap(
			errorDescription: "Version \(dependency.version.quoted) is not listed in json at \(jsonURL)"
		)
		logLatestAvailableVersion(
			dependency: dependency,
			allVersions: versionsAndURLs
		)
		return binaryURL
	}

	// swiftformat:disable:next spaceAroundOperators
	private func logLatestAvailableVersion(dependency: PublicBinaryLib, allVersions: [String:String]) {
		let latestVersion = allVersions.keys
			.compactMap { try? SemVer(parseFrom: $0) }
			.sorted(by: <)
			.last

		if let latestVersion = latestVersion,
		   let selectedVersion = try? SemVer(parseFrom: dependency.version),
		   latestVersion > selectedVersion {
			// swiftformat:disable indent
			logger.warn(
				"Latest available version of \(dependency.name) is \(latestVersion.string(format: .full))" +
				" (you are using \(dependency.version))."
			)
			// swiftformat:enable indent
		}
	}
}
