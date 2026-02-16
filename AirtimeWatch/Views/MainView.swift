import SwiftUI

struct MainView: View {
    @StateObject private var motionManager = WatchMotionManager()
    @StateObject private var workoutManager = WorkoutManager()
    @State private var isSessionActive = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            if isSessionActive {
                ActiveSessionView(
                    motionManager: motionManager,
                    workoutManager: workoutManager,
                    isSessionActive: $isSessionActive
                )
            } else {
                startView
            }
        }
    }

    private var startView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "figure.skiing.downhill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)

                Text("Airtime")
                    .font(.headline)

                Button {
                    Task {
                        await startSession()
                    }
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                if !motionManager.sessionJumps.isEmpty {
                    Button {
                        showingHistory = true
                    } label: {
                        Label("Jump History", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                NavigationLink {
                    SessionListView()
                } label: {
                    Label("Past Sessions", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingHistory) {
            JumpHistoryView(jumps: motionManager.sessionJumps)
        }
    }

    private func startSession() async {
        let authorized = await workoutManager.requestAuthorization()
        guard authorized else { return }

        await workoutManager.startWorkoutSession()

        let logger = CSVLogger()
        motionManager.csvLogger = logger
        motionManager.startRecording()
        isSessionActive = true
    }
}
