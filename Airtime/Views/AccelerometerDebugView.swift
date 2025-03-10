import SwiftUI

struct AccelerometerDebugView: View {
    @ObservedObject var motionManager: MotionManager
    @State private var showingSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Jump Status")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "slider.horizontal.3")
                }
                .sheet(isPresented: $showingSettings) {
                    SensitivitySettingsView(motionManager: motionManager)
                }
            }
            
            // Status text
            Text(motionManager.debugStatus)
                .font(.system(.title2, design: .rounded))
                .bold()
                .foregroundStyle(statusColor(for: motionManager.debugStatus))
            
            // Mini graph of recent readings
            AccelerationGraph(samples: motionManager.recentAccelerations)
                .frame(height: 60)
                .overlay {
                    // Threshold lines
                    GeometryReader { geo in
                        let midY = geo.size.height / 2
                        
                        // Jump threshold line
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: midY - CGFloat(motionManager.jumpThreshold) * 20))
                            path.addLine(to: CGPoint(x: geo.size.width, y: midY - CGFloat(motionManager.jumpThreshold) * 20))
                        }
                        .stroke(Color.green.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        
                        // Landing threshold line
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: midY - CGFloat(motionManager.landingThreshold) * 20))
                            path.addLine(to: CGPoint(x: geo.size.width, y: midY - CGFloat(motionManager.landingThreshold) * 20))
                        }
                        .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }
    
    private func statusColor(for status: String) -> Color {
        if status.contains("Take Off") || status.contains("Accelerating") {
            return .green
        } else if status.contains("In Air") {
            return .blue
        } else if status.contains("Landed") {
            return .purple
        } else if status.contains("❌") {
            return .red
        } else if status.contains("Lowering") {
            return .orange
        } else {
            return .primary
        }
    }
}

struct SensitivitySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var motionManager: MotionManager
    @State private var jumpThreshold: Double
    @State private var landingThreshold: Double
    
    init(motionManager: MotionManager) {
        self.motionManager = motionManager
        _jumpThreshold = State(initialValue: motionManager.jumpThreshold)
        _landingThreshold = State(initialValue: motionManager.landingThreshold)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Takeoff Sensitivity: \(String(format: "%.2f", jumpThreshold))g")
                        Slider(value: $jumpThreshold, in: 0.3...1.5) { _ in
                            motionManager.updateJumpThreshold(jumpThreshold)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Landing Sensitivity: \(String(format: "%.2f", abs(landingThreshold)))g")
                        Slider(value: $landingThreshold, in: -2.0...(-0.5)) { _ in
                            motionManager.updateLandingThreshold(landingThreshold)
                        }
                    }
                } header: {
                    Text("Jump Detection")
                } footer: {
                    Text("Takeoff: Higher = needs stronger jump (0.3g to 1.5g)\nLanding: Higher = needs harder landing (0.5g to 2.0g)")
                }
                
                Section {
                    Button("Reset to Defaults") {
                        jumpThreshold = 0.8     // Match the default in MotionManager
                        landingThreshold = -1.0  // Match the default in MotionManager
                        motionManager.updateJumpThreshold(jumpThreshold)
                        motionManager.updateLandingThreshold(landingThreshold)
                    }
                }
            }
            .navigationTitle("Jump Sensitivity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct AccelerationGraph: View {
    let samples: [Double]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Zero line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                
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
            }
        }
    }
} 