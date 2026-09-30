import Foundation
import BuddyCore
import PixelKit
import BuddyArt
import BuddyStage

// 开发用：表现层无头工具（和 buddyctl 里对应的子命令共用同一份实现）。
let args = Array(CommandLine.arguments.dropFirst())
exit(StageCommands.run(args))
