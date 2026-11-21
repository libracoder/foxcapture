import AVFoundation
import CoreMedia

/// Reads the loudness of a ScreenCaptureKit audio buffer for auto-pause.
enum AudioLevel {
    /// Peak absolute amplitude (0...1) across all channels of `sampleBuffer`,
    /// or nil if the buffer is in a format we don't read (the caller then
    /// treats it as sound rather than guessing at silence).
    static func peak(of sampleBuffer: CMSampleBuffer) -> Float? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM else { return nil }

        let isFloat = asbd.mFormatFlags & AudioFormatFlags(kAudioFormatFlagIsFloat) != 0
        guard (isFloat && asbd.mBitsPerChannel == 32) || (!isFloat && asbd.mBitsPerChannel == 16) else {
            return nil
        }

        // Non-interleaved stereo arrives as one AudioBuffer per channel, so
        // the list needs a variable-size allocation.
        var listSize = 0
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard listSize > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        var peak: Float = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = buffer.mData else { continue }
            let bytes = Int(buffer.mDataByteSize)
            if isFloat {
                let samples = data.assumingMemoryBound(to: Float.self)
                for i in 0..<(bytes / MemoryLayout<Float>.size) {
                    peak = max(peak, abs(samples[i]))
                }
            } else {
                let samples = data.assumingMemoryBound(to: Int16.self)
                for i in 0..<(bytes / MemoryLayout<Int16>.size) {
                    peak = max(peak, abs(Float(samples[i])) / 32768)
                }
            }
        }
        // blockBuffer owns the memory `list` points into; keep it alive.
        withExtendedLifetime(blockBuffer) {}
        return peak
    }
}
