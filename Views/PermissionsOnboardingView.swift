import SwiftUI

struct PermissionsOnboardingView: View {
    @ObservedObject var permissions = PermissionManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("Permissions Needed")
                .font(.title2).bold()

            Text("Signal Scout uses these permissions to detect hidden devices and threats.")
                .multilineTextAlignment(.center)

            permissionRow("📸 Camera", status: permissions.cameraStatus)
            permissionRow("🎤 Microphone", status: permissions.microphoneStatus)
            permissionRow("📍 Location", status: permissions.locationStatus)
            permissionRow("📶 Bluetooth", status: permissions.bluetoothStatus)

            Button("Grant Permissions") {
                permissions.requestCameraPermission()
                permissions.requestMicrophonePermission()
                permissions.requestLocationPermission()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)

            Spacer()
        }
        .padding()
    }

    private func permissionRow(_ label: String, status: PermissionStatus) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(status.rawValue.capitalized)
                .foregroundColor(status == .granted ? .green : .red)
        }
        .padding(.horizontal)
    }
}
