import CoreML
import Foundation

struct CoreMLStemSeparationRunner: StemSeparationModelRunning {
    let stems: [StemKind] = [.vocals, .accompaniment]
    private let model: MLModel
    private let outputName: String
    private let processor: StemSeparationSpectrogramProcessor
    private let compiledModelURL: URL?

    init(modelURL: URL? = nil) throws {
        guard let resolvedURL = modelURL ?? Self.defaultModelURL() else {
            throw StemSeparationError.modelNotConfigured
        }
        let loadURL: URL
        if resolvedURL.pathExtension == "mlpackage" || resolvedURL.pathExtension == "mlmodel" {
            let compiledURL = try MLModel.compileModel(at: resolvedURL)
            self.compiledModelURL = compiledURL
            loadURL = compiledURL
        } else {
            self.compiledModelURL = nil
            loadURL = resolvedURL
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        self.model = try MLModel(contentsOf: loadURL, configuration: configuration)
        guard let outputName = model.modelDescription.outputDescriptionsByName.keys.first else {
            throw StemSeparationError.modelOutputInvalid
        }
        guard let processor = StemSeparationSpectrogramProcessor() else {
            throw StemSeparationError.invalidConfiguration
        }
        self.outputName = outputName
        self.processor = processor
    }

    func separate(samples: [Float], sampleRate: Double) async throws -> [StemKind: [Float]] {
        guard abs(sampleRate - 44_100) < 1 else {
            throw StemSeparationError.invalidConfiguration
        }
        let input = processor.makeModelInputs(samples: samples)
        var masksByStem: [StemKind: [[Float]]] = [
            .vocals: [],
            .accompaniment: [],
        ]

        for splitIndex in 0..<input.splitCount {
            let magnitude = processor.makeMagnitudeInput(input, splitIndex: splitIndex)
            let modelInput = try makeMultiArray(values: magnitude)
            let provider = try MLDictionaryFeatureProvider(dictionary: ["x": MLFeatureValue(multiArray: modelInput)])
            let output = try await predict(provider)
            guard let multiArray = output.featureValue(for: outputName)?.multiArrayValue else {
                throw StemSeparationError.modelOutputInvalid
            }
            let masks = try readMasks(from: multiArray)
            masksByStem[.vocals]?.append(masks.vocals)
            masksByStem[.accompaniment]?.append(masks.accompaniment)
        }

        return try processor.synthesize(input: input, masksByStem: masksByStem)
    }

    private func predict(_ provider: MLFeatureProvider) async throws -> MLFeatureProvider {
        try await Task.detached(priority: .userInitiated) {
            try model.prediction(from: provider)
        }.value
    }

    private func makeMultiArray(values: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [2, 1, 512, 1024], dataType: .float32)
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: values.count)
        pointer.update(from: values, count: values.count)
        return array
    }

    private func readMasks(from array: MLMultiArray) throws -> (vocals: [Float], accompaniment: [Float]) {
        let expectedPerStemCount = 2 * 512 * 1024
        guard array.count >= expectedPerStemCount * 2 else {
            throw StemSeparationError.modelOutputInvalid
        }
        var vocals = [Float](repeating: 0, count: expectedPerStemCount)
        var accompaniment = [Float](repeating: 0, count: expectedPerStemCount)

        switch array.dataType {
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: array.count)
            for i in 0..<expectedPerStemCount {
                vocals[i] = Float(Float16(bitPattern: pointer[i]))
                accompaniment[i] = Float(Float16(bitPattern: pointer[expectedPerStemCount + i]))
            }
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            vocals.withUnsafeMutableBufferPointer { $0.baseAddress?.update(from: pointer, count: expectedPerStemCount) }
            accompaniment.withUnsafeMutableBufferPointer {
                $0.baseAddress?.update(from: pointer.advanced(by: expectedPerStemCount), count: expectedPerStemCount)
            }
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: array.count)
            for i in 0..<expectedPerStemCount {
                vocals[i] = Float(pointer[i])
                accompaniment[i] = Float(pointer[expectedPerStemCount + i])
            }
        default:
            throw StemSeparationError.modelOutputInvalid
        }
        return (vocals, accompaniment)
    }

    private static func defaultModelURL() -> URL? {
        if let compiled = Bundle.main.url(forResource: "stemseparation", withExtension: "mlmodelc") {
            return compiled
        }
        if let package = Bundle.main.url(forResource: "stemseparation", withExtension: "mlpackage") {
            return package
        }
        return nil
    }
}
