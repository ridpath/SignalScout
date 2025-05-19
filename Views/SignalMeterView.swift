import SwiftUI

/// A live visual meter for displaying device signal strength and history.
struct SignalMeterView: View {
    @ObservedObject var device: DeviceModel

    var body: some View {
        VStack(spacing: 16) {
            // 🔵 Circle Visual Meter
            ZStack {
                Circle()
                    .fill(signalColor)
                    .frame(width: circleSize, height: circleSize)
                    .shadow(radius: 4)
                Text("\(device.currentRSSI ?? -99) dBm")
                    .foregroundColor(.white)
                    .font(.headline)
            }

            // 📈 Historical RSSI Graph
            SignalHistoryGraph(device: device)
        }
        .padding()
    }

    private var circleSize: CGFloat {
        guard let rssi = device.currentRSSI else { return 100 }
        return CGFloat(100 + max(rssi + 100, 0))
    }

    private var signalColor: Color {
        guard let rssi = device.currentRSSI else { return .gray }
        return rssi > -50 ? .green :
               rssi > -70 ? .yellow :
                            .red
    }
}

/// A simple sparkline graph of the last 30 RSSI samples.
struct SignalHistoryGraph: View {
    @ObservedObject var device: DeviceModel

    var body: some View {
        GeometryReader { geo in
            let maxRSSI = -30
            let minRSSI = -100
            let width = geo.size.width
            let height = geo.size.height
            let values = device.signalHistory.suffix(30)

            Path { path in
                for (index, sample) in values.enumerated() {
                    let x = width * CGFloat(index) / CGFloat(values.count)
                    let normalized = Double(sample.rssi - minRSSI) / Double(maxRSSI - minRSSI)
                    let y = height * CGFloat(1 - normalized)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.blue, lineWidth: 2)
        }
        .frame(height: 100)
        .padding(.horizontal, 8)
    }
}
