import SwiftUI

struct SignalHistoryGraph: View {
    @ObservedObject var device: DeviceModel

    var body: some View {
        GeometryReader { geo in
            let maxRSSI = -30
            let minRSSI = -100
            let width = geo.size.width
            let height = geo.size.height
            let values = device.signalHistory.suffix(30) // Last 30 points

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
        .padding()
    }
}
