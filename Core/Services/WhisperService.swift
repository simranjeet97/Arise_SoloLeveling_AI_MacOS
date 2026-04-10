import Foundation
import AVFoundation

// MARK: - WhisperService

/// Records microphone audio to a temp .wav file and transcribes it using
/// the local open-source `whisper` CLI (https://github.com/openai/whisper).
///
/// No API key required — whisper runs entirely on-device.
///
/// Prerequisites:
///   pip install openai-whisper
///   # or: brew install openai-whisper (if available)
final class WhisperService: NSObject, ObservableObject {

    // MARK: Singleton

    static let shared = WhisperService()

    // MARK: - Published State

    @Published var isRecording:   Bool    = false
    @Published var audioLevel:    Float   = 0.0       // 0–1 for waveform visualisation
    @Published var transcription: String  = ""
    @Published var errorMessage:  String? = nil

    // MARK: - Private

    private let engine       = AVAudioEngine()
    private var audioFile:   AVAudioFile?
    private var tempFileURL: URL?

    // Continuation resolved by stopAndTranscribe() for the full pipeline.
    private var pendingContinuation: CheckedContinuation<String, Error>?

    // MARK: - Init

    private override init() { super.init() }

    // MARK: - Recording Lifecycle

    func startRecording() {
        guard !isRecording else { return }

        let inputNode = engine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)

        // Whisper CLI works best with WAV (PCM) input.
        let uuid = UUID().uuidString
        let tmp  = FileManager.default.temporaryDirectory
            .appendingPathComponent("arise_voice_\(uuid).wav")
        tempFileURL = tmp

        // PCM settings for WAV output — 16 kHz mono for best whisper accuracy.
        let wavSettings: [String: Any] = [
            AVFormatIDKey:           Int(kAudioFormatLinearPCM),
            AVSampleRateKey:         16000,
            AVNumberOfChannelsKey:   1,
            AVLinearPCMBitDepthKey:  16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey:   false
        ]

