import Foundation
import CoreGraphics
import BuddyCore
import PixelKit
import BuddyArt
import BuddyStage

// buddyctl：无头工具（不需要窗口和 GPU，可以在沙箱里跑）。
//   dump      实时打印会话状态表（同 buddydump）        replay    回放合成时序验证整条链路
//   snapshot  确定性的场景快照（PNG + 总览）              flicker   闪烁扫描
//   verify    局部重绘 vs 整张重画逐像素对比             golden    金图哈希（--update 重新生成）
//   gif       导出演示动图   screens 各种屏幕内容总览   cards 提示卡 / 悬停卡总览   bench 渲染耗时
//   sheet     精灵总表   cell 工位预览   strip 朝向条   walk 走路周期   room 只画房间   icon App 图标   probe 无头渲染自检
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    FileHandle.standardError.write("用法：buddyctl <dump|replay|snapshot|flicker|verify|golden|gif|screens|cards|bench|text-audit|sheet|cell|strip|walk|room|icon|probe> …\n".data(using: .utf8)!)
    exit(2)
}
let rest = Array(args.dropFirst())

switch cmd {
case "dump": exit(runDumpCommand(arguments: rest))
case "replay": exit(runReplayCommand(arguments: rest))
case "snapshot", "flicker", "room", "bench", "verify", "cards", "golden", "gif", "screens", "text-audit": exit(StageCommands.run(args))
case "sheet": exit(ArtCommands.sheet(rest))
case "cell": exit(ArtCommands.cell(rest))
case "strip": exit(ArtCommands.strip(rest))
case "walk": exit(ArtCommands.walk(rest))
case "icon": exit(ArtCommands.icon(rest))
case "probe": exit(runProbe(rest))
default:
    FileHandle.standardError.write("未知子命令：\(cmd)\n".data(using: .utf8)!)
    exit(2)
}

func runProbe(_ a: [String]) -> Int32 {
    let out = a.first ?? "probe.png"
    var pal = MasterPalette()
    let bg = pal.add("bg", RGBA8(hex: 0x3B3F55))
    let skin = pal.add("skin", RGBA8(hex: 0xE8B48F))
    let lut = PaletteLUT.identity(pal)
    let st = Resolved(map: nil, lutA: lut)
    let c = Canvas(width: 96, height: 32)
    c.fillRect(c.bounds, value: UInt8(bg), style: st)
    PixelFont.tiny.draw("03:12 1.2M 2/10", x: 4, y: 4, value: UInt8(skin), style: st, on: c)
    let texts = [TextItem("运行 npm test · 本轮 3:12", style: TextStyle(size: 11, color: RGBA8(0xFF, 0xF3, 0xD9), weight: .medium), x: 4, y: 14)]
    guard let img = FrameRenderer.render(Frame(canvas: c, texts: texts), zoom: 4, scale: 2) else { print("render failed"); return 1 }
    do { try PNGExport.write(img, to: URL(fileURLWithPath: out)) } catch { print("\(error)"); return 1 }
    print("probe ok: wrote \(out) (\(img.width)x\(img.height))")
    return 0
}
