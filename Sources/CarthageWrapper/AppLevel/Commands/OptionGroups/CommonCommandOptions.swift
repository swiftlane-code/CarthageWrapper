//

import ArgumentParser
import Foundation

struct CommonCommandOptions: ParsableArguments {
	@Flag(help: "Enables verbose mode")
	var verbose = false
}
