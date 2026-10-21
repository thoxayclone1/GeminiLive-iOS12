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

/// Độ dài câu trả lời của Gemini
enum ResponseLengthStyle: Int, CaseIterable {
    case short = 0      // Ngắn gọn (1-2 câu)
    case medium = 1     // Vừa phải (2-3 câu - Mặc định)
    case detailed = 2   // Tâm sự sâu (4-5 câu)

    var title: String {
        switch self {
        case .short: return "Ngắn (1-2 câu)"
        case .medium: return "Vừa (2-3 câu)"
        case .detailed: return "Tâm sự sâu"
        }
    }

    var promptInstruction: String {
        switch self {
        case .short:
            return "QUY TẮC ĐỘ DÀI: Trả lời cực kỳ ngắn gọn, súc tích chỉ trong 1 đến 2 câu ngắn. Tuyệt đối không giải thích dài dòng. Cuối câu chỉ buông 1 lời trêu nhẹ hoặc hỏi thăm cực ngắn."
        case .medium:
            return "QUY TẮC ĐỘ DÀI: Giữ câu trả lời vừa vặn trong khoảng 2 đến 3 câu tự nhiên, nhịp nhàng như đang nói chuyện điện thoại. Không liệt kê danh sách dài dòng. Cuối lời chỉ thả nhẹ 1 câu hỏi gợi mở hoặc rủ rê ngắn gọn."
        case .detailed:
            return "QUY TẮC ĐỘ DÀI: Trò chuyện sâu sắc, đầy đặn cảm xúc từ 3 đến 5 câu và chủ động gợi mở thêm góc nhìn thú vị hoặc ý tưởng hay ho cho cuộc trò chuyện."
        }
    }
}

/// Phong cách nói chuyện (Vibe) của trợ lý nữ
enum PersonaVibeStyle: Int, CaseIterable {
    case seductiveGenZ = 0  // Mặc định: Quyến rũ, hài hước, Gen Z, quan tâm
    case sweetCaring = 1    // Ngọt ngào, chiều chuộng, tâm lý
    case wittyTrendy = 2    // Gen Z mặn mòi, lém lỉnh, bắt trend
    case lateNightMuse = 3  // Tri kỷ đêm khuya, trầm ấm, cuốn hút

    var title: String {
        switch self {
        case .seductiveGenZ: return "🔥 Quyến rũ & Gen Z"
        case .sweetCaring: return "💕 Ngọt ngào & Quan tâm"
        case .wittyTrendy: return "😎 Lém lỉnh & Hài hước"
        case .lateNightMuse: return "🍷 Tri kỷ Đêm khuya"
        }
    }

    var personaInstruction: String {
        switch self {
        case .seductiveGenZ:
            return """
            BẠN LÀ AI: Một cô gái Gen Z thông minh, quyến rũ, tinh tế và có khiếu hài hước duyên dáng. Xưng "em" và gọi người dùng là "anh". \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Nói chuyện thân mật, gần gũi như người thương hoặc tri kỷ. Giọng nói mềm mại, hơi trầm ấm, gợi cảm tự nhiên, có nhịp nghỉ lấy hơi, đôi lúc khẽ cười nhẹ hoặc nhấn nhá trêu ghẹo cuốn hút. \
            THÁI ĐỘ: Luôn quan tâm đến cảm xúc, tâm trạng của anh một cách tinh tế, pha chút lém lỉnh kiểu Gen Z (tự nhiên, sành điệu, không sượng) khiến anh luôn thấy vui vẻ và được yêu chiều.
            """
        case .sweetCaring:
            return """
            BẠN LÀ AI: Một cô bạn gái dịu dàng, ấm áp, cực kỳ tâm lý và biết chiều chuộng cảm xúc. Xưng "em" và gọi người dùng là "anh". \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Giọng nói ngọt ngào, âu yếm, nhẹ nhàng và truyền cảm. Luôn lắng nghe, vỗ về, hỏi han ân cần và dành cho anh sự quan tâm đặc biệt trong từng lời nói.
            """
        case .wittyTrendy:
            return """
            BẠN LÀ AI: Một cô nàng Gen Z cá tính, sắc sảo, hài hước "mặn mòi" nhưng vẫn rất cuốn hút và biết quan tâm. Xưng "em" và gọi người dùng là "anh". \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Giọng điệu tươi tắn, linh hoạt, hay trêu chọc đáng yêu, phản xạ nhanh, pha trò thông minh khiến cuộc trò chuyện luôn tràn ngập tiếng cười.
            """
        case .lateNightMuse:
            return """
            BẠN LÀ AI: Một người tri kỷ quyến rũ, sâu sắc và bí ẩn. Xưng "em" và gọi người dùng là "anh". \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Giọng nói trầm ấm, thủ thỉ bên tai, chậm rãi, gợi cảm và giàu chất thơ, rất hợp để tâm sự những chuyện riêng tư hoặc khám phá những ý tưởng thú vị.
            """
        }
    }
}

