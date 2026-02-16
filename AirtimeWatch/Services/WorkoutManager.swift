import HealthKit
import WatchKit

@MainActor
class WorkoutManager: NSObject, ObservableObject {
    @Published var isSessionActive = false
    @Published var sessionState: HKWorkoutSessionState = .notStarted
    @Published var errorMessage: String?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    override init() {
        super.init()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "HealthKit unavailable"
            return false
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            errorMessage = "Auth failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Workout Session

    func startWorkoutSession() async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .snowSports
        configuration.locationType = .outdoor

        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()

            workoutSession?.delegate = self
            workoutBuilder?.delegate = self

            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            let startDate = Date()
            workoutSession?.startActivity(with: startDate)
            try await workoutBuilder?.beginCollection(at: startDate)

            isSessionActive = true
            sessionState = .running
        } catch {
            errorMessage = "Session failed: \(error.localizedDescription)"
        }
    }

    func endWorkoutSession() async {
        guard let session = workoutSession, let builder = workoutBuilder else { return }

        session.end()

        do {
            try await builder.endCollection(at: Date())
            try await builder.finishWorkout()
        } catch {
            errorMessage = "End failed: \(error.localizedDescription)"
        }

        isSessionActive = false
        sessionState = .ended
        workoutSession = nil
        workoutBuilder = nil
    }

    func pauseWorkoutSession() {
        workoutSession?.pause()
    }

    func resumeWorkoutSession() {
        workoutSession?.resume()
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState,
                                     date: Date) {
        Task { @MainActor in
            self.sessionState = toState
            self.isSessionActive = (toState == .running)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle collected events if needed
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Handle collected data types if needed
    }
}
