import SwiftUI

struct JumpHistoryView: View {
    let jumps: [JumpEvent]

    var body: some View {
        NavigationStack {
            if jumps.isEmpty {
                ContentUnavailableView(
                    "No Jumps",
                    systemImage: "figure.skiing.downhill",
                    description: Text("Jumps will appear here")
                )
            } else {
                List {
                    ForEach(jumps.reversed()) { jump in
                        JumpRowView(jump: jump)
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Jumps")
            }
        }
    }
}

struct JumpRowView: View {
    let jump: JumpEvent

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(jump.formattedDuration)
                    .font(.system(.body, design: .rounded))
                    .bold()

                Text(jump.formattedRotation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1fG", jump.peakUserAccel))
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text(timeString(from: jump.startTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
