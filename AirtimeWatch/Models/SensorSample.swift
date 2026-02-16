import Foundation

struct SensorSample: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let userAccelX: Double
    let userAccelY: Double
    let userAccelZ: Double
    let rotationRateX: Double
    let rotationRateY: Double
    let rotationRateZ: Double
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double

    var userAccelMagnitude: Double {
        sqrt(userAccelX * userAccelX + userAccelY * userAccelY + userAccelZ * userAccelZ)
    }

    var csvRow: String {
        String(format: "%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
               timestamp,
               userAccelX, userAccelY, userAccelZ,
               rotationRateX, rotationRateY, rotationRateZ,
               gravityX, gravityY, gravityZ)
    }

    static let csvHeader = "Timestamp,UserAccel_X,UserAccel_Y,UserAccel_Z,RotationRate_X,RotationRate_Y,RotationRate_Z,Gravity_X,Gravity_Y,Gravity_Z"
}