        do {
            audioFile = try AVAudioFile(forWriting: tmp, settings: wavSettings)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Cannot create audio file: \(error.localizedDescription)"
            }
            return
        }

        // Install tap on the input node, converting to our target format if needed.
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate:   16000,
            channels:     1,
            interleaved:  true
        )!

        // Use the input format for the tap, convert manually if sample rates differ.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }

            // Downsample / convert if the hardware format differs from 16 kHz.
            if let converted = self.convert(buffer: buffer, to: targetFormat) {
                try? self.audioFile?.write(from: converted)
                self.updateAudioLevel(from: buffer)
            } else {
                // Fallback: write raw (whisper handles many sample rates)
                try? self.audioFile?.write(from: buffer)
                self.updateAudioLevel(from: buffer)
            }
        }

        do {
            try engine.start()
            DispatchQueue.main.async {
                self.isRecording   = true
                self.transcription = ""
                self.errorMessage  = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Audio engine failed: \(error.localizedDescription)"
            }
        }
    }

    /// Stop recording. Does NOT transcribe — use stopAndTranscribe() for the pipeline.
    func stopRecording() {
        guard isRecording else { return }
        tearDownEngine()
    }

    /// Stop recording and immediately transcribe the captured audio using whisper CLI.
    /// - Returns: Transcribed string.
    func stopAndTranscribe() async throws -> String {
        guard isRecording else {
            // If not recording, attempt to transcribe any pending file.
            if let url = tempFileURL {
                return try await transcribeFile(at: url)
            }
            throw WhisperError.notRecording
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
            tearDownEngine()
            guard let url = self.tempFileURL else {
                continuation.resume(throwing: WhisperError.noAudioFile)
                self.pendingContinuation = nil
                return
            }
            Task {
                do {
                    let text = try await self.transcribeFile(at: url)
                    self.pendingContinuation?.resume(returning: text)
                } catch {
                    self.pendingContinuation?.resume(throwing: error)
                }
                self.pendingContinuation = nil
            }
        }
    }

    // MARK: - Private Helpers

    private func tearDownEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel  = 0
        }
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let samples: [Float]  = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        let sumOfSquares: Float = samples.reduce(0) { $0 + $1 * $1 }
        let rms: Float          = sqrt(sumOfSquares / Float(frameCount))
        let level               = min(1.0, rms * 20)

        DispatchQueue.main.async { self.audioLevel = level }
    }

    /// Convert a PCMBuffer to the target AVAudioFormat using AVAudioConverter.
    private func convert(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != targetFormat else { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                            frameCapacity: targetFrameCapacity) else { return nil }

        var error: NSError?
        var inputConsumed = false

        converter.convert(to: output, error: &error) { inNumPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            print("[WhisperService] Conversion error: \(error)")
            return nil
        }
        return output
    }

    // MARK: - Local Whisper CLI Transcription

    /// Transcribe a WAV file using the local `whisper` command-line tool.
    ///
    /// The CLI is discovered in this order:
    ///   1. `/usr/local/bin/whisper`  (pip install / homebrew on Intel)
    ///   2. `/opt/homebrew/bin/whisper` (homebrew on Apple Silicon)
    ///   3. `~/.local/bin/whisper`   (pip --user installs)
    ///   4. Resolved via `/usr/bin/env whisper`
    private func transcribeFile(at url: URL) async throws -> String {
        let whisperPath = resolveWhisperPath()
        guard let whisperPath else {
            throw WhisperError.whisperNotInstalled
        }

        // Prepare a dedicated temp output directory.
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("arise_whisper_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async { self.tempFileURL = nil }
        }

        // Run: whisper <file> --model base --language en --output_format txt --output_dir <dir>
        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            url.path,
            "--model",         "base",
            "--language",      "en",
            "--output_format", "txt",
            "--output_dir",    outputDir.path,
            "--verbose",       "False"
        ]

        // Capture stdout and stderr.
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        print("[WhisperService] 🎙 Running: \(whisperPath) \(process.arguments!.joined(separator: " "))")

        try process.run()

        // Wait on a background thread to avoid blocking the main thread.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                cont.resume()
            }
        }

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            throw WhisperError.transcriptionFailed("whisper exited \(process.terminationStatus): \(stderr)")
        }

        // Find the .txt output file whisper produced.
        // whisper names it after the input file: <stem>.txt
        let inputStem = url.deletingPathExtension().lastPathComponent
        let txtFile   = outputDir.appendingPathComponent("\(inputStem).txt")

        guard FileManager.default.fileExists(atPath: txtFile.path),
              let text = try? String(contentsOf: txtFile, encoding: .utf8) else {
            // Try any .txt file in the output directory as fallback.
            let allFiles = (try? FileManager.default.contentsOfDirectory(
                at: outputDir,
                includingPropertiesForKeys: nil
            )) ?? []
            if let fallback = allFiles.first(where: { $0.pathExtension == "txt" }),
               let text = try? String(contentsOf: fallback, encoding: .utf8) {
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async { self.transcription = cleaned }
                return cleaned
            }
            throw WhisperError.noTranscriptFile
        }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async { self.transcription = cleaned }
        print("[WhisperService] ✅ Transcript: \(cleaned)")
        return cleaned
    }

    /// Discover the `whisper` executable on disk.
    private func resolveWhisperPath() -> String? {
        let candidates = [
            "/usr/local/bin/whisper",
            "/opt/homebrew/bin/whisper",
            "\(NSHomeDirectory())/.local/bin/whisper",
            "\(NSHomeDirectory())/Library/Python/3.11/bin/whisper",
            "\(NSHomeDirectory())/Library/Python/3.12/bin/whisper",
            "\(NSHomeDirectory())/miniconda3/bin/whisper",
            "\(NSHomeDirectory())/anaconda3/bin/whisper"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Last resort — use `which` to find it on PATH.
        if let fromWhich = runShellCommand("/usr/bin/which", ["whisper"]),
           !fromWhich.isEmpty {
            return fromWhich.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    /// Run a simple shell command and return stdout.
    private func runShellCommand(_ executable: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    // MARK: - Errors

    enum WhisperError: LocalizedError {
        case whisperNotInstalled
        case notRecording
        case noAudioFile
        case noTranscriptFile
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .whisperNotInstalled:
                return "Whisper CLI not found. Install it with: pip install openai-whisper"
            case .notRecording:
                return "WhisperService is not recording."
            case .noAudioFile:
                return "No audio file found to transcribe."
            case .noTranscriptFile:
                return "Whisper produced no transcript file."
            case .transcriptionFailed(let msg):
                return "Whisper transcription failed: \(msg)"
            }
        }
    }
}
