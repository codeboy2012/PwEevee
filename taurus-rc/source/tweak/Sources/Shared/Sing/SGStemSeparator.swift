import CoreML
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum SGStemError: Error {
    case invalidModel, invalidInput, invalidOutput
}

enum SGStemShape {
    static let fftSize = 2048, stftHop = 441, stftFrames = 201
    static let bins = fftSize / 2 + 1
    static let windowFrames = (stftFrames - 1) * stftHop   // 88200, two seconds at 44.1 kHz
    // [1, real and imaginary of each bin for each channel, frame, 2].
    static let spectrum: [Int] = [1, bins * 2, stftFrames, 2]
    static let spectrumCount = spectrum.reduce(1, *)
}

@available(iOS 18.0, macOS 27.0, *)
actor SGStemSeparator {
    let windowFrames = SGStemShape.windowFrames
    private let cpu: MLModel
    private var neural: MLModel?         // nil when it could not be loaded; the CPU model then does everything
    private var neuralFailed = false     // a Neural Engine prediction failed since Spotify was last inactive
    private var lastAccelerated: Bool?
    private let dsp: SGStemSpectralDSP
    private let tensor: MLMultiArray
    private let provider: MLDictionaryFeatureProvider
    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(modelURL: URL) async throws {
        let cpuOnly = MLModelConfiguration()
        cpuOnly.computeUnits = .cpuOnly
        let cpu = try await MLModel.load(contentsOf: modelURL, configuration: cpuOnly)
        try Task.checkCancellation()
        let shape = SGStemShape.spectrum.map(NSNumber.init(value:))
        let description = cpu.modelDescription
        guard description.stateDescriptionsByName.isEmpty,
              description.inputDescriptionsByName.count == 1, description.outputDescriptionsByName.count == 1,
              let input = description.inputDescriptionsByName["spectrum"]?.multiArrayConstraint,
              let output = description.outputDescriptionsByName["vocals_spectrum"]?.multiArrayConstraint,
              input.shape == shape, output.shape == shape,
              (input.dataType == .float32 || input.dataType == .float16),
              (output.dataType == .float32 || output.dataType == .float16) else { throw SGStemError.invalidModel }
        // The Vitrine Core ML export declares float16 but accepts this float32 input tensor.
        let tensor = try MLMultiArray(shape: shape, dataType: .float32)
        guard tensor.strides.map(\.intValue) == Self.strides else { throw SGStemError.invalidInput }
        self.tensor = tensor
        self.provider = try MLDictionaryFeatureProvider(dictionary: ["spectrum": tensor])
        self.cpu = cpu
        self.dsp = try SGStemSpectralDSP()
        let accelerated = MLModelConfiguration()
        accelerated.computeUnits = .cpuAndNeuralEngine
        // Without the Neural Engine copy the CPU model still does the work, only more slowly in the foreground.
        do { self.neural = try await MLModel.load(contentsOf: modelURL, configuration: accelerated) }
        catch {
            try Task.checkCancellation()
            NSLog("[spotifyglass] Sing Neural Engine acceleration unavailable: %@", String(describing: error))
        }
    }

    // A packed row-major tensor: what encode writes and decode reads.
    private static let strides: [Int] = SGStemShape.spectrum.indices.map {
        SGStemShape.spectrum[($0 + 1)...].reduce(1, *)
    }

    func warmUp() async throws {
        try encode([Float](repeating: 0, count: windowFrames * 2))
        _ = try predict(accelerated: false)
        if neural != nil, await foreground() { _ = try predict(accelerated: true) }
    }

    func vocals(for pcm: [Float]) async throws -> [Float] {
        guard pcm.count == windowFrames * 2, pcm.allSatisfy(\.isFinite) else { throw SGStemError.invalidInput }
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        let active = neural != nil ? await foreground() : false
        if !active { neuralFailed = false }
        try encode(pcm)
        let accelerated = active && !neuralFailed
        if lastAccelerated != accelerated {
            NSLog("[spotifyglass] Sing Core ML compute policy: %@", accelerated ? "foreground CPU/Neural Engine" : "CPU only")
            lastAccelerated = accelerated
        }
        return try predict(accelerated: accelerated)
    }

    private func acquire() async {
        if running { await withCheckedContinuation { waiters.append($0) } }
        else { running = true }
    }

    private func release() {
        if waiters.isEmpty { running = false }
        else { waiters.removeFirst().resume() }
    }

    private func foreground() async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run { UIApplication.shared.applicationState == .active }
        #else
        return true
        #endif
    }

    private func encode(_ pcm: [Float]) throws {
        try dsp.encode(pcm, into: UnsafeMutableBufferPointer(
            start: tensor.dataPointer.assumingMemoryBound(to: Float.self), count: tensor.count))
    }

    private func predict(accelerated: Bool) throws -> [Float] {
        try Task.checkCancellation()
        let result: MLFeatureProvider
        if accelerated, let neural {
            do { result = try neural.prediction(from: provider) }
            catch {
                try Task.checkCancellation()
                neuralFailed = true
                NSLog("[spotifyglass] Sing using CPU after Neural Engine prediction failed: %@", String(describing: error))
                result = try cpu.prediction(from: provider)
            }
        } else { result = try cpu.prediction(from: provider) }
        try Task.checkCancellation()
        guard let output = result.featureValue(for: "vocals_spectrum")?.multiArrayValue,
              output.shape.map(\.intValue) == SGStemShape.spectrum,
              output.dataType == .float32 || output.dataType == .float16 else { throw SGStemError.invalidOutput }
        let strides = output.strides.map(\.intValue)
        var spectrum = [Float](repeating: 0, count: SGStemShape.spectrumCount)
        for row in 0..<SGStemShape.spectrum[1] {
            for frame in 0..<SGStemShape.spectrum[2] {
                for component in 0..<SGStemShape.spectrum[3] {
                    let source = row * strides[1] + frame * strides[2] + component * strides[3]
                    let target = (row * SGStemShape.spectrum[2] + frame) * SGStemShape.spectrum[3] + component
                    spectrum[target] = output.dataType == .float32
                        ? output.dataPointer.assumingMemoryBound(to: Float.self)[source]
                        : Float(output.dataPointer.assumingMemoryBound(to: Float16.self)[source])
                }
            }
        }
        return try spectrum.withUnsafeBufferPointer { try dsp.decode($0) }
    }
}
