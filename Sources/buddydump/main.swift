import BuddyCore
import Foundation

// buddydump [--watch|--once] [--poll] [--data-root DIR]   实时打印会话表（对照真实数据）
// buddydump replay --root <空目录> [--fsevents]            回放整条合成时序（buddyctl replay 转发到同一个函数）
var args = Array(CommandLine.arguments.dropFirst())
if args.first == "replay" {
    args.removeFirst()
    exit(runReplayCommand(arguments: args))
}
exit(runDumpCommand(arguments: args))
