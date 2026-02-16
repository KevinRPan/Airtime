import CoreMotion
import Combine
import WatchKit

@MainActor
class WatchMotionManager: ObservableObject {
    // MARK: - Published Properties
    @Published var detectionState: JumpDetectionState = .ground
    @Published var isRecording = false
    @Published var currentJump: JumpEvent?
    @Published var recentJumps: [JumpEvent] = []
    @Published var sessionJumps: [JumpEvent] = []
    @Published var groundTruthMarks: [GroundTruthMark] = []
    @Published var statusText: String = "Ready"
    @Published var currentAccelMagnitude: Double = 0
    @Published var lastAirtimeDuration: TimeInterval = 0
    @Published var maxSpinDegrees: Double = 0
    @Published var totalJumpCount: Int = 0

    // MARK: - Sensor Buffer (Circular)
    @Published private(set) var recentSamples: [SensorSample] = []
    private let bufferCapacity = 300 // ~3-5 seconds at 50-100Hz

    // MARK: - Detection Thresholds
    var takeoffThreshold: Double = 1.5   // G-force for takeoff spike
    var landingThreshold: Double = 2.5   // G-force for landing impact
    var minimumAirtime: TimeInterval = 0.2 // 200ms minimum freefall
    var freefallAccelCeiling: Double = 0.4 // userAccel magnitude near 0 during freefall

    // MARK: - Private Properties
    private let motionManager = CMMotionManager()
    private let sampleRate: TimeInterval = 1.0 / 50.0 // 50Hz target
    private var sessionStartTime: Date?
    private var jumpStartTime: Date?
    private var jumpSamples: [SensorSample] = []
    private var accumulatedYawRadians: Double = 0
    private var lastGyroTimestamp: TimeInterval?
    private var peakAccelDuringJump: Double = 0

    // Batch write buffer for CSV logger
    private var csvBatchBuffer: [SensorSample] = []
    private let csvBatchSize = 50 * 60 // ~60 seconds at 50Hz
    var csvLogger: CSVLogger?

    // MARK: - Initialization
    init() {}

    // MARK: - Public Methods

    func startRecording() {
        guard motionManager.isDeviceMotionAvailable else {
            statusText = "Motion unavailable"
            return
        }

        sessionStartTime = Date()
        isRecording = true
        sessionJumps.removeAll()
        groundTruthMarks.removeAll()
        totalJumpCount = 0
        maxSpinDegrees = 0
        lastAirtimeDuration = 0
        detectionState = .ground
        statusText = "Recording..."

        startDeviceMotion()
    }

    func stopRecording() {
        motionManager.stopDeviceMotionUpdates()
        isRecording = false
        detectionState = .ground
        statusText = "Stopped"

        // Flush remaining CSV buffer
        flushCSVBuffer()
    }

    func markEvent(label: String = "jump") {
        let mark = GroundTruthMark(timestamp: Date(), label: label)
        groundTruthMarks.append(mark)

        // Write mark to CSV as a special row
        csvLogger?.writeGroundTruthMark(mark)

        WKInterfaceDevice.current().play(.click)
    }

    func clearSession() {
        sessionJumps.removeAll()
        recentJumps.removeAll()
        groundTruthMarks.removeAll()
        totalJumpCount = 0
        maxSpinDegrees = 0
        lastAirtimeDuration = 0
    }

    // MARK: - Private: Sensor Pipeline