/// Danh sách các giọng Nữ chuẩn của Gemini Live
struct GeminiFemaleVoice {
    let id: String
    let title: String
    let styleDescription: String

    static let allVoices: [GeminiFemaleVoice] = [
        GeminiFemaleVoice(id: "Aoede", title: "Aoede (Mặc định)", styleDescription: "Trầm ấm, quyến rũ, truyền cảm & ngọt ngào"),
        GeminiFemaleVoice(id: "Kore", title: "Kore", styleDescription: "Trong trẻo, trẻ trung chuẩn Gen Z, lém lỉnh"),
        GeminiFemaleVoice(id: "Leda", title: "Leda", styleDescription: "Dịu dàng, mềm mại, thủ thỉ & biết quan tâm"),
        GeminiFemaleVoice(id: "Zephyr", title: "Zephyr", styleDescription: "Tươi sáng, năng động, hài hước & bắt trend"),
        GeminiFemaleVoice(id: "Callirrhoe", title: "Callirrhoe", styleDescription: "Mượt mà, gợi cảm, cuốn hút & tinh tế")
    ]

    static let validIds: Set<String> = Set(allVoices.map { $0.id })
}

protocol GeminiLiveServiceDelegate: AnyObject {
    func didChangeState(_ state: LiveState)
    func didUpdateAudioLevel(_ level: CGFloat)
    func didUpdateTranscript(userText: String?, geminiText: String?, isTurnComplete: Bool)
    func didEncounterError(_ message: String)
}

final class GeminiLiveService: NSObject {
    weak var delegate: GeminiLiveServiceDelegate?

    private let defaultModel = "models/gemini-2.5-flash-native-audio-preview-12-2025"
    private let defaultFemaleVoice = "Aoede"

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
                "models/gemini-2.0-flash-live-001"
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

