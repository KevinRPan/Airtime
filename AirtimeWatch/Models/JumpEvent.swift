import Foundation

struct JumpEvent: Identifiable {
    let id = UUID()
    let startTime: Date
    let duration: TimeInterval
    let yawRotationDegrees: Double
    let peakUserAccel: Double
    let landingImpact: Double
    let samples: [SensorSample]

    var formattedDuration: String {
        String(format: "%.2fs", duration)
    }

    var formattedRotation: String {
        let absRotation = abs(yawRotationDegrees)
        if absRotation < 45 {
            return "Straight"
        }
        let nearest90 = Int(round(absRotation / 90.0)) * 90
        let direction = yawRotationDegrees >= 0 ? "R" : "L"
        return "\(nearest90)\(direction)"
    }
}

enum JumpDetectionState {
    case ground
    case potentialTakeoff
    case airborne
}

struct GroundTruthMark: Identifiable {
    let id = UUID()
    let timestamp: Date
    let label: String
}