    private func startDeviceMotion() {
        motionManager.deviceMotionUpdateInterval = sampleRate

        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            let sample = SensorSample(
                timestamp: motion.timestamp,
                userAccelX: motion.userAcceleration.x,
                userAccelY: motion.userAcceleration.y,
                userAccelZ: motion.userAcceleration.z,
                rotationRateX: motion.rotationRate.x,
                rotationRateY: motion.rotationRate.y,
                rotationRateZ: motion.rotationRate.z,
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y,
                gravityZ: motion.gravity.z
            )

            self.processSample(sample)
        }
    }

    private func processSample(_ sample: SensorSample) {
        // Update circular buffer
        recentSamples.append(sample)
        if recentSamples.count > bufferCapacity {
            recentSamples.removeFirst()
        }

        // Batch CSV writing
        csvBatchBuffer.append(sample)
        if csvBatchBuffer.count >= csvBatchSize {
            flushCSVBuffer()
        }

        // Update live display
        currentAccelMagnitude = sample.userAccelMagnitude

        // Run state machine
        switch detectionState {
        case .ground:
            checkForTakeoff(sample)
        case .potentialTakeoff:
            checkForAirborne(sample)
        case .airborne:
            trackAirborne(sample)
        }
    }

    // MARK: - State Machine

    private func checkForTakeoff(_ sample: SensorSample) {
        // Detect sharp positive spike in acceleration magnitude > takeoff threshold
        if sample.userAccelMagnitude > takeoffThreshold {
            detectionState = .potentialTakeoff
            jumpStartTime = Date()
            jumpSamples.removeAll()
            jumpSamples.append(sample)
            accumulatedYawRadians = 0
            lastGyroTimestamp = sample.timestamp
            peakAccelDuringJump = sample.userAccelMagnitude
            statusText = "Takeoff detected"
        }
    }

    private func checkForAirborne(_ sample: SensorSample) {
        jumpSamples.append(sample)
        integrateYaw(sample)

        // Look for freefall signature: userAcceleration magnitude settling near 0
        if sample.userAccelMagnitude < freefallAccelCeiling {
            detectionState = .airborne
            statusText = "Airborne"
        }

        // If we get another big spike without ever going near-zero, it was noise
        guard let startTime = jumpStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > 0.5 && sample.userAccelMagnitude > takeoffThreshold {
            // Likely not a real jump - reset
            resetToGround("Noise filtered")
        }
    }

    private func trackAirborne(_ sample: SensorSample) {
        jumpSamples.append(sample)
        integrateYaw(sample)
        peakAccelDuringJump = max(peakAccelDuringJump, sample.userAccelMagnitude)

        guard let startTime = jumpStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)

        // Update status with live airtime
        statusText = String(format: "Air: %.2fs", elapsed)

        // Check for landing: high-magnitude impact spike
        if sample.userAccelMagnitude > landingThreshold && elapsed > minimumAirtime * 0.5 {
            commitJump(duration: elapsed, landingImpact: sample.userAccelMagnitude)
            return
        }

        // Safety timeout: if airborne for >5 seconds, something is wrong
        if elapsed > 5.0 {
            resetToGround("Timeout")
        }
    }

    private func integrateYaw(_ sample: SensorSample) {
        guard let lastTimestamp = lastGyroTimestamp else {
            lastGyroTimestamp = sample.timestamp
            return
        }

        let dt = sample.timestamp - lastTimestamp
        guard dt > 0 && dt < 0.1 else {
            lastGyroTimestamp = sample.timestamp
            return
        }

        // Integrate Z-axis rotation rate (yaw) using trapezoidal rule
        accumulatedYawRadians += sample.rotationRateZ * dt
        lastGyroTimestamp = sample.timestamp
    }

    private func commitJump(duration: TimeInterval, landingImpact: Double) {
        guard duration >= minimumAirtime else {
            resetToGround("Too short")
            return
        }

        let yawDegrees = accumulatedYawRadians * (180.0 / .pi)

        let event = JumpEvent(
            startTime: jumpStartTime ?? Date(),
            duration: duration,
            yawRotationDegrees: yawDegrees,
            peakUserAccel: peakAccelDuringJump,
            landingImpact: landingImpact,
            samples: jumpSamples
        )

        currentJump = event
        recentJumps.insert(event, at: 0)
        if recentJumps.count > 50 {
            recentJumps.removeLast()
        }
        sessionJumps.append(event)
        totalJumpCount += 1
        lastAirtimeDuration = duration
        maxSpinDegrees = max(maxSpinDegrees, abs(yawDegrees))

        statusText = String(format: "Landed! %.2fs %@", duration, event.formattedRotation)

        // Haptic feedback
        WKInterfaceDevice.current().play(.success)

        // Log jump event
        csvLogger?.writeJumpEvent(event)

        resetToGround(nil)
    }

    private func resetToGround(_ reason: String?) {
        detectionState = .ground
        jumpStartTime = nil
        jumpSamples.removeAll()
        accumulatedYawRadians = 0
        lastGyroTimestamp = nil
        peakAccelDuringJump = 0

        if let reason = reason {
            statusText = reason
        }
    }

    // MARK: - CSV Batch Writing

    private func flushCSVBuffer() {
        guard !csvBatchBuffer.isEmpty else { return }
        csvLogger?.writeSamples(csvBatchBuffer)
        csvBatchBuffer.removeAll()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
