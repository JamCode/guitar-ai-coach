import AVFoundation
import Foundation

struct DecodedTranscriptionMedia {
    let fileName: String
    let durationMs: Int
    let pcmSamples: [Float]
    let sampleRate: Double
}

enum TranscriptionMediaDecoder {
    static func probeDuration(url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return Int((CMTimeGetSeconds(duration) * 1000).rounded())
    }

    static func decode(url: URL) async throws -> DecodedTranscriptionMedia {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw TranscriptionImportError.audioTrackReadFailed
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw TranscriptionImportError.audioTrackReadFailed
        }
        reader.add(output)
        guard reader.startReading() else {
            throw TranscriptionImportError.audioTrackReadFailed
        }

        let format = try await track.load(.formatDescriptions)
        guard
            let firstDescription = format.first,
            let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(firstDescription as! CMAudioFormatDescription)
        else {
            throw TranscriptionImportError.audioTrackReadFailed
        }

        let asbd = asbdPointer.pointee
        let channelCount = max(1, Int(asbd.mChannelsPerFrame))
        let sampleRate = Double(asbd.mSampleRate)
        var samples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            if length == 0 { continue }

            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { buffer in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: buffer.baseAddress!)
            }
            guard status == noErr else { continue }

            data.withUnsafeBytes { rawBuffer in
                let frameBuffer = rawBuffer.bindMemory(to: Float.self)
                if channelCount == 1 {
                    samples.append(contentsOf: frameBuffer)
                } else {
                    let frameCount = frameBuffer.count / channelCount
                    samples.reserveCapacity(samples.count + frameCount)
                    for frameIndex in 0..<frameCount {
                        var sum: Float = 0
                        let base = frameIndex * channelCount
                        for channelIndex in 0..<channelCount {
                            sum += frameBuffer[base + channelIndex]
                        }
                        samples.append(sum / Float(channelCount))
                    }
                }
            }
        }

        guard reader.status == .completed, !samples.isEmpty else {
            throw TranscriptionImportError.audioTrackReadFailed
        }

        return DecodedTranscriptionMedia(
            fileName: url.lastPathComponent,
            durationMs: Int((CMTimeGetSeconds(duration) * 1000).rounded()),
            pcmSamples: samples,
            sampleRate: sampleRate
        )
    }
}
