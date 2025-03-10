//
//  ContentView.swift
//  Airtime
//
//  Created by Kevin Pan on 2/13/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @State private var isTracking = false
    @State private var showingJumpLog = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !motionManager.isAuthorized {
                    VStack(spacing: 16) {
                        Text("Motion Access Required")
                            .font(.title2)
                        Text("Please enable motion access in Settings to measure your jumps")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    // Header with icon
                    Label {
                        Text("Airtime")
                            .font(.title)
                            .fontWeight(.bold)
                    } icon: {
                        Image(systemName: "figure.jump")
                            .font(.title)
                    }
                    .padding(.top)
                    
                    // Buttons Stack
                    VStack(spacing: 12) {
                        // Start/Stop tracking button
                        Button(action: {
                            isTracking.toggle()
                            if isTracking {
                                motionManager.startTracking()
                            } else {
                                motionManager.stopTracking()
                            }
                        }) {
                            Label(isTracking ? "Stop Tracking" : "Start Tracking",
                                  systemImage: isTracking ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isTracking ? Color.red : Color.green)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        // View Log button (only show when not tracking and have jumps)
                        if !isTracking && !motionManager.recentJumps.isEmpty {
                            Button(action: { showingJumpLog.toggle() }) {
                                Label("View Jump Log", systemImage: "list.bullet.clipboard")
                                    .font(.title2)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    if isTracking {
                        // Debug view
                        AccelerometerDebugView(motionManager: motionManager)
                            .padding(.horizontal)
                        
                        // Live jumps list
                        if motionManager.recentJumps.isEmpty {
                            ContentUnavailableView(
                                "No Jumps Yet",
                                systemImage: "figure.jump",
                                description: Text("Start jumping to see your stats!")
                            )
                        } else {
                            List {
                                ForEach(motionManager.recentJumps) { jump in
                                    JumpVisualizer(jump: jump)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingJumpLog) {
                NavigationStack {
                    List {
                        ForEach(motionManager.recentJumps) { jump in
                            JumpVisualizer(jump: jump)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .navigationTitle("Jump Log")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingJumpLog = false
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(role: .destructive) {
                                motionManager.clearJumps()
                                showingJumpLog = false
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
    }
}

#Preview {
    ContentView()
}
