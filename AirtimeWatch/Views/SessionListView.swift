import SwiftUI

struct SessionListView: View {
    @State private var sessions: [String] = []

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "folder",
                    description: Text("Recorded sessions will appear here")
                )
            } else {
                List {
                    ForEach(sessions, id: \.self) { sessionID in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sessionID)
                                .font(.system(.caption, design: .monospaced))

                            Text(formattedDate(from: sessionID))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Sessions")
        .onAppear {
            sessions = CSVLogger.listSessions()
        }
    }

    private func formattedDate(from sessionID: String) -> String {
        // sessionID format: yyyy-MM-dd_HHmmss
        let parts = sessionID.split(separator: "_")
        guard parts.count == 2 else { return sessionID }
        let datePart = String(parts[0])
        let timePart = String(parts[1])

        let hour = String(timePart.prefix(2))
        let minute = String(timePart.dropFirst(2).prefix(2))
        return "\(datePart) \(hour):\(minute)"
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let sessionID = sessions[index]
            let url = CSVLogger.sessionURL(for: sessionID)
            try? FileManager.default.removeItem(at: url)
        }
        sessions.remove(atOffsets: offsets)
    }
}
