import Foundation

struct JumpData: Identifiable {
    let id = UUID()
    let height: Double      // in meters
    let airTime: TimeInterval
    let timestamp: Date
    let accelerationSamples: [Double]
    let takeoffIndex: Int
    let landingIndex: Int
} 