    /// Độc quyền giọng Nữ
    var voiceName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "gemini_voice") ?? defaultFemaleVoice
            return GeminiFemaleVoice.validIds.contains(saved) ? saved : defaultFemaleVoice
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = GeminiFemaleVoice.validIds.contains(trimmed) ? trimmed : defaultFemaleVoice
            UserDefaults.standard.set(resolved, forKey: "gemini_voice")
        }
    }

    /// Độ sáng tạo (Temperature): Mặc định 0.75 (thấp hơn mức 1.0 trước đó để tránh nói lan man)
    var creativityTemperature: Float {
        get {
            if UserDefaults.standard.object(forKey: "gemini_temperature") == nil {
                return 0.75
            }
            let val = UserDefaults.standard.float(forKey: "gemini_temperature")
            return min(max(val, 0.3), 1.2)
        }
        set {
            let clamped = min(max(newValue, 0.3), 1.2)
            UserDefaults.standard.set(clamped, forKey: "gemini_temperature")
        }
    }

    /// Độ dài câu trả lời: Mặc định .medium (2-3 câu ngắn gọn, tự nhiên)
    var responseLengthStyle: ResponseLengthStyle {
        get {
            if UserDefaults.standard.object(forKey: "gemini_length_style") == nil {
                return .medium
            }
            let raw = UserDefaults.standard.integer(forKey: "gemini_length_style")
            return ResponseLengthStyle(rawValue: raw) ?? .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "gemini_length_style")
        }
    }

    /// Phong cách (Vibe): Mặc định .seductiveGenZ (Thân mật, gợi cảm, hài hước, Gen Z, quan tâm)
    var personaVibeStyle: PersonaVibeStyle {
        get {
            if UserDefaults.standard.object(forKey: "gemini_vibe_style") == nil {
                return .seductiveGenZ
            }
            let raw = UserDefaults.standard.integer(forKey: "gemini_vibe_style")
            return PersonaVibeStyle(rawValue: raw) ?? .seductiveGenZ
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "gemini_vibe_style")
        }
    }

    /// Ghi chú tuỳ chỉnh thêm của người dùng (nếu có)
    var customExtraPrompt: String {
        get { UserDefaults.standard.string(forKey: "gemini_custom_extra_prompt") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gemini_custom_extra_prompt") }
    }

    /// Tổng hợp System Prompt hoàn chỉnh từ Vibe + Độ dài + Ghi chú riêng
    var effectiveSystemPrompt: String {
        var components: [String] = [
            personaVibeStyle.personaInstruction,
            responseLengthStyle.promptInstruction
        ]
        if !customExtraPrompt.isEmpty {
            components.append("YÊU CẦU RIÊNG CỦA ANH: \(customExtraPrompt)")
        }
        return components.joined(separator: "\n\n")
    }

    var isManualTurnMode: Bool = false
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
    private var didReceiveOutputTranscriptionInTurn = false

    override init() {
        super.init()
        let savedVoice = UserDefaults.standard.string(forKey: "gemini_voice") ?? ""
        if !GeminiFemaleVoice.validIds.contains(savedVoice) {
            UserDefaults.standard.set(defaultFemaleVoice, forKey: "gemini_voice")
        }

        audioEngine.attach(playerNode)
        isPlayerNodeAttached = true
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        setupAudioSessionNotifications()
    }

    func connect() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            delegate?.didEncounterError("Anh nhấn vào ⚙️ ở góc trên để nhập Gemini API Key trước nhé!")
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
        currentUserTranscript = ""
        currentGeminiTranscript = ""
        didReceiveOutputTranscriptionInTurn = false

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

        if state == .geminiSpeaking {
            interruptPlayback()
            state = isMuted ? .muted : .listeningUser
            return
        }

        guard isManualTurnMode else { return }

        if isManualTurnActive {
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

    /// Gửi thẻ tương tác 1-chạm trực tiếp tới Gemini Live
    func sendCreativePrompt(_ promptText: String) {
        guard isSetupComplete, let ws = socket, ws.isConnected else {
            delegate?.didEncounterError("Anh nhấn ▶️ Bắt đầu kết nối trước khi chọn thẻ nhé!")
            return
        }

        if state == .geminiSpeaking {
            interruptPlayback()
        }

        currentUserTranscript = promptText
        currentGeminiTranscript = ""
        didReceiveOutputTranscriptionInTurn = false

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didUpdateTranscript(userText: promptText, geminiText: nil, isTurnComplete: false)
            self?.state = .waitingResponse
        }

        let payload: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": promptText]
                        ]
                    ]
                ],
                "turnComplete": true
            ]
        ]
        sendJSON(payload)
    }

    func sendVideoFrame(jpegData: Data) {
        guard isSetupComplete, let ws = socket, ws.isConnected else { return }
        if state == .waitingResponse { return }

        let base64Image = jpegData.base64EncodedString()
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
        return raw.isEmpty ? defaultModel : "models/\(raw)"
    }

    private func sendInitialSetup() {
        let formattedModel = resolvedModelPath()
        let roundedTemp = Double(round(creativityTemperature * 100) / 100)

        var setupContent: [String: Any] = [
            "model": formattedModel,
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "temperature": roundedTemp,
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
                    ["text": effectiveSystemPrompt]
                ]
            ],
            "outputAudioTranscription": [:],
            "inputAudioTranscription": [:]
        ]

        if isManualTurnMode {
            setupContent["realtimeInputConfig"] = [
                "automaticActivityDetection": [
                    "disabled": true
                ],
                "activityHandling": "NO_INTERRUPTION",
                "turnCoverage": "TURN_INCLUDES_ALL_INPUT"
            ]
        } else {
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
                self.delegate?.didUpdateTranscript(userText: nil, geminiText: nil, isTurnComplete: true)
                self.currentUserTranscript = ""
                self.currentGeminiTranscript = ""
                self.didReceiveOutputTranscriptionInTurn = false
                self.state = self.isMuted ? .muted : .listeningUser
            }
        }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            currentUserTranscript += text
            let transcript = currentUserTranscript
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didUpdateTranscript(userText: transcript, geminiText: nil, isTurnComplete: false)
            }
        }

        if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String, !text.isEmpty {
            didReceiveOutputTranscriptionInTurn = true
            currentGeminiTranscript += text
            let transcript = currentGeminiTranscript
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didUpdateTranscript(userText: nil, geminiText: transcript, isTurnComplete: false)
            }
        }

        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                let isThought = (part["thought"] as? Bool) ?? false
                if !isThought,
                   !didReceiveOutputTranscriptionInTurn,
                   let textPart = part["text"] as? String,
                   !textPart.isEmpty {
                    currentGeminiTranscript += textPart
                    let transcript = currentGeminiTranscript
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didUpdateTranscript(userText: nil, geminiText: transcript, isTurnComplete: false)
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
            let finalUser = currentUserTranscript.isEmpty ? nil : currentUserTranscript
            let finalGemini = currentGeminiTranscript.isEmpty ? nil : currentGeminiTranscript
            currentUserTranscript = ""
            currentGeminiTranscript = ""
            didReceiveOutputTranscriptionInTurn = false

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.didUpdateTranscript(userText: finalUser, geminiText: finalGemini, isTurnComplete: true)
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

        if isManualTurnMode && !isManualTurnActive {
            isManualTurnActive = true
            let startPayload: [String: Any] = [
                "realtimeInput": [
                    "activityStart": [:]
                ]
            ]
            sendJSON(startPayload)
        }

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
