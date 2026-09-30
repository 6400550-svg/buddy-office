import Foundation
import BuddyArt
import PixelKit

// 开发用：只依赖 PixelKit + BuddyArt 的美术工具，不受数据层半成品影响。
let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "sheet": exit(ArtCommands.sheet(Array(args.dropFirst())))
case "strip": exit(ArtCommands.strip(Array(args.dropFirst())))
case "walk": exit(ArtCommands.walk(Array(args.dropFirst())))
case "cell": exit(ArtCommands.cell(Array(args.dropFirst())))
default:
    print("用法：artctl sheet [--filter x] [--scale 6] [--seed N] [--out f.png]"); exit(2)
}
