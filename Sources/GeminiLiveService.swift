import Foundation
import AVFoundation
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

    // Chế độ kết nối tự động thích ứng cho cả khóa AQ. và AIzaSy
    private enum ConnectionRoute: Int {
        case v1BetaStandard = 0       // Cổng v1beta chuẩn (tối ưu cho gemini-2.0-flash-exp)
        case v1BetaEnhanced = 1       // Cổng v1beta kèm cấu hình mở rộng
        case vertexExpressAQ = 2      // Cổng Vertex AI Express dành riêng cho khóa AQ.
    }

    // Cấu hình người dùng
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "gemini_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gemini_api_key") }
    }

    var modelName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "gemini_model") ?? "models/gemini-2.0-flash-exp"
            if saved.isEmpty || saved == "models/gemini-2.0-flash-live-001" {
                return "models/gemini-2.0-flash-exp"
            }
            return saved
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? "models/gemini-2.0-flash-exp" : trimmed, forKey: "gemini_model")
        }
    }

    var voiceName: String {
        get { UserDefaults.standard.string(forKey: "gemini_voice") ?? "Aoede" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gemini_voice") }
    }

    var systemPrompt: String {
        get {
            UserDefaults.standard.string(forKey: "gemini_sys_prompt")
            ?? "Bạn là trợ lý AI thông minh, trả lời ngắn gọn, tự nhiên bằng tiếng Việt."
        }
        set { UserDefaults.standard.set(newValue, forKey: "gemini_sys_prompt") }
    }

    // true = Thủ công (Tap-to-Finish), false = Tự động (Auto VAD)
    var isManualTurnMode: Bool = true
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
    private var activeRoute: ConnectionRoute = .v1BetaStandard
    private var isUserInitiatedDisconnect = false

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24000,
        channels: 1,
        interleaved: false
    )!

    private var isSetupComplete = false
    private var isManualTurnActive = false
    private var scheduledBuffersCount = 0
    private var currentUserTranscript = ""
    private var currentGeminiTranscript = ""

    override init() {
        super.init()
        // Tự động chuyển model mặc định cũ sang models/gemini-2.0-flash-exp
        if UserDefaults.standard.string(forKey: "gemini_model") == "models/gemini-2.0-flash-live-001" {
            UserDefaults.standard.set("models/gemini-2.0-flash-exp", forKey: "gemini_model")
        }
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        setupAudioSessionNotifications()
    }

    // MARK: - Kết nối & Tự động tương thích khóa AQ. trên v1beta

    func connect() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            delegate?.didEncounterError("Vui lòng nhấn vào ⚙️ Cài đặt để nhập Gemini API Key.")
            return
        }

        activeRoute = .v1BetaStandard
        openWebSocketConnection(withKey: trimmedKey, route: activeRoute)
    }

    private func openWebSocketConnection(withKey key: String, route: ConnectionRoute) {
        isUserInitiatedDisconnect = true
        socket?.disconnect()
        socket = nil
        stopAudioEngine()

        isUserInitiatedDisconnect = false
        state = .connecting
        isSetupComplete = false
        isManualTurnActive = false

        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let urlString: String

        switch route {
        case .v1BetaStandard, .v1BetaEnhanced:
            urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(encodedKey)"
        case .vertexExpressAQ:
            urlString = "wss://aiplatform.googleapis.com/ws/google.cloud.aiplatform.v1beta1.LlmBidiService/BidiGenerateContent?key=\(encodedKey)"
        }

        guard let url = URL(string: urlString) else {
            delegate?.didEncounterError("URL kết nối không hợp lệ.")
            state = .disconnected
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Đính kèm khóa vào Header để tương thích với cả khóa AQ. và AIzaSy trên cổng v1beta
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let ws = WebSocket(request: request)
        ws.onConnect = { [weak self] in
            self?.sendInitialSetup(for: route)
        }
        ws.onDisconnect = { [weak self] error in
            guard let self = self else { return }
            self.stopAudioEngine()

            // Nếu người dùng chủ động bấm Dừng thì không chạy fallback
            if self.isUserInitiatedDisconnect {
                self.state = .disconnected
                return
            }

            // Nếu bị ngắt ngay trước khi hoàn tất Setup -> Tự động thử phương án dự phòng cho khóa AQ. / v1beta
            if !self.isSetupComplete {
                if self.tryNextFallbackRoute(withKey: key) {
                    return
                }
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

    private func tryNextFallbackRoute(withKey key: String) -> Bool {
        let isAQKey = key.hasPrefix("AQ.")
        switch activeRoute {
        case .v1BetaStandard:
            if isAQKey {
                activeRoute = .vertexExpressAQ
                openWebSocketConnection(withKey: key, route: .vertexExpressAQ)
                return true
            } else {
                activeRoute = .v1BetaEnhanced
                openWebSocketConnection(withKey: key, route: .v1BetaEnhanced)
                return true
            }
        case .vertexExpressAQ:
            activeRoute = .v1BetaEnhanced
            openWebSocketConnection(withKey: key, route: .v1BetaEnhanced)
            return true
        case .v1BetaEnhanced:
            return false
        }
    }

    func disconnect() {
        isUserInitiatedDisconnect = true
        socket?.disconnect()
        socket = nil
        stopAudioEngine()
        isSetupComplete = false
        isManualTurnActive = false
        state = .disconnected
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
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

    // MARK: - Thao tác Tap-to-Finish (Chế độ Thủ công)

    func finishUserTurnManually() {
        guard isSetupComplete, let ws = socket, ws.isConnected else { return }

        if state == .geminiSpeaking {
            interruptPlayback()
            state = .listeningUser
            return
        }

        guard isManualTurnMode else { return }

        if isManualTurnActive {
            if activeRoute == .v1BetaEnhanced {
                let payload: [String: Any] = [
                    "realtimeInput": [
                        "activityEnd": [String: Any]()
                    ]
                ]
                sendJSON(payload)
            } else {
                // Tín hiệu kết thúc lượt nói tương thích 100% với mọi nhánh v1beta
                let payload: [String: Any] = [
                    "clientContent": [
                        "turnComplete": true
                    ]
                ]
                sendJSON(payload)
            }
            isManualTurnActive = false
            state = .waitingResponse
        }
    }

    // MARK: - Gửi Khung hình Camera (Vision Live)

    func sendVideoFrame(jpegData: Data) {
        guard isSetupComplete, let ws = socket, ws.isConnected else { return }
        let base64Image = jpegData.base64EncodedString()
        let payload: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "image/jpeg",
                        "data": base64Image
                    ]
                ]
            ]
        ]
        sendJSON(payload)
    }

    // MARK: - Cấu hình Gói Tin Setup Ban Đầu (Chuẩn v1beta)

    private func resolvedModelPath(for route: ConnectionRoute) -> String {
        let raw = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName: String
        if raw.hasPrefix("publishers/google/models/") {
            cleanName = String(raw.dropFirst("publishers/google/models/".count))
        } else if raw.hasPrefix("models/") {
            cleanName = String(raw.dropFirst("models/".count))
        } else {
            cleanName = raw.isEmpty ? "gemini-2.0-flash-exp" : raw
        }

        switch route {
        case .v1BetaStandard, .v1BetaEnhanced:
            return "models/\(cleanName)"
        case .vertexExpressAQ:
            return "publishers/google/models/\(cleanName)"
        }
    }

    private func sendInitialSetup(for route: ConnectionRoute) {
        let formattedModel = resolvedModelPath(for: route)

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
            ]
        ]

        // Chỉ đính kèm các cờ mở rộng ở nhánh Enhanced để tránh lỗi 1007 (WSError error 1) trên v1beta chuẩn
        if route == .v1BetaEnhanced {
            setupContent["realtimeInputConfig"] = [
                "automaticActivityDetection": [
                    "disabled": isManualTurnMode
                ]
            ]
            setupContent["inputAudioTranscription"] = [String: Any]()
            setupContent["outputAudioTranscription"] = [String: Any]()
        }

        let setupDict: [String: Any] = ["setup": setupContent]
        sendJSON(setupDict)
    }

    // MARK: - Xử lý Phản hồi từ Máy chủ Gemini

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
            isSetupComplete = true
            startAudioEngine()
            state = isMuted ? .muted : .listeningUser
            return
        }

        guard let serverContent = json["serverContent"] as? [String: Any] else { return }

        if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
            interruptPlayback()
            state = isMuted ? .muted : .listeningUser
        }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            currentUserTranscript += text
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.didUpdateTranscript(userText: self.currentUserTranscript, geminiText: nil)
            }
        }

        if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String, !text.isEmpty {
            currentGeminiTranscript += text
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.didUpdateTranscript(userText: nil, geminiText: self.currentGeminiTranscript)
            }
        }

        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let textPart = part["text"] as? String, !textPart.isEmpty {
                    currentGeminiTranscript += textPart
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.didUpdateTranscript(userText: nil, geminiText: self.currentGeminiTranscript)
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
            if scheduledBuffersCount == 0 && state != .muted {
                state = .listeningUser
            }
        }
    }

    // MARK: - Âm thanh Hai chiều & Chạy nền (AVAudioEngine)

    private func startAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            if audioEngine.isRunning {
                audioEngine.stop()
            }
            audioEngine.reset()

            if !audioEngine.attachedNodes.contains(playerNode) {
                audioEngine.attach(playerNode)
            }
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)

            let inputNode = audioEngine.inputNode
            let hwFormat = inputNode.outputFormat(forBus: 0)

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
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
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
        if state == .listeningUser, let channelData = buffer.floatChannelData?[0] {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))
            let normalized = min(max(CGFloat(rms * 6.5), 0.02), 1.0)
            delegate?.didUpdateAudioLevel(normalized)
        }

        guard isSetupComplete, !isMuted, state != .waitingResponse else { return }

        if isManualTurnMode && state == .geminiSpeaking { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = UInt32(Double(buffer.frameLength) * ratio) + 32
        guard let pcm16Buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

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

        if isManualTurnMode && !isManualTurnActive {
            isManualTurnActive = true
            if activeRoute == .v1BetaEnhanced {
                let startPayload: [String: Any] = [
                    "realtimeInput": [
                        "activityStart": [String: Any]()
                    ]
                ]
                sendJSON(startPayload)
            }
        }

        let audioPayload: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=16000",
                        "data": pcmData.base64EncodedString()
                    ]
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

        if state != .geminiSpeaking {
            state = .geminiSpeaking
        }

        scheduledBuffersCount += 1
        playerNode.scheduleBuffer(pcmFloatBuffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.scheduledBuffersCount = max(0, self.scheduledBuffersCount - 1)
                if self.scheduledBuffersCount == 0 && self.state == .geminiSpeaking {
                    self.state = self.isMuted ? .muted : .listeningUser
                }
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func interruptPlayback() {
        playerNode.stop()
        playerNode.play()
        scheduledBuffersCount = 0
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
