ContentView.swift
import SwiftUI
import MapKit
import UIKit

struct ContentView: View {
    @StateObject private var coordinator = ScanCoordinator()
    @StateObject private var permissionManager = PermissionManager.shared
    
    @State private var isScanning = false
    @State private var showTutorial = false
    @State private var showMap = false
    @State private var showPermissionSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                // 🚨 Permissions Error Banner
                permissionErrorBanner

                // Scan Control Button
                Button(action: toggleScanning) {
                    Text(isScanning ? "Stop Scan" : "Start Scan")
                        .font(.title2)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isScanning ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                }
                .padding(.horizontal)

                // Status Indicator
                HStack {
                    Text(isScanning ? "Scanning..." : "Idle")
                        .font(.headline)
                        .foregroundColor(isScanning ? .blue : .gray)
                    if isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.2)
                    }
                }
                .animation(.easeInOut, value: isScanning)

                // Radar-style Proximity UI
                if let highestThreat = coordinator.scanResults.max(by: { $0.severityScore < $1.severityScore }) {
                    ZStack {
                        Circle()
                            .fill(signalToColor(highestThreat.device.currentRSSI).opacity(0.4))
                            .frame(width: radarSize(rssi: highestThreat.device.currentRSSI),
                                   height: radarSize(rssi: highestThreat.device.currentRSSI))
                        Circle()
                            .stroke(signalToColor(highestThreat.device.currentRSSI), lineWidth: 2)
                            .frame(width: radarSize(rssi: highestThreat.device.currentRSSI),
                                   height: radarSize(rssi: highestThreat.device.currentRSSI))
                        Text("\(highestThreat.device.currentRSSI ?? -99) dBm")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 10)
                }

                // Results Summary
                if !coordinator.scanResults.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Detected Devices/Anomalies")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ForEach(DeviceType.allCases, id: \.self) { type in
                            let count = coordinator.scanResults.filter { $0.type == type }.count
                            if count > 0 {
                                Text("\(type.rawValue.capitalized): \(count)")
                                    .font(.body)
                            }
                        }
                    }
                } else {
                    Text("No recent scans")
                        .foregroundColor(.gray)
                        .italic()
                }

                // Navigation to Results
                NavigationLink(destination: ScanSummaryView(coordinator: coordinator)) {
                    Text("View Detailed Results")
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(radius: 3)
                }

                // Feature Buttons
                HStack(spacing: 20) {
                    Button("Tutorial") { showTutorial = true }
                        .buttonStyle(FeatureButtonStyle())

                    Button("View Map") { showMap = true }
                        .buttonStyle(FeatureButtonStyle())

                    Button("Share Results") { shareScanResults() }
                        .buttonStyle(FeatureButtonStyle())
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Signal Scout")
            .sheet(isPresented: $showTutorial) {
                TutorialView()
            }
            .sheet(isPresented: $showPermissionSheet) {
                PermissionsOnboardingView()
            }
            .background(
                NavigationLink(
                    destination: MapView(devices: coordinator.scanResults.filter {
                        $0.device.latitude != nil && $0.device.longitude != nil
                    }),
                    isActive: $showMap
                ) {
                    EmptyView()
                }
            )
            .onAppear {
                permissionManager.refreshAllStatuses()
                if needsOnboardingSheet {
                    showPermissionSheet = true
                }
            }
        }
    }

    // MARK: - Radar Helper
    private func radarSize(rssi: Int?) -> CGFloat {
        guard let rssi = rssi else { return 100 }
        return CGFloat(150 + max(rssi + 100, 0))
    }

    private func signalToColor(_ rssi: Int?) -> Color {
        guard let rssi = rssi else { return .gray }
        return rssi > -50 ? .green : rssi > -70 ? .yellow : .red
    }

    // MARK: - Sharing
    private func shareScanResults() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(coordinator.scanResults)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("scan_results.json")
            try data.write(to: tempURL)

            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = scene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("❌ Failed to share scan results: \(error)")
        }
    }

    // MARK: - Toggle
    private func toggleScanning() {
        if permissionManager.allCriticalPermissionsGranted {
            isScanning ? coordinator.stopAllScans() : coordinator.startAllScans()
            isScanning.toggle()
        } else {
            showPermissionSheet = true
        }
    }

    // MARK: - Banner UI
    private var permissionErrorBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            if permissionManager.bluetoothStatus == .denied {
                Text("❌ Bluetooth permission denied.")
            }
            if permissionManager.cameraStatus == .denied {
                Text("❌ Camera permission denied.")
            }
            if permissionManager.microphoneStatus == .denied {
                Text("❌ Microphone permission denied.")
            }
            if permissionManager.locationStatus == .denied {
                Text("❌ Location permission denied.")
            }
            if !permissionManager.allCriticalPermissionsGranted {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    private var needsOnboardingSheet: Bool {
        return [
            permissionManager.bluetoothStatus,
            permissionManager.cameraStatus,
            permissionManager.locationStatus,
            permissionManager.microphoneStatus
        ].contains(.notDetermined)
    }
}
