import Foundation
import AVFoundation
import Accelerate
import Combine

class AudioAnalyzer: NSObject, ObservableObject {
    private var engine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var bufferSize: AVAudioFrameCount = 4096
    private var fftSetup: FFTSetup?
    private let threshold: Float = 0.1  // Detection threshold
    private let detectionRange: ClosedRange<Double> = 18000...22000

    @Published var isDetectingUltrasonic = false

    override init() {
        super.init()
        setupAudioEngine()
        setupFFT()
    }

    // MARK: - Audio Setup
    private func setupAudioEngine() {
        engine = AVAudioEngine()
        inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
    }

    private func setupFFT() {
        let log2Size = log2(Float(bufferSize))
        guard log2Size == floor(log2Size) else {
            print("⚠️ Buffer size must be power of 2.")
            return
        }
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2Size), FFTRadix(kFFTRadix2))
    }

    // MARK: - Start Detection
    func startDetection() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])

            // ✅ Select built-in mic if available
            if let availableInputs = session.availableInputs {
                for input in availableInputs where input.portType == .builtInMic {
                    try session.setPreferredInput(input)
                }
            }

            try session.setActive(true, options: [])
            try engine.start()

            isDetectingUltrasonic = true
            print("🎧 Ultrasonic detection started.")
        } catch {
            print("❌ Failed to start audio session or engine: \(error)")
        }
    }

    // MARK: - Stop Detection
    func stopDetection() {
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
        isDetectingUltrasonic = false
        print("🛑 Ultrasonic detection stopped.")
    }

    // MARK: - Process Audio
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)

        let signal = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        let magnitudes = computeFFT(signal: signal)

        // Calculate frequency bins
        let sampleRate = buffer.format.sampleRate
        let binWidth = sampleRate / Double(bufferSize)

        let startBin = Int(detectionRange.lowerBound / binWidth)
        let endBin = min(Int(detectionRange.upperBound / binWidth), magnitudes.count - 1)

        let ultrasonicSlice = magnitudes[startBin...endBin]
        if let maxMagnitude = ultrasonicSlice.max(), maxMagnitude > threshold {
            print("📢 Ultrasonic chirp detected at \(Date()) | Magnitude: \(maxMagnitude)")
            // You can call a delegate or push an alert here
        }
    }

    private func computeFFT(signal: [Float]) -> [Float] {
        guard let fftSetup = fftSetup else { return [] }

        let log2n = vDSP_Length(log2(Float(bufferSize)))
        var real = signal
        var imaginary = [Float](repeating: 0.0, count: signal.count)

        var splitComplex = DSPSplitComplex(realp: &real, imagp: &imaginary)
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0.0, count: signal.count / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(magnitudes.count))
        vDSP_vsmul(sqrtArray(magnitudes), 1, [2.0 / Float(bufferSize)], &magnitudes, 1, vDSP_Length(magnitudes.count))

        return magnitudes
    }

    private func sqrtArray(_ input: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: input.count)
        vvsqrtf(&result, input, [Int32(input.count)])
        return result
    }

    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }
}

