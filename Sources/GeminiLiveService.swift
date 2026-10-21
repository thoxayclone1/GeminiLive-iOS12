import Foundation
import AVFoundation
import QuartzCore
import Starscream

enum LiveState {
    case disconnected
    case connecting
    case listeningUser      // Đang nghe bạn nói
    case waitingResponse    // Đã bấm kết thúc câu (hoặc VAD ngắt), chờ Gemini phản hồi
    case geminiSpeaking     // Gemini đang nói
    case muted              // Đang tắt Mic
}

protocol GeminiLiveServiceDelegate: AnyObject {
    func didChangeState(_ state: LiveState)
    func didUpdateAudioLevel(_ level: CGFloat)
    func didUpdateTranscript(userText: String?, geminiText: String?)
    func didEncounterError(_ message: String)
}

final class GeminiLiveService: NSObject {
    weak var delegate: GeminiLiveServiceDelegate?

    // Model mặc định thế hệ mới nhất theo chuẩn AI Studio Live API
    private let defaultModel = "models/gemini-3.8-live"

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "gemini_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gemini_api_key") }
    }

    var modelName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "gemini_model") ?? defaultModel
            let retiredModels: Set<String> = [
                "",
                "gemini-2.0-flash-exp",
                "models/gemini-2.0-flash-exp",
                "gemini-2.0-flash-live-001",
                "models/gemini-2.0-flash-live-001",
                "gemini-live-2.5-flash-preview",
                "models/gemini-live-2.5-flash-preview",
                "models/gemini-3.1-flash-live-preview"
            ]
            if retiredModels.contains(saved) || saved.contains("projects/") || saved.contains("publishers/") {
                return defaultModel
            }
            return saved
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.contains("projects/") || trimmed.contains("publishers/") {
                UserDefaults.standard.set(defaultModel, forKey: "gemini_model")
            } else {
                UserDefaults.standard.set(trimmed, forKey: "gemini_model")
            }
        }
    }

    var voiceName: String {
        get { UserDefaults.standard.string(forKey: "gemini_voice") ?? "Puck" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gemini_voice") }
    }

    var systemPrompt: String {
        get {
            UserDefaults.standard.string(forKey: "gemini_sys_prompt")
            ?? "Bạn là trợ lý AI thông minh, trả lời ngắn gọn, tự nhiên bằng tiếng Việt."
        }
        set { UserDefaults.standard.set(newValue, forKey: "gemini_sys_prompt") }
    }

    var isManualTurnMode: Bool = false // Mặc định bật Tự động (VAD) để đàm thoại tự nhiên ngay khi kết nối
    private(set) var isMuted: Bool = false
    private(set) var state: LiveState = .disconnected {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.didChangeState(self.state)
            }
        }
    }

    private var socket: WebSocket?
    private var isUserInitiatedDisconnect = false

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isPlayerNodeAttached = false
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24000,
        channels: 1,
        interleaved: false
    )!

    private var isSetupComplete = false
    private var isManualTurnActive = false
    private var isServerTurnComplete = true
    private var scheduledBuffersCount = 0
    private var speechEndCooldownUntil: TimeInterval = 0
    private var currentUserTranscript = ""
    private var currentGeminiTranscript = ""

    override init() {
        super.init()
        let saved = UserDefaults.standard.string(forKey: "gemini_model") ?? ""
        if saved.contains("projects/") || saved.contains("gemini-2.0") {
            UserDefaults.standard.set(defaultModel, forKey: "gemini_model")
        }
        audioEngine.attach(playerNode)
        isPlayerNodeAttached = true
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        setupAudioSessionNotifications()
    }

    func connect() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            delegate?.didEncounterError("Vui lòng nhấn vào ⚙️ Cài đặt để nhập Gemini API Key.")
            return
        }

        openWebSocketConnection(withKey: trimmedKey)
    }

    private func openWebSocketConnection(withKey key: String) {
        isUserInitiatedDisconnect = true
        socket?.disconnect()
        socket = nil
        stopAudioEngine()

        isUserInitiatedDisconnect = false
        state = .connecting
        isSetupComplete = false
        isManualTurnActive = false
        isServerTurnComplete = true
        scheduledBuffersCount = 0

        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(encodedKey)"

        guard let url = URL(string: urlString) else {
            delegate?.didEncounterError("URL kết nối không hợp lệ.")
            state = .disconnected
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let ws = WebSocket(request: request)
        ws.onConnect = { [weak self] in
            self?.sendInitialSetup()
        }
        ws.onDisconnect = { [weak self] error in
            guard let self = self else { return }
            self.stopAudioEngine()

            if self.isUserInitiatedDisconnect {
                self.state = .disconnected
                return
            }

            self.state = .disconnected
            if let wsErr = error as? WSError {
                self.delegate?.didEncounterError("Ngắt kết nối (\(wsErr.code)): \(wsErr.message)")
            } else if let err = error {
                self.delegate?.didEncounterError("Ngắt kết nối: \(err.localizedDescription)")
            }
        }
        ws.onText = { [weak self] text in
            self?.handleServerPayload(text)
        }
        ws.onData = { [weak self] data in
            if let text = String(data: data, encoding: .utf8) {
                self?.handleServerPayload(text)
            }
        }
        self.socket = ws
        ws.connect()
    }

    func disconnect() {
        isUserInitiatedDisconnect = true
        socket?.disconnect()
        socket = nil
        stopAudioEngine()
        isSetupComplete = false
        isManualTurnActive = false
        isServerTurnComplete = true
        scheduledBuffersCount = 0
        state = .disconnected
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            if isManualTurnMode && isManualTurnActive {
                sendJSON(["realtimeInput": ["activityEnd": [:]]])
                isManualTurnActive = false
            } else if !isManualTurnMode && isSetupComplete {
                sendJSON(["realtimeInput": ["audioStreamEnd": true]])
            }
            state = .muted
        } else if isSetupComplete {
            state = .listeningUser
        }
    }

    func toggleTurnMode() {
        isManualTurnMode.toggle()
        if state != .disconnected {
            connect()
        }
    }

    func finishUserTurnManually() {
        guard isSetupComplete, let ws = socket, ws.isConnected else { return }

        // Nếu Gemini đang nói, chạm quả cầu sẽ ngắt lời ngay lập tức để người dùng nói
        if state == .geminiSpeaking {
            interruptPlayback()
            state = isMuted ? .muted : .listeningUser
            return
        }

        guard isManualTurnMode else { return }

        if isManualTurnActive {
            // Chuẩn v1beta: Dùng activityEnd thay vì clientContent.turnComplete rỗng
            let payload: [String: Any] = [
                "realtimeInput": [
                    "activityEnd": [:]
                ]
            ]
            sendJSON(payload)
            isManualTurnActive = false
            state = .waitingResponse
        }
    }

    func sendVideoFrame(jpegData: Data) {
        guard isSetupComplete, let ws = socket, ws.isConnected else { return }
        // Không gửi frame khi đang đợi hoặc khi đã tắt mic ở chế độ thủ công
        if state == .waitingResponse { return }

        let base64Image = jpegData.base64EncodedString()
        // Chuẩn v1beta: Dùng trường "video" thay vì "mediaChunks"
        let payload: [String: Any] = [
            "realtimeInput": [
                "video": [
                    "mimeType": "image/jpeg",
                    "data": base64Image
                ]
            ]
        ]
        sendJSON(payload)
    }

    private func resolvedModelPath() -> String {
        let raw = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("models/") {
            return raw
        }
        let cleanName = raw.isEmpty ? "gemini-3.8-live" : raw
        return "models/\(cleanName)"
    }

    private func sendInitialSetup() {
        let formattedModel = resolvedModelPath()

        var setupContent: [String: Any] = [
            "model": formattedModel,
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": [
                            "voiceName": voiceName
                        ]
                    ]
                ]
            ],
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "outputAudioTranscription": [:],
            "inputAudioTranscription": [:]
        ]

        if isManualTurnMode {
            // Tắt hẳn VAD phía server khi dùng chế độ Thủ công (quản lý bằng activityStart / activityEnd)
            setupContent["realtimeInputConfig"] = [
                "automaticActivityDetection": [
                    "disabled": true
                ],
                "activityHandling": "NO_INTERRUPTION",
                "turnCoverage": "TURN_INCLUDES_ALL_INPUT"
            ]
        } else {
            // Cấu hình VAD độ nhạy cân bằng để tránh bắt nhầm tạp âm hoặc tiếng vọng loa
            setupContent["realtimeInputConfig"] = [
                "automaticActivityDetection": [
                    "disabled": false,
                    "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
                    "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
                    "prefixPaddingMs": 120,
                    "silenceDurationMs": 700
                ],
                "activityHandling": "START_OF_ACTIVITY_INTERRUPTS",
                "turnCoverage": "TURN_INCLUDES_AUDIO_ACTIVITY_AND_ALL_VIDEO"
            ]
        }

        let setupDict: [String: Any] = ["setup": setupContent]
        sendJSON(setupDict)
    }

    private func handleServerPayload(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let errorDict = json["error"] as? [String: Any],
           let message = errorDict["message"] as? String {
            delegate?.didEncounterError("Lỗi máy chủ: \(message)")
            return
        }

        if json["setupComplete"] != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isSetupComplete = true
                self.startAudioEngine()
                self.state = self.isMuted ? .muted : .listeningUser
            }
            return
        }

        guard let serverContent = json["serverContent"] as? [String: Any] else { return }

        if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.interruptPlayback()
                self.state = self.isMuted ? .muted : .listeningUser
            }
        }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            currentUserTranscript += text
            let transcript = currentUserTranscript
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didUpdateTranscript(userText: transcript, geminiText: nil)
            }
        }

        if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String, !text.isEmpty {
            currentGeminiTranscript += text
            let transcript = currentGeminiTranscript
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didUpdateTranscript(userText: nil, geminiText: transcript)
            }
        }

        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let textPart = part["text"] as? String, !textPart.isEmpty {
                    currentGeminiTranscript += textPart
                    let transcript = currentGeminiTranscript
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didUpdateTranscript(userText: nil, geminiText: transcript)
                    }
                }

                if let inlineData = part["inlineData"] as? [String: Any],
                   let mimeType = inlineData["mimeType"] as? String,
                   mimeType.contains("audio/pcm"),
                   let base64Audio = inlineData["data"] as? String,
                   let pcmData = Data(base64Encoded: base64Audio) {
                    enqueuePCM24kAudio(pcmData)
                }
            }
        }

        if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
            currentUserTranscript = ""
            currentGeminiTranscript = ""
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isServerTurnComplete = true
                if self.scheduledBuffersCount == 0 && self.state != .muted {
                    self.speechEndCooldownUntil = CACurrentMediaTime() + 0.4
                    self.state = .listeningUser
                }
            }
        }
    }

    private func startAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Bỏ .mixWithOthers để bộ khử tiếng vọng phần cứng (AEC) của mode .voiceChat hoạt động tối đa
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setPreferredSampleRate(16000)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            if audioEngine.isRunning {
                audioEngine.inputNode.removeTap(onBus: 0)
                playerNode.stop()
                audioEngine.stop()
            }
            audioEngine.reset()

            if #available(iOS 13.0, *) {
                if !audioEngine.attachedNodes.contains(playerNode) {
                    audioEngine.attach(playerNode)
                    isPlayerNodeAttached = true
                }
            } else {
                if !isPlayerNodeAttached {
                    audioEngine.attach(playerNode)
                    isPlayerNodeAttached = true
                }
            }
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)

            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            let hwFormat = (inputFormat.sampleRate > 0 && inputFormat.channelCount > 0)
                ? inputFormat
                : inputNode.outputFormat(forBus: 0)

            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
            ), let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
                delegate?.didEncounterError("Không thể khởi tạo bộ chuyển đổi âm thanh 16kHz.")
                return
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { [weak self] buffer, _ in
                self?.processMicrophoneBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }

            audioEngine.prepare()
            try audioEngine.start()
            playerNode.play()
        } catch {
            delegate?.didEncounterError("Lỗi AudioEngine: \(error.localizedDescription)")
        }
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            playerNode.stop()
            audioEngine.stop()
        }
    }

    private func processMicrophoneBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        // Chặn thu âm khi đang tắt mic, đang chờ phản hồi, khi Gemini đang nói, hoặc trong 0.4s vừa dứt tiếng loa
        guard isSetupComplete,
              !isMuted,
              state != .waitingResponse,
              state != .geminiSpeaking,
              CACurrentMediaTime() >= speechEndCooldownUntil else {
            return
        }

        if let channelData = buffer.floatChannelData?[0] {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))
            let normalized = min(max(CGFloat(rms * 6.5), 0.02), 1.0)
            delegate?.didUpdateAudioLevel(normalized)
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = UInt32(Double(buffer.frameLength) * ratio) + 32
        guard let pcm16Buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        converter.reset()
        var error: NSError?
        var hasProvidedData = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasProvidedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedData = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: pcm16Buffer, error: &error, withInputFrom: inputBlock)
        guard error == nil, pcm16Buffer.frameLength > 0,
              let int16Ptr = pcm16Buffer.int16ChannelData?[0] else { return }

        let byteCount = Int(pcm16Buffer.frameLength) * MemoryLayout<Int16>.size
        let pcmData = Data(bytes: int16Ptr, count: byteCount)

        // Nếu ở chế độ Thủ công, gửi tín hiệu activityStart ngay trước gói âm thanh đầu tiên của lượt nói
        if isManualTurnMode && !isManualTurnActive {
            isManualTurnActive = true
            let startPayload: [String: Any] = [
                "realtimeInput": [
                    "activityStart": [:]
                ]
            ]
            sendJSON(startPayload)
        }

        // Chuẩn v1beta: Gửi qua trường "audio" thay vì "mediaChunks"
        let audioPayload: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": pcmData.base64EncodedString()
                ]
            ]
        ]
        sendJSON(audioPayload)
    }

    private func enqueuePCM24kAudio(_ data: Data) {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0,
              let pcmFloatBuffer = AVAudioPCMBuffer(
                  pcmFormat: playbackFormat,
                  frameCapacity: AVAudioFrameCount(sampleCount)
              ),
              let floatChannel = pcmFloatBuffer.floatChannelData?[0] else { return }

        pcmFloatBuffer.frameLength = AVAudioFrameCount(sampleCount)

        var sumSquares: Float = 0
        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<sampleCount {
                let sample = Float(Int16(littleEndian: int16Ptr[i])) / 32768.0
                floatChannel[i] = sample
                sumSquares += sample * sample
            }
        }

        let rms = sqrt(sumSquares / Float(sampleCount))
        let level = min(max(CGFloat(rms * 5.0), 0.05), 1.0)
        delegate?.didUpdateAudioLevel(level)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isServerTurnComplete = false
            if self.state != .geminiSpeaking {
                self.state = .geminiSpeaking
            }
            self.scheduledBuffersCount += 1

            self.playerNode.scheduleBuffer(pcmFloatBuffer) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.scheduledBuffersCount = max(0, self.scheduledBuffersCount - 1)
                    // Chỉ mở lại Mic sau khi Server đã báo turnComplete VÀ toàn bộ buffer âm thanh đã phát xong
                    if self.scheduledBuffersCount == 0 && self.isServerTurnComplete && self.state == .geminiSpeaking {
                        self.speechEndCooldownUntil = CACurrentMediaTime() + 0.4
                        self.state = self.isMuted ? .muted : .listeningUser
                    }
                }
            }

            if !self.playerNode.isPlaying && self.audioEngine.isRunning {
                self.playerNode.play()
            }
        }
    }

    private func interruptPlayback() {
        playerNode.stop()
        if audioEngine.isRunning {
            playerNode.play()
        }
        scheduledBuffersCount = 0
        isServerTurnComplete = true
        speechEndCooldownUntil = CACurrentMediaTime() + 0.2
    }

    private func sendJSON(_ dictionary: [String: Any]) {
        guard let ws = socket, ws.isConnected,
              let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let text = String(data: data, encoding: .utf8) else { return }
        ws.write(string: text)
    }

    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }

        if type == .ended && isSetupComplete {
            try? AVAudioSession.sharedInstance().setActive(true)
            if !audioEngine.isRunning {
                try? audioEngine.start()
                playerNode.play()
            }
        }
    }
}
