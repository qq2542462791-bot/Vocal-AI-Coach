import SwiftUI

struct BreathView: View {
    @ObservedObject var engine: VocalMasterEngine
    @State private var isRunning = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("一口气挑战").font(.title2.bold())
            
            HStack {
                VStack {
                    Text("剩余时间")
                    Text("\(engine.remainingTime)s").font(.title3.bold())
                }
                Spacer()
                VStack {
                    Text("历史最佳")
                    Text(String(format: "%.1f", engine.bestBreath) + "s").font(.title3.bold())
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            
            ZStack {
                Circle().fill(Color.blue.opacity(0.1)).frame(width: 200)
                Circle().fill(Color.blue.opacity(0.3)).frame(width: 200 * engine.audioLevel)
                Text(String(format: "%.1f", engine.currentBreathSeconds)).font(.system(size: 50, weight: .bold))
            }
            
            // 修正后的 Button 写法
            Button(action: {
                self.isRunning.toggle()
                if self.isRunning { engine.startBreath() } 
                else { engine.stopAll() }
            }) {
                Text(isRunning ? "结束测验" : "开始 1 分钟挑战")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            
            VStack {
                // 使用 indices 解决 Hashable 报错
                ForEach(engine.history.indices, id: \.self) { index in
                    Text("记录: \(String(format: "%.1f", engine.history[index])) 秒").font(.caption)
                }
            }
        }
    }
}

struct PitchView: View {
    @ObservedObject var engine: VocalMasterEngine
    @State private var isPitching = false
    
    var body: some View {
        VStack(spacing: 25) {
            Text("音准实验室").font(.title2.bold())
            Text(engine.currentPitch).font(.system(size: 70, weight: .black)).foregroundColor(.green)
            
            Button(action: {
                self.isPitching.toggle()
                if self.isPitching { engine.startPitch() }
                else { engine.stopAll() }
            }) {
                Text(isPitching ? "停止检测" : "开启检测")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
}
