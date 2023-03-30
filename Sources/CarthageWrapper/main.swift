//

import ArgumentParser
import Foundation
import PerfectRainbow

// Make stdout unbuffered.
setbuf(__stdoutp, nil)

RootCommand.main()
