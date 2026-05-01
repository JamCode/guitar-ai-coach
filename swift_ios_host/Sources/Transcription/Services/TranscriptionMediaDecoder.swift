import AVFoundation
import CoreMedia
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
            let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(firstDescription)
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

    /// 将单声道 Float PCM 写为 WAV（16-bit PCM），用于远程识别上传兼容性。
    static func writeWAV(samples: [Float], sampleRate: Double, to destinationURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        guard let stream = OutputStream(url: destinationURL, append: false) else {
            throw TranscriptionImportError.audioExportFailed
        }
        stream.open()
        defer { stream.close() }

        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleRateUInt32 = UInt32(max(8_000, Int(sampleRate.rounded())))
        let byteRate = sampleRateUInt32 * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)

        let pcmDataSize = UInt32(samples.count * Int(bitsPerSample / 8))
        let riffChunkSize = 36 + pcmDataSize

        func writeBytes<T>(_ value: T) {
            var v = value
            withUnsafeBytes(of: &v) { raw in
                _ = raw.baseAddress.map {
                    stream.write($0.assumingMemoryBound(to: UInt8.self), maxLength: raw.count)
                }
            }
        }
        func writeASCII(_ str: String) {
            let bytes = Array(str.utf8)
            _ = bytes.withUnsafeBytes {
                stream.write($0.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: bytes.count)
            }
        }

        writeASCII("RIFF")
        writeBytes(riffChunkSize.littleEndian)
        writeASCII("WAVE")
        writeASCII("fmt ")
        writeBytes(UInt32(16).littleEndian) // PCM fmt chunk size
        writeBytes(UInt16(1).littleEndian) // PCM format
        writeBytes(numChannels.littleEndian)
        writeBytes(sampleRateUInt32.littleEndian)
        writeBytes(byteRate.littleEndian)
        writeBytes(blockAlign.littleEndian)
        writeBytes(bitsPerSample.littleEndian)
        writeASCII("data")
        writeBytes(pcmDataSize.littleEndian)

        var pcm = Data(capacity: Int(pcmDataSize))
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let v = Int16((clamped * Float(Int16.max)).rounded())
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }
        _ = pcm.withUnsafeBytes {
            stream.write($0.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: pcm.count)
        }
    }

    /// 仅导出音轨为 M4A（AAC），用于长期存储，避免整段视频占空间。
    static func exportM4A(from sourceURL: URL, to destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionImportError.audioExportFailed
        }
        session.outputURL = destinationURL
        session.outputFileType = .m4a
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        guard session.status == .completed else {
            throw TranscriptionImportError.audioExportFailed
        }
    }

    /// 远程识别上传用：方案 A，直接走系统 AppleM4A 导出链路，优先稳定性。
    static func exportCompressedM4AForRemoteUpload(
        from sourceURL: URL,
        to destinationURL: URL,
        aacBitrate: Int = 96_000
    ) async throws {
        _ = aacBitrate // kept for API compatibility; AppleM4A preset manages encoder settings.
        try await exportM4A(from: sourceURL, to: destinationURL)
    }

    /// 线性重采样到 22050 Hz 单声道（与 ONNX 管线一致，体积可控）。
    nonisolated static func linearResampleTo22050(samples: [Float], sourceSampleRate: Double) -> [Float] {
        let srOut = 22_050.0
        guard sourceSampleRate > 0, !samples.isEmpty else { return samples }
        if abs(sourceSampleRate - srOut) < 1 { return samples }
        let ratio = srOut / sourceSampleRate
        let outCount = max(1, Int((Double(samples.count) * ratio).rounded(.down)))
        var out = [Float](repeating: 0, count: outCount)
        let last = samples.count - 1
        for i in 0..<outCount {
            let srcPos = Double(i) / ratio
            let idx = min(Int(srcPos), last)
            let frac = Float(srcPos - Double(idx))
            if idx >= last {
                out[i] = samples[last]
            } else {
                out[i] = samples[idx] * (1 - frac) + samples[idx + 1] * frac
            }
        }
        return out
    }

    /// 将已是 22050 Hz 的单声道 float PCM 写成 m4a（AAC）。
    nonisolated static func writeAAC_M4A(
        pcmSamples: [Float],
        sampleRate: Double,
        aacBitrate: Int,
        to destinationURL: URL
    ) throws {
        guard !pcmSamples.isEmpty else {
            throw TranscriptionImportError.audioExportFailed
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionImportError.audioExportFailed
        }
        let pcmFormatDescription = pcmFormat.formatDescription

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .m4a)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: aacBitrate,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw TranscriptionImportError.audioExportFailed
        }
        writer.add(writerInput)
        guard writer.startWriting() else {
            throw TranscriptionImportError.audioExportFailed
        }
        writer.startSession(atSourceTime: .zero)

        let chunkFrames = 4096
        var frameIndex = 0
        var pts = CMTime.zero
        let timescale = CMTimeScale(sampleRate.rounded())

        while frameIndex < pcmSamples.count {
            let end = min(frameIndex + chunkFrames, pcmSamples.count)
            let n = end - frameIndex
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(n)) else {
                throw TranscriptionImportError.audioExportFailed
            }
            pcmBuffer.frameLength = AVAudioFrameCount(n)
            pcmSamples.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress, let dst = pcmBuffer.floatChannelData?.pointee else { return }
                dst.update(from: base.advanced(by: frameIndex), count: n)
            }

            let sampleBuffer = try makePCMSampleBufferForAACWriter(
                pcmBuffer: pcmBuffer,
                pcmFormatDescription: pcmFormatDescription,
                presentationTimeStamp: pts
            )

            var spin = 0
            while !writerInput.isReadyForMoreMediaData {
                spin += 1
                if spin > 50_000 { throw TranscriptionImportError.audioExportFailed }
                Thread.sleep(forTimeInterval: 0.0005)
            }
            guard writerInput.append(sampleBuffer) else {
                throw TranscriptionImportError.audioExportFailed
            }

            let chunkDuration = CMTime(value: CMTimeValue(n), timescale: timescale)
            pts = CMTimeAdd(pts, chunkDuration)
            frameIndex = end
        }

        writerInput.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting {
            sem.signal()
        }
        sem.wait()
        if writer.status == .failed {
            throw writer.error ?? TranscriptionImportError.audioExportFailed
        }
        guard writer.status == .completed else {
            throw TranscriptionImportError.audioExportFailed
        }
    }

    nonisolated private static func makePCMSampleBufferForAACWriter(
        pcmBuffer: AVAudioPCMBuffer,
        pcmFormatDescription: CMFormatDescription,
        presentationTimeStamp: CMTime
    ) throws -> CMSampleBuffer {
        let frameCount = Int(pcmBuffer.frameLength)
        let bytesPerFrame = Int(pcmBuffer.format.streamDescription.pointee.mBytesPerFrame)
        let totalBytes = frameCount * bytesPerFrame

        guard let base = pcmBuffer.floatChannelData?.pointee else {
            throw TranscriptionImportError.audioExportFailed
        }

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: totalBytes,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: totalBytes,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw TranscriptionImportError.audioExportFailed
        }

        status = CMBlockBufferReplaceDataBytes(
            with: UnsafeRawPointer(base),
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: totalBytes
        )
        guard status == noErr else {
            throw TranscriptionImportError.audioExportFailed
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(pcmBuffer.format.sampleRate)),
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: pcmFormatDescription,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw TranscriptionImportError.audioExportFailed
        }
        return sampleBuffer
    }
}
