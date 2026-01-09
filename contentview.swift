import SwiftUI
import AVFoundation

class VocalMasterEngine: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    
    // --- 数据库 Key ---
    private let historyKey = "VocalTrainingHistory"
    
    @Published var audioLevel: CGFloat = 0.0
    @Published var currentBreathSeconds: Double = 0
    @Published var bestBreath: Double = 0
    @Published var history: [Double] = [] {
        didSet {
            // 每当 history 改变时，自动存入“数据库”
            saveToDatabase()
        }
    }
    
    @Published var remainingTime: Int = 60
    @Published var currentPitch: String = "---"
    @Published var frequency: Float = 0.0
    
    init() {
        // App 启动时，先从“数据库”加载之前的记录
        loadFromDatabase()
    }
    
    // --- 数据库操作 ---
    private func saveToDatabase() {
        UserDefaults.standard.set(history, forKey: historyKey)
    }
    
    private func loadFromDatabase() {
        if let savedHistory = UserDefaults.standard.array(forKey: historyKey) as? [Double] {
            self.history = savedHistory
        }
    }

    // (以下 startBreathTest, analyzePitch 等核心逻辑均完整保留且未做删减)
    func startBreathTest() {
        stopAll()
        remainingTime = 60
        currentBreathSeconds = 0
        bestBreath = 0
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
        let url = URL(fileURLWithPath: "/dev/null")
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatAppleLossless), AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue]
        audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.audioRecorder?.updateMeters()
            let level = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
            DispatchQueue.main.async {
                self.audioLevel = CGFloat(max(0.2, (level + 60) / 40))
                if self.remainingTime > 0 {
                    if level > -45 && level < -2 {
                        self.currentBreathSeconds += 0.1
                        if self.currentBreathSeconds > self.bestBreath { self.bestBreath = self.currentBreathSeconds }
                    } else { self.currentBreathSeconds = 0 }
                }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            DispatchQueue.main.async {
                if self.remainingTime > 0 { self.remainingTime -= 1 }
                else { t.invalidate(); self.stopAll() }
            }
        }
    }
    
    func startPitchDetection() {
        stopAll()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let data = self.analyzePitch(buffer: buffer)
            DispatchQueue.main.async {
                self.frequency = data.0
                self.currentPitch = data.1
                self.audioLevel = CGFloat(abs(buffer.floatChannelData![0][0])) * 5
            }
        }
        try? audioEngine.start()
    }
    
    func stopAll() {
        timer?.invalidate()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioRecorder?.stop()
        if bestBreath > 0 { 
            // 存入历史，会自动触发 saveToDatabase()
            history.insert(bestBreath, at: 0) 
        }
    }
    
    private func analyzePitch(buffer: AVAudioPCMBuffer) -> (Float, String) {
        guard let floatData = buffer.floatChannelData?[0] else { return (0, "---") }
        let frameCount = Int(buffer.frameLength)
        var crossings = 0
        for i in 1..<frameCount {
            if (floatData[i-1] < 0 && floatData[i] >= 0) || (floatData[i-1] > 0 && floatData[i] <= 0) { crossings += 1 }
        }
        let freq = Float(crossings) * 44100 / (Float(frameCount) * 2)
        if freq < 80 || freq > 1200 { return (0, "---") }
        let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let j = Int(round(12 * log2(freq / 440) + 69))
        return (freq, "\(notes[max(0, j % 12)])\(j / 12 - 1)")
    }
}

// (ContentView, BreathChallengeView, PitchLabView 保持 7.0 的结构不变)
struct ContentView: View {
    @StateObject private var engine = VocalMasterEngine()
    var body: some View {
        TabView {
            BreathChallengeView(engine: engine)
                .tabItem { Label("气息挑战", systemImage: "wind") }
            PitchLabView(engine: engine)
                .tabItem { Label("音准实验", systemImage: "waveform") }
        }.accentColor(.blue)
    }
}

struct BreathChallengeView: View {
    @ObservedObject var engine: VocalMasterEngine
    @State private var isTesting = false
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                Text("1分钟气息挑战").font(.title.bold()).padding(.top)
                HStack(spacing: 40) {
                    VStack { Text("倒计时"); Text("\(engine.remainingTime)s").font(.title2.monospaced()).bold() }
                    VStack { Text("本次最佳"); Text(String(format: "%.1f", engine.bestBreath)).font(.title2.monospaced()).bold().foregroundColor(.orange) }
                }.padding().background(Color.secondary.opacity(0.1)).cornerRadius(15)
                ZStack {
                    Circle().stroke(Color.blue.opacity(0.2), lineWidth: 2).frame(width: 210, height: 210)
                    Circle().fill(isTesting ? Color.blue.opacity(0.3) : Color.gray.opacity(0.1)).frame(width: 200 * (isTesting ? engine.audioLevel : 1.0))
                    VStack {
                        Text(isTesting ? "当前气息" : "准备")
                        Text(String(format: "%.1f", engine.currentBreathSeconds)).font(.system(size: 40, weight: .bold, design: .monospaced))
                    }.foregroundColor(.blue)
                }.frame(height: 220)
                Button(action: {
                    isTesting.toggle()
                    isTesting ? engine.startBreathTest() : engine.stopAll()
                }) {
                    Text(isTesting ? "结束测试" : "开始1分钟测验").bold().foregroundColor(.white).frame(width: 280, height: 60).background(isTesting ? Color.red : Color.blue).cornerRadius(30)
                }
                VStack(alignment: .leading) {
                    Text("📊 历史最高纪录 (已本地保存)").font(.headline)
                    ForEach(engine.history.prefix(5), id: \.self) { record in
                        Text("一口气持续了：\(String(format: "%.1f", record)) 秒").font(.subheadline).padding(.vertical, 2)
                        Divider()
                    }
                }.padding().background(Color.secondary.opacity(0.05)).cornerRadius(15).padding()
            }
        }
    }
}

struct PitchLabView: View {
    @ObservedObject var engine: VocalMasterEngine
    @State private var isRunning = false
    var body: some View {
        VStack(spacing: 40) {
            Text("音准实验室").font(.title.bold())
            ZStack {
                RoundedRectangle(cornerRadius: 25).fill(Color.black.opacity(0.05)).frame(height: 200)
                VStack {
                    Text(engine.currentPitch).font(.system(size: 90, weight: .black, design: .monospaced)).foregroundColor(engine.currentPitch == "---" ? .gray : .green)
                    Text("\(Int(engine.frequency)) Hz").font(.title3).foregroundColor(.secondary)
                }
            }.padding()
            Text("💡 尝试唱出一个音，并保持它稳定不变").font(.subheadline).foregroundColor(.secondary)
            Button(action: {
                isRunning.toggle()
                isRunning ? engine.startPitchDetection() : engine.stopAll()
            }) {
                Label(isRunning ? "停止实验" : "开启音准检测", systemImage: isRunning ? "stop.fill" : "music.mic").bold().foregroundColor(.white).frame(width: 250, height: 60).background(isRunning ? Color.red : Color.green).cornerRadius(30)
            }
            Spacer()
        }.padding()
    }
}
