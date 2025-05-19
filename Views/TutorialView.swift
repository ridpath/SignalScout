import SwiftUI

struct TutorialView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text("📡 Welcome to Signal Scout")
                    .font(.title)
                    .bold()

                Text("This app helps you detect hidden trackers, electromagnetic anomalies, and reflective IR devices using only your iPhone.")
                    .font(.body)

                Divider()

                Text("🛠 How to Use")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Tap **Start Scan** to begin detecting signals.", systemImage: "play.circle.fill")
                    Label("The radar shows the **strongest nearby signal**.", systemImage: "scope")
                    Label("**View Map** shows device locations by GPS.", systemImage: "map.fill")
                    Label("**Share Results** to export detailed JSON logs.", systemImage: "square.and.arrow.up.fill")
                }
                .font(.body)

                Divider()

                Text("🧠 Best Practices")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    Text("• Move slowly during scans to improve accuracy.")
                    Text("• Run multiple scans over time for correlation.")
                    Text("• Keep permissions granted for better results.")
                }

                Divider()

                Text("🔐 Privacy & Safety")
                    .font(.headline)

                Text("All scan data stays on your device unless you choose to export it. No tracking or analytics are used.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Tutorial")
    }
}

struct TutorialView_Previews: PreviewProvider {
    static var previews: some View {
        TutorialView()
    }
