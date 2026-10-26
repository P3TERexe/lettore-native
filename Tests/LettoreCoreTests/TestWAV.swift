import Foundation

/// WAV PCM minimo e valido per i test che attraversano cache e audio.
enum TestWAV {
    static func data(frames: Int = 16) -> Data {
        let frameCount = max(1, frames)
        let dataSize = frameCount * 2
        let fileSize = 36 + dataSize

        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        append(UInt32(fileSize), to: &wav)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        append(UInt32(16), to: &wav)
        append(UInt16(1), to: &wav)          // PCM
        append(UInt16(1), to: &wav)          // mono
        append(UInt32(24_000), to: &wav)     // sample rate
        append(UInt32(48_000), to: &wav)     // byte rate
        append(UInt16(2), to: &wav)          // block align
        append(UInt16(16), to: &wav)         // bits per sample
        wav.append(contentsOf: "data".utf8)
        append(UInt32(dataSize), to: &wav)
        wav.append(Data(repeating: 0, count: dataSize))
        return wav
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { buffer in
            data.append(contentsOf: buffer)
        }
    }
}
