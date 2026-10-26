import Foundation

/// Validazione minima del payload WAV prima di metterlo in cache o passarlo
/// ad `AVAudioPlayer`.
///
/// Il backend risponde con un WAV RIFF/PCM. Un corpo HTTP 200 che non lo è
/// (JSON d'errore, pagina HTML di un proxy, stream troncato) non deve essere
/// trattato come audio: senza questo controllo entrerebbe in cache e ogni
/// replay dello stesso chunk fallirebbe in silenzio.
enum WAVValidator {

    /// `true` quando `data` contiene header RIFF/WAVE, un chunk `fmt ` con
    /// almeno 16 byte e un chunk `data` non vuoto, tutti entro i limiti.
    static func isValid(_ data: Data) -> Bool {
        guard data.count >= 44 else { return false }
        guard fourCC(in: data, at: 0) == "RIFF",
              fourCC(in: data, at: 8) == "WAVE" else {
            return false
        }

        var offset = 12
        var hasFormat = false
        var hasAudio = false

        while offset + 8 <= data.count {
            let identifier = fourCC(in: data, at: offset)
            let size = chunkSize(in: data, at: offset + 4)
            let bodyStart = offset + 8

            guard size >= 0, size <= data.count - bodyStart else {
                return false
            }

            switch identifier {
            case "fmt ":
                hasFormat = size >= 16
            case "data":
                hasAudio = size > 0
            default:
                break
            }

            // I chunk RIFF sono allineati a 2 byte; il padding non è incluso
            // nella dimensione dichiarata.
            offset = bodyStart + size + (size % 2)
        }

        return hasFormat && hasAudio
    }

    private static func fourCC(in data: Data, at offset: Int) -> String {
        let start = data.startIndex + offset
        let end = start + 4
        guard start >= data.startIndex, end <= data.endIndex else { return "" }
        return String(bytes: data[start..<end], encoding: .ascii) ?? ""
    }

    private static func chunkSize(in data: Data, at offset: Int) -> Int {
        let start = data.startIndex + offset
        guard start >= data.startIndex, start + 4 <= data.endIndex else { return -1 }
        return Int(data[start])
            | Int(data[start + 1]) << 8
            | Int(data[start + 2]) << 16
            | Int(data[start + 3]) << 24
    }
}
