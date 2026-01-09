import SwiftUI
import AVFoundation

class VocalMasterEngine: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private let historyKey = "VocalTrainingHistory"
    
    @Published var audioLevel: CGFloat = 0.2
    @Published var currentBreathSeconds: Double = 0
    @Published var bestBreath: Double = 0
    @Published var remainingTime: Int = 60
    @Published var currentPitch: String = "---"
    
    // ✨ 核心修复点：必须包含这行 history 变量
    @Published var history: [Double] = []
    
    init() {
        if let saved = UserDefaults.standard.array(forKey: historyKey) as? [Double] {
            self.history = saved
        }
    }
    
    func startBreath() {
        stopAll()
        remainingTime = 60; currentBreathSeconds = 0
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatAppleLossless), AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1]
        audioRecorder = try? AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"), settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.audioRecorder?.updateMeters()
            let level = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
            DispatchQueue.main.async {
                self.audioLevel = CGFloat(max(0.2, (level + 60) / 40))
                if level > -45 && level < -2 {
                    self.currentBreathSeconds += 0.1
                    if self.currentBreathSeconds > self.bestBreath { self.bestBreath = self.currentBreathSeconds }
                } else { self.currentBreathSeconds = 0 }
            }
        }
    }
    
    func startPitch() {
        stopAll()
        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            let freq = self.getFreq(buffer: buffer)
            DispatchQueue.main.async {
                self.currentPitch = self.noteName(f: freq)
                self.audioLevel = CGFloat(abs(buffer.floatChannelData![0][0]) * 10)
            }
        }
        try? audioEngine.start()
    }
    
    func stopAll() {
        timer?.invalidate(); audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0); audioRecorder?.stop()
        if bestBreath > 0 {
            history.insert(bestBreath, at: 0)
            UserDefaults.standard.set(history, forKey: historyKey)
        }
    }
    
    private func getFreq(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        var cross = 0
        for i in 1..<Int(buffer.frameLength) { if data[i-1] * data[i] < 0 { cross += 1 } }
        return Float(cross) * 44100 / (Float(buffer.frameLength) * 2)
    }
    
    private func noteName(f: Float) -> String {
        if f < 80 || f > 1200 { return "---" }
        let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let j = Int(round(12 * log2(f / 440) + 69))
        return "\(notes[max(0, j % 12)])\(j / 12 - 1)"
    }
}
