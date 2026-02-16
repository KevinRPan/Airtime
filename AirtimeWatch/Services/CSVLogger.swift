import Foundation

class CSVLogger {
    private let sessionDirectory: URL
    private let sensorFileURL: URL
    private let eventsFileURL: URL
    private let marksFileURL: URL

    private var sensorFileHandle: FileHandle?
    private var eventsFileHandle: FileHandle?
    private var marksFileHandle: FileHandle?

    let sessionID: String

    init() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        sessionID = dateFormatter.string(from: Date())

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        sessionDirectory = documentsDir.appendingPathComponent("sessions/\(sessionID)")

        sensorFileURL = sessionDirectory.appendingPathComponent("sensor_data.csv")
        eventsFileURL = sessionDirectory.appendingPathComponent("jump_events.csv")
        marksFileURL = sessionDirectory.appendingPathComponent("ground_truth_marks.csv")

        createSessionFiles()
    }

    // MARK: - File Setup

    private func createSessionFiles() {
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

            // Sensor data CSV
            let sensorHeader = SensorSample.csvHeader + "\n"
            fm.createFile(atPath: sensorFileURL.path, contents: sensorHeader.data(using: .utf8))
            sensorFileHandle = try FileHandle(forWritingTo: sensorFileURL)
            sensorFileHandle?.seekToEndOfFile()

            // Jump events CSV
            let eventsHeader = "Timestamp,Duration_s,Yaw_Degrees,Peak_Accel_G,Landing_Impact_G,Sample_Count\n"
            fm.createFile(atPath: eventsFileURL.path, contents: eventsHeader.data(using: .utf8))
            eventsFileHandle = try FileHandle(forWritingTo: eventsFileURL)
            eventsFileHandle?.seekToEndOfFile()

            // Ground truth marks CSV
            let marksHeader = "Timestamp,Label\n"
            fm.createFile(atPath: marksFileURL.path, contents: marksHeader.data(using: .utf8))
            marksFileHandle = try FileHandle(forWritingTo: marksFileURL)
            marksFileHandle?.seekToEndOfFile()
        } catch {
            print("CSVLogger: Failed to create session files: \(error)")
        }
    }

    // MARK: - Writing Methods

    func writeSamples(_ samples: [SensorSample]) {
        guard !samples.isEmpty else { return }

        let rows = samples.map { $0.csvRow }.joined(separator: "\n") + "\n"
        if let data = rows.data(using: .utf8) {
            sensorFileHandle?.write(data)
        }
    }

    func writeJumpEvent(_ event: JumpEvent) {
        let dateFormatter = ISO8601DateFormatter()
        let row = "\(dateFormatter.string(from: event.startTime)),\(String(format: "%.3f", event.duration)),\(String(format: "%.1f", event.yawRotationDegrees)),\(String(format: "%.2f", event.peakUserAccel)),\(String(format: "%.2f", event.landingImpact)),\(event.samples.count)\n"

        if let data = row.data(using: .utf8) {
            eventsFileHandle?.write(data)
        }
    }

    func writeGroundTruthMark(_ mark: GroundTruthMark) {
        let dateFormatter = ISO8601DateFormatter()
        let row = "\(dateFormatter.string(from: mark.timestamp)),\(mark.label)\n"

        if let data = row.data(using: .utf8) {
            marksFileHandle?.write(data)
        }
    }

    // MARK: - Session Management

    func closeSession() {
        sensorFileHandle?.closeFile()
        eventsFileHandle?.closeFile()
        marksFileHandle?.closeFile()
        sensorFileHandle = nil
        eventsFileHandle = nil
        marksFileHandle = nil
    }

    func getSessionFiles() -> [URL] {
        return [sensorFileURL, eventsFileURL, marksFileURL]
    }

    func getSessionDirectoryURL() -> URL {
        return sessionDirectory
    }

    // MARK: - List Available Sessions

    static func listSessions() -> [String] {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionsDir = documentsDir.appendingPathComponent("sessions")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.hasDirectoryPath }
            .map { $0.lastPathComponent }
            .sorted(by: >)
    }

    static func sessionURL(for sessionID: String) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent("sessions/\(sessionID)")
    }

    deinit {
        closeSession()
    }
}
