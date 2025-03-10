import SwiftUI

struct JumpVisualizer: View {
    let jump: JumpData
    
    private var formattedHeight: String {
        let heightInCm = jump.height * 100
        if heightInCm < 1 {
            return "< 1 cm"
        } else {
            return String(format: "%.0f cm", heightInCm)
        }
    }
    
    private var formattedSpeed: String? {
        guard let speed = jump.horizontalSpeed else { return nil }
        return String(format: "%.0f km/h", speed * 3.6) // Convert m/s to km/h
    }
    
    private var formattedDistance: String? {
        guard let distance = jump.jumpDistance else { return nil }
        return String(format: "%.1f m", distance)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Height and time metrics
            HStack(spacing: 24) {
                VStack {
                    Text(formattedHeight)
                        .font(.title)
                        .bold()
                    Text("Height")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack {
                    Text(String(format: "%.2f s", jump.airTime))
                        .font(.title)
                        .bold()
                    Text("Air Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Show ski metrics if available
                if let speed = formattedSpeed {
                    VStack {
                        Text(speed)
                            .font(.title)
                            .bold()
                        Text("Speed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let distance = formattedDistance {
                    VStack {
                        Text(distance)
                            .font(.title)
                            .bold()
                        Text("Distance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Updated graph view with markers
            GraphView(
                samples: jump.accelerationSamples,
                takeoffIndex: jump.takeoffIndex,
                landingIndex: jump.landingIndex
            )
            .frame(height: 100)
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 5)
    }
}

struct GraphView: View {
    let samples: [Double]
    let takeoffIndex: Int
    let landingIndex: Int
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                
                // Acceleration line
                Path { path in
                    guard !samples.isEmpty else { return }
                    
                    let xStep = geometry.size.width / CGFloat(samples.count - 1)
                    let yScale: CGFloat = 20 // Increased scale factor
                    let midY = geometry.size.height / 2
                    
                    path.move(to: CGPoint(x: 0, y: midY - CGFloat(samples[0]) * yScale))
                    
                    for (index, sample) in samples.enumerated() {
                        let x = CGFloat(index) * xStep
                        let y = midY - CGFloat(sample) * yScale
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Color.blue, lineWidth: 2)
                
                // Takeoff marker
                let takeoffX = CGFloat(takeoffIndex) * (geometry.size.width / CGFloat(max(1, samples.count - 1)))
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .position(x: takeoffX, 
                             y: geometry.size.height / 2 - CGFloat(samples[takeoffIndex]) * 20)
                    .overlay {
                        Text("Takeoff")
                            .font(.caption2)
                            .offset(y: -15)
                    }
                
                // Landing marker
                let landingX = CGFloat(landingIndex) * (geometry.size.width / CGFloat(max(1, samples.count - 1)))
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .position(x: landingX,
                             y: geometry.size.height / 2 - CGFloat(samples[landingIndex]) * 20)
                    .overlay {
                        Text("Landing")
                            .font(.caption2)
                            .offset(y: 15)
                    }
            }
        }
    }
} 