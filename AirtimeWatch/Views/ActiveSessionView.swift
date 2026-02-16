import SwiftUI
import WatchKit

struct ActiveSessionView: View {
    @ObservedObject var motionManager: WatchMotionManager
    @ObservedObject var workoutManager: WorkoutManager
    @Binding var isSessionActive: Bool
    @State private var showingStopConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Status indicator
                statusBadge
                    .padding(.top, 4)

                // Last jump metrics
                if motionManager.totalJumpCount > 0 {
                    lastJumpCard
                }

                // Session stats
                sessionStatsCard

                // Live acceleration indicator
                liveAccelBar

                // Mark Event button (ground truth labeling)
                Button {
                    motionManager.markEvent()
                } label: {
                    Label("Mark Jump", systemImage: "flag.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                // Stop button
                Button(role: .destructive) {
                    showingStopConfirmation = true
                } label: {
                    Label("End Session", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .confirmationDialog("End Session?", isPresented: $showingStopConfirmation) {
            Button("End & Save", role: .destructive) {
                Task {
                    await stopSession()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Subviews

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)

            Text(motionManager.statusText)
                .font(.system(.caption, design: .rounded))
                .bold()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(stateColor.opacity(0.2))
        .clipShape(Capsule())
    }

    private var lastJumpCard: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2fs", motionManager.lastAirtimeDuration))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)

            if let jump = motionManager.currentJump {
                Text(jump.formattedRotation)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text("Last Jump")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sessionStatsCard: some View {
        HStack {
            VStack {
                Text("\(motionManager.totalJumpCount)")
                    .font(.system(.title3, design: .rounded))
                    .bold()
                Text("Jumps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack {
                Text(String(format: "%.0f", motionManager.maxSpinDegrees))
                    .font(.system(.title3, design: .rounded))
                    .bold()
                Text("Max Spin")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .background(Color(.darkGray).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var liveAccelBar: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let normalized = min(motionManager.currentAccelMagnitude / 4.0, 1.0)
                let barWidth = geo.size.width * normalized

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(accelBarColor)
                        .frame(width: barWidth)
                }
            }
            .frame(height: 8)

            Text(String(format: "%.1fG", motionManager.currentAccelMagnitude))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch motionManager.detectionState {
        case .ground: return .green
        case .potentialTakeoff: return .yellow
        case .airborne: return .blue
        }
    }

    private var accelBarColor: Color {
        if motionManager.currentAccelMagnitude > motionManager.landingThreshold {
            return .red
        } else if motionManager.currentAccelMagnitude > motionManager.takeoffThreshold {
            return .orange
        }
        return .blue
    }

    private func stopSession() async {
        motionManager.stopRecording()
        motionManager.csvLogger?.closeSession()
        await workoutManager.endWorkoutSession()
        isSessionActive = false
    }
}
