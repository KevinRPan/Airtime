import SwiftUI

struct TimerView: View {
    @StateObject private var viewModel = TimerViewModel()
    
    var body: some View {
        VStack(spacing: 32) {
            // Timer display
            Text(viewModel.formattedTime)
                .font(.system(size: 64, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(viewModel.isFinished ? .green : .primary)
            
            // Timer controls
            HStack(spacing: 16) {
                if viewModel.isFinished {
                    // Show only reset when finished
                    Button(action: viewModel.reset) {
                        Label("Reset", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.bordered)
                } else {
                    // Start/Pause button
                    Button(action: viewModel.startPause) {
                        Label(viewModel.isRunning ? "Pause" : "Start", 
                              systemImage: viewModel.isRunning ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if viewModel.isRunning {
                        // Show finish button when running
                        Button(action: viewModel.finish) {
                            Label("Finish", systemImage: "flag.circle.fill")
                                .font(.title2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    } else {
                        // Show reset button when paused
                        Button(action: viewModel.reset) {
                            Label("Reset", systemImage: "arrow.counterclockwise.circle.fill")
                                .font(.title2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Timer")
        .navigationBarTitleDisplayMode(.inline)
    }
} 