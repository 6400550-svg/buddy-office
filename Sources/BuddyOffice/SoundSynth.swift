import AppKit
import AVFoundation

/// 运行时合成 8-bit 提示音（方波琶音，WAV 数据），用 NSSound(data:) 播放，不需要外部文件。
enum SoundSynth {
    enum Kind { case approval, question, finished, error }

    static func wav(_ kind: Kind) -> Data {
        let rate = 22050
        let notes: [(Double, Double)]      // (频率, 秒)
        switch kind {
        case .approval: notes = [(659.25, 0.09), (880.0, 0.13)]
        case .question: notes = [(523.25, 0.09), (783.99, 0.13)]
        case .finished: notes = [(523.25, 0.08), (659.25, 0.08), (783.99, 0.14)]
        case .error: notes = [(392.0, 0.1), (293.66, 0.18)]
        }
        var samples: [UInt8] = []
        for (f, d) in notes {
            let n = Int(Double(rate) * d)
            for i in 0..<n {
                let t = Double(i) / Double(rate)
                let sq: Double = sin(2 * Double.pi * f * t) >= 0 ? 1 : -1
                // 起音 / 收音各 6 ms，避免爆音
                let env = min(1.0, min(Double(i) / (0.006 * Double(rate)), Double(n - i) / (0.012 * Double(rate))))
                let v = sq * env * 0.22
                samples.append(UInt8(max(0, min(255, Int((v * 127.0 + 128.0).rounded())))))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + samples.count)); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate)); u16(1); u16(8)
        d.append("data".data(using: .ascii)!); u32(UInt32(samples.count)); d.append(contentsOf: samples)
        return d
    }

    // 第一次 NSSound.play() 会在主线程上卡 200–270 ms（实测：初始化音频设备），之后每次也要 15–70 ms。
    // 所以放到专门的串行队列里做，用 AVAudioPlayer（创建 + prepareToPlay 都在后台），主线程一点不卡。
    private static let queue = DispatchQueue(label: "buddy.sound", qos: .utility)
    nonisolated(unsafe) private static var players: [Int: AVAudioPlayer] = [:]
    private static func index(_ kind: Kind) -> Int {
        switch kind { case .approval: return 0; case .question: return 1; case .finished: return 2; case .error: return 3 }
    }
    private static func player(_ kind: Kind) -> AVAudioPlayer? {     // 只在 queue 上调用
        let k = index(kind)
        if let p = players[k] { return p }
        guard let p = try? AVAudioPlayer(data: wav(kind), fileTypeHint: AVFileType.wav.rawValue) else { return nil }
        p.prepareToPlay()
        players[k] = p
        return p
    }
    /// 启动后空闲时把四种提示音都建好（不发声），第一次真的响的时候就不用再等。
    static func prewarm() { queue.async { for k in [Kind.approval, .question, .finished, .error] { _ = player(k) } } }
    static func play(_ kind: Kind, mode: String) {
        switch mode {
        case "none": return
        case "system": queue.async { NSSound.beep() }
        default:
            queue.async {
                guard let p = player(kind) else { return }
                p.currentTime = 0
                p.play()
            }
        }
    }
}
