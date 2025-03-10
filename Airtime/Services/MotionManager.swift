import CoreMotion
import Combine
import CoreLocation

@MainActor
class MotionManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthorized = false
    @Published var isInJump = false
    @Published var currentJump: JumpData?
    @Published var recentJumps: [JumpData] = []
    
    // Acceleration data
    @Published private(set) var currentAcceleration: Double = 0
    @Published private(set) var peakAcceleration: Double = 0
    @Published private(set) var recentAccelerations: [Double] = []
    
    // Jump detection thresholds
    private let jumpThreshold: Double = 0.3
    private let landingThreshold: Double = -0.4
    
    // Add altimeter properties
    private let altimeter = CMAltimeter()
    private var jumpStartAltitude: Double?
    private var currentAltitude: Double = 0
    private var peakAltitude: Double = 0
    
    // MARK: - Private Properties
    private let motionManager = CMMotionManager()
    private var jumpStartTime: Date?
    private var accelerationSamples: [Double] = []
    private var takeoffIndex: Int = 0
    
    // Configuration
    private let sampleRate: TimeInterval = 1.0 / 60.0  // 60 Hz sampling
    private let maxRecentAccelerations = 50
    private let peakWindow = 10
    private let heightCalibrationFactor: Double = 0.45
    private let gravity: Double = 9.81
    
    // Noise filtering
    private var recentPeaks: [Double] = []
    
    // Add location manager for speed tracking
    private let locationManager = CLLocationManager()
    private var currentSpeed: Double = 0
    private var takeoffSpeed: Double = 0
    
    // Add debug properties
    @Published private(set) var debugStatus: String = "Ready"
    @Published private(set) var lastPeakAcceleration: Double = 0
    
    // Add a property to track relative height change
    @Published private(set) var currentHeightChange: Double = 0
    
    // Add properties to track vertical movement
    private var previousAltitude: Double = 0
    private var isMovingUp: Bool = false
    private let altitudeUpdateInterval: TimeInterval = 0.1 // 100ms
    private var lastAltitudeUpdate: Date = Date()
    
    // Add property to track downward movement
    private var isMovingDown: Bool = false
    private var consecutiveLandingReadings: Int = 0
    private let requiredLandingReadings: Int = 3  // Number of readings needed to confirm landing
    
    // Add device motion property
    private let deviceMotion = CMMotionManager()
    
    // MARK: - Initialization
    override init() {
        super.init()
        loadSavedThresholds()
        setupLocationManager()
        checkAuthorization()
    }
    
    // MARK: - Public Methods
    func clearJumps() {
        recentJumps.removeAll()
        currentJump = nil
    }
    
    func startTracking() {
        startAccelerometer()
        if CMAltimeter.isRelativeAltitudeAvailable() {
            startAltimeter()
        }
    }
    
    func stopTracking() {
        deviceMotion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        locationManager.stopUpdatingLocation()
        isInJump = false
        currentJump = nil
    }
    
    // MARK: - Private Methods
    private func loadSavedThresholds() {
        // No need to load thresholds as they are already set
    }
    
    private func checkAuthorization() {
        guard deviceMotion.isDeviceMotionAvailable else {
            print("Device motion not available")
            return
        }
        
        CMMotionActivityManager().queryActivityStarting(from: Date(),
                                                      to: Date(),
                                                      to: .main) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.isAuthorized = error == nil
            }
        }
    }
    
    private func startAccelerometer() {
        // Use deviceMotion instead of just accelerometer
        deviceMotion.deviceMotionUpdateInterval = sampleRate
        
        deviceMotion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let motion = motion else { return }
            
            // Get gravity-free acceleration in the vertical direction
            let gravity = motion.gravity
            let userAccel = motion.userAcceleration
            
            // Calculate vertical acceleration in world coordinates
            let verticalAccel = -(
                userAccel.x * gravity.x +
                userAccel.y * gravity.y +
                userAccel.z * gravity.z
            )
            
            self?.processAcceleration(verticalAccel)
        }
    }
    
    private func startAltimeter() {
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let data = data else { return }
            
            let altitude = data.relativeAltitude.doubleValue
            self?.currentAltitude = altitude
            
            // Check vertical movement direction
            let now = Date()
            if let self = self, now.timeIntervalSince(self.lastAltitudeUpdate) >= self.altitudeUpdateInterval {
                let verticalVelocity = (altitude - self.previousAltitude) / now.timeIntervalSince(self.lastAltitudeUpdate)
                self.isMovingUp = verticalVelocity > 0.05
                self.isMovingDown = verticalVelocity < -0.05
                self.previousAltitude = altitude
                self.lastAltitudeUpdate = now
            }
            
            if self?.isInJump == true {
                let heightChange = altitude - (self?.jumpStartAltitude ?? altitude)
                self?.currentHeightChange = heightChange
                self?.peakAltitude = max(self?.peakAltitude ?? 0, heightChange)
            }
        }
    }
    
    // MARK: - Private Methods - Jump Detection
    private func updateStatus(_ acceleration: Double) {
        if isInJump {
            if let startTime = jumpStartTime {
                let airTime = Date().timeIntervalSince(startTime)
                let heightInfo = String(format: "%.0f cm", currentHeightChange * 100)
                debugStatus = String(format: "In Air (%.1fs) • Height: %@", airTime, heightInfo)
            }
        } else if acceleration < -0.2 {
            // Show height change during crouch
            let heightChange = currentAltitude - (jumpStartAltitude ?? currentAltitude)
            if heightChange < -0.1 {  // Only show if significant crouch
                let verticalDirection = isMovingUp ? "↑" : "↓"
                debugStatus = String(format: "Lowering... %@ (%.0f cm)", verticalDirection, abs(heightChange * 100))
            } else {
                debugStatus = "Lowering..."
            }
        } else if acceleration > 0.2 && isMovingUp {
            debugStatus = "Accelerating Up! ↑"
        } else if acceleration > 0.2 {
            debugStatus = "Loading..."  // Show when we have acceleration but not upward movement yet
        } else {
            debugStatus = "Ready"
        }
    }
    
    private func processAcceleration(_ acceleration: Double) {
        updateAccelerationData(acceleration)
        updateStatus(acceleration)
        
        if !isInJump {
            checkForTakeoff(acceleration)
        } else {
            checkForLanding(acceleration)
        }
        
        if isInJump {
            accelerationSamples.append(acceleration)
        }
    }
    
    private func updateAccelerationData(_ acceleration: Double) {
        currentAcceleration = acceleration
        peakAcceleration = max(peakAcceleration, acceleration)
        
        // Update recent readings
        recentAccelerations.append(acceleration)
        if recentAccelerations.count > maxRecentAccelerations {
            recentAccelerations.removeFirst()
        }
        
        // Update peak readings for noise filtering
        recentPeaks.append(abs(acceleration))
        if recentPeaks.count > peakWindow {
            recentPeaks.removeFirst()
        }
    }
    
    private func checkForTakeoff(_ acceleration: Double) {
        let avgPeak = recentPeaks.reduce(0, +) / Double(recentPeaks.count)
        
        // Detect takeoff with more lenient conditions
        if acceleration > jumpThreshold * 0.8 && // Reduced threshold requirement
           (isMovingUp || acceleration > jumpThreshold) { // Allow either condition
            debugStatus = "🚀 Take Off!"
            startJump()
        }
    }
    
    private func checkForLanding(_ acceleration: Double) {
        guard let startTime = jumpStartTime else { return }
        let currentDuration = Date().timeIntervalSince(startTime)
        
        if currentDuration > maximumJumpDuration {
            debugStatus = "❌ Jump too long"
            cancelJump()
            return
        }
        
        // Detect landing based on downward movement and impact
        let isPastPeak = currentHeightChange < peakAltitude * 0.5 // Past the peak of the jump
        
        if (acceleration < landingThreshold) || // Strong impact
           (isMovingDown && isPastPeak) { // Moving down after reaching peak
            handleLanding()
        }
    }
    
    // MARK: - Private Methods - Jump State Management
    private func startJump() {
        isInJump = true
        jumpStartTime = Date()
        jumpStartAltitude = currentAltitude
        previousAltitude = currentAltitude
        currentHeightChange = 0
        consecutiveLandingReadings = 0
        takeoffSpeed = currentSpeed
        peakAltitude = 0
        accelerationSamples.removeAll()
        peakAcceleration = 0
        takeoffIndex = 0
    }
    
    private func endJump() {
        guard let startTime = jumpStartTime else { return }
        
        let airTime = Date().timeIntervalSince(startTime)
        let jump = createJumpData(startTime: startTime, airTime: airTime)
        
        if let jump = jump {
            currentJump = jump
            recentJumps.insert(jump, at: 0)
            
            if recentJumps.count > 20 {
                recentJumps.removeLast()
            }
        }
        
        cancelJump()
    }
    
    private func createJumpData(startTime: Date, airTime: TimeInterval) -> JumpData? {
        guard airTime >= minimumJumpDuration && airTime <= maximumJumpDuration else {
            return nil
        }
        
        let height = peakAltitude > 0 ? peakAltitude : calculateHeightFromAcceleration(airTime)
        
        return JumpData(
            height: height,
            airTime: airTime,
            timestamp: startTime,
            accelerationSamples: accelerationSamples,
            takeoffIndex: takeoffIndex,
            landingIndex: accelerationSamples.count - 1
        )
    }
    
    private func calculateHeightFromAcceleration(_ airTime: TimeInterval) -> Double {
        let peakUpwardVelocity = max(0, peakAcceleration) * airTime * 0.5
        let heightFromAccel = (peakUpwardVelocity * airTime) - 
                            (gravity * pow(airTime, 2)) / 2
        return min(max(heightFromAccel, 0), 2.0)
    }
    
    private func cancelJump() {
        isInJump = false
        jumpStartTime = nil
        jumpStartAltitude = nil
        previousAltitude = currentAltitude
        currentHeightChange = 0
        consecutiveLandingReadings = 0
        peakAltitude = 0
        accelerationSamples.removeAll()
        peakAcceleration = 0
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .other
        locationManager.distanceFilter = 1 // Update every meter
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    private func handleLanding() {
        guard isInJump else { return }
        guard let startTime = jumpStartTime else { return }
        
        let currentDuration = Date().timeIntervalSince(startTime)
        if currentDuration >= minimumJumpDuration {
            let finalHeight = String(format: "%.0f cm", peakAltitude * 100)
            debugStatus = "🛬 Landed! Peak: \(finalHeight)"
            endJump()
        } else {
            debugStatus = "❌ Too short"
            cancelJump()
        }
    }
    
    deinit {
        deviceMotion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }
}

// MARK: - Location Manager Delegate
@MainActor
extension MotionManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let speed = location.speed > 0 ? location.speed : 0
        
        Task { @MainActor in
            self.currentSpeed = speed
        }
    }
} 