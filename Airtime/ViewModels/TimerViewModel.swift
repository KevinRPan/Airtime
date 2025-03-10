import Foundation

@MainActor
class TimerViewModel: ObservableObject {
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isFinished = false
    @Published private(set) var finalTime: TimeInterval?
    
    private var timer: Timer?
    
    var formattedTime: String {
        let time = finalTime ?? elapsedTime
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    func startPause() {
        if isFinished {
            reset()
        }
        
        if isRunning {
            stopTimer()
        } else {
            startTimer()
        }
    }
    
    func finish() {
        stopTimer()
        isFinished = true
        finalTime = elapsedTime
    }
    
    func reset() {
        stopTimer()
        elapsedTime = 0
        isFinished = false
        finalTime = nil
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedTime += 0.01
            }
        }
        isRunning = true
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
} 