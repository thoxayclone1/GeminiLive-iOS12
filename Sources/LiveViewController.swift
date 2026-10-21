import UIKit
import AVFoundation

final class LiveViewController: UIViewController {
    private let liveService = GeminiLiveService()

    // MARK: - Camera (Vision Live)
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "com.geminilive.camera")
    private let ciContext = CIContext(options: nil)
    private var isCameraEnabled = false
    private var isUsingFrontCamera = false
    private var lastFrameSentTime: TimeInterval = 0

    // MARK: - Hiệu ứng Quả cầu 60 FPS (CoreAnimation)
    private let orbContainer = UIView()
    private let outerGlowLayer = CAGradientLayer()
    private let middleOrbLayer = CAGradientLayer()
    private let innerCoreLayer = CAGradientLayer()
    private let orbHintLabel = UILabel()
    private var displayLink: CADisplayLink?
    private var currentAudioLevel: CGFloat = 0.05
    private var targetAudioLevel: CGFloat = 0.05
    private var phase: CGFloat = 0

    // MARK: - Các lớp phủ giao diện trên cùng
    private let topVignette = CAGradientLayer()
    private let bottomVignette = CAGradientLayer()
    private let statusBadge = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let flipCamButton = UIButton(type: .system)

    // MARK: - Thanh Gợi Ý Sáng Tạo (Creative Suggestion Chips)
    private let suggestionScrollView = UIScrollView()
    private let suggestionStackView = UIStackView()
    private let creativePrompts: [(title: String, prompt: String)] = [
        ("✨ Ý tưởng mới", "Hãy gợi ý cho tôi 3 ý tưởng thật độc đáo, sáng tạo và khác biệt về một chủ đề thú vị hôm nay, kèm cách thực hiện cụ thể."),
        ("🎨 Brainstorm", "Đóng vai một giám đốc sáng tạo, hãy cùng tôi brainstorm các giải pháp đột phá và đặt cho tôi 3 câu hỏi khơi gợi tư duy."),
        ("📖 Kể chuyện", "Hãy sáng tác một câu chuyện ngắn thật cuốn hút, giàu hình ảnh và cảm xúc, sau đó cho tôi 2 lựa chọn để quyết định diễn biến tiếp theo."),
        ("🔮 Góc nhìn đa chiều", "Hãy chọn một nghịch lý hoặc xu hướng thú vị trong cuộc sống và phân tích dưới 3 góc nhìn hoàn toàn bất ngờ."),
        ("📷 Cảm hứng từ Camera", "Hãy quan sát hình ảnh từ camera của tôi và đưa ra nhận xét thật tinh tế, kèm theo những gợi ý sáng tạo liên quan đến những gì bạn thấy.")
    ]

    // MARK: - Khung Live Lyric Đa Năng (Cuộn tự động + Phóng to/Thu gọn)
    private let subtitleContainer = UIView()
    private let lyricHeaderBar = UIView()
    private let lyricTitleLabel = UILabel()
    private let expandLyricButton = UIButton(type: .system)
    private let copyLyricButton = UIButton(type: .system)
    private let clearLyricButton = UIButton(type: .system)
    private let toggleSubButton = UIButton(type: .system)
    private let lyricTextView = UITextView()

    private var subtitleHeightConstraint: NSLayoutConstraint?
    private var isSubtitleHidden = false
    private var isLyricExpanded = false

    // Lưu lịch sử hội thoại để hiển thị đầy đủ trên khung Lyric
    private var conversationHistory: [(speaker: String, text: String, isGemini: Bool)] = []
    private var activeUserStreamingText: String = ""
    private var activeGeminiStreamingText: String = ""

    // MARK: - Thanh con nhộng điều khiển (Floating Pill Bar)
    private let pillBar = UIView()
    private let micButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let camButton = UIButton(type: .system)
    private let powerButton = UIButton(type: .system)

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        liveService.delegate = self
        setupBackgroundAndVignettes()
        setupOrbView()
        setupTopBar()
        setupSubtitleBox()
        setupCreativeSuggestionsBar()
        setupFloatingPillBar()
        setupLifecycleObservers()
        startDisplayLink()
        updateUIForState(.disconnected)
        renderLyricContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        topVignette.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height * 0.18)
        bottomVignette.frame = CGRect(
            x: 0,
            y: view.bounds.height * 0.50,
            width: view.bounds.width,
            height: view.bounds.height * 0.50
        )
        layoutOrbLayers()
    }

    // MARK: - Dựng Giao Diện

    private func setupBackgroundAndVignettes() {
        view.backgroundColor = UIColor(red: 6/255, green: 6/255, blue: 14/255, alpha: 1.0)

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.isHidden = true
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        topVignette.colors = [
            UIColor.black.withAlphaComponent(0.75).cgColor,
            UIColor.clear.cgColor
        ]
        bottomVignette.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.92).cgColor
        ]
        view.layer.addSublayer(topVignette)
        view.layer.addSublayer(bottomVignette)
    }

    private func setupOrbView() {
        orbContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(orbContainer)

        NSLayoutConstraint.activate([
            orbContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            orbContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -95),
            orbContainer.widthAnchor.constraint(equalToConstant: 220),
            orbContainer.heightAnchor.constraint(equalToConstant: 220)
        ])

        let geminiBlue = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0).cgColor
        let geminiPurple = UIColor(red: 0.61, green: 0.45, blue: 0.80, alpha: 1.0).cgColor
        let geminiCoral = UIColor(red: 0.85, green: 0.40, blue: 0.44, alpha: 1.0).cgColor

        outerGlowLayer.colors = [geminiBlue, geminiPurple, geminiCoral]
        outerGlowLayer.startPoint = CGPoint(x: 0, y: 0)
        outerGlowLayer.endPoint = CGPoint(x: 1, y: 1)
        outerGlowLayer.opacity = 0.35

        middleOrbLayer.colors = [geminiPurple, geminiCoral, geminiBlue]
        middleOrbLayer.startPoint = CGPoint(x: 1, y: 0)
        middleOrbLayer.endPoint = CGPoint(x: 0, y: 1)
        middleOrbLayer.opacity = 0.65

        innerCoreLayer.colors = [geminiBlue, geminiPurple, geminiCoral]
        innerCoreLayer.startPoint = CGPoint(x: 0, y: 0.5)
        innerCoreLayer.endPoint = CGPoint(x: 1, y: 0.5)
        innerCoreLayer.opacity = 0.95

        orbContainer.layer.addSublayer(outerGlowLayer)
        orbContainer.layer.addSublayer(middleOrbLayer)
        orbContainer.layer.addSublayer(innerCoreLayer)

        orbHintLabel.translatesAutoresizingMaskIntoConstraints = false
        orbHintLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        orbHintLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        orbHintLabel.textAlignment = .center
        orbHintLabel.numberOfLines = 2
        orbContainer.addSubview(orbHintLabel)

        NSLayoutConstraint.activate([
            orbHintLabel.centerXAnchor.constraint(equalTo: orbContainer.centerXAnchor),
            orbHintLabel.centerYAnchor.constraint(equalTo: orbContainer.centerYAnchor),
            orbHintLabel.widthAnchor.constraint(equalToConstant: 155)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleOrbTap))
        orbContainer.addGestureRecognizer(tapGesture)
    }

    private func layoutOrbLayers() {
        let bounds = orbContainer.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let outerSize: CGFloat = 205
        outerGlowLayer.bounds = CGRect(x: 0, y: 0, width: outerSize, height: outerSize)
        outerGlowLayer.position = center
        outerGlowLayer.cornerRadius = outerSize / 2

        let midSize: CGFloat = 162
        middleOrbLayer.bounds = CGRect(x: 0, y: 0, width: midSize, height: midSize)
        middleOrbLayer.position = center
        middleOrbLayer.cornerRadius = midSize / 2

        let coreSize: CGFloat = 124
        innerCoreLayer.bounds = CGRect(x: 0, y: 0, width: coreSize, height: coreSize)
        innerCoreLayer.position = center
        innerCoreLayer.cornerRadius = coreSize / 2
    }

    private func setupTopBar() {
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        statusBadge.layer.cornerRadius = 15
        statusBadge.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        statusBadge.setTitleColor(.white, for: .normal)
        statusBadge.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        statusBadge.isUserInteractionEnabled = false
        view.addSubview(statusBadge)

        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.setTitle("⚙️", for: .normal)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        settingsButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        settingsButton.layer.cornerRadius = 15
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        view.addSubview(settingsButton)

        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        voiceButton.setTitle("👩 \(liveService.voiceName)", for: .normal)
        voiceButton.setTitleColor(.white, for: .normal)
        voiceButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        voiceButton.backgroundColor = UIColor(red: 0.61, green: 0.45, blue: 0.80, alpha: 0.35)
        voiceButton.layer.cornerRadius = 15
        voiceButton.layer.borderWidth = 1
        voiceButton.layer.borderColor = UIColor(red: 0.85, green: 0.40, blue: 0.44, alpha: 0.5).cgColor
        voiceButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        voiceButton.addTarget(self, action: #selector(openFemaleVoicePicker), for: .touchUpInside)
        view.addSubview(voiceButton)

        flipCamButton.translatesAutoresizingMaskIntoConstraints = false
        flipCamButton.setTitle("🔄", for: .normal)
        flipCamButton.setTitleColor(.white, for: .normal)
        flipCamButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        flipCamButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        flipCamButton.layer.cornerRadius = 15
        flipCamButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        flipCamButton.isHidden = true
        flipCamButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        view.addSubview(flipCamButton)

        let topAnchor = view.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            statusBadge.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            statusBadge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            settingsButton.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            voiceButton.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
            voiceButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -8),

            flipCamButton.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
            flipCamButton.trailingAnchor.constraint(equalTo: voiceButton.leadingAnchor, constant: -8)
        ])
    }

    // MARK: - Khung Live Lyric Mới (Hiển thị nhiều dòng, tự cuộn, phóng to/thu nhỏ)

    private func setupSubtitleBox() {
        subtitleContainer.translatesAutoresizingMaskIntoConstraints = false
        subtitleContainer.backgroundColor = UIColor(red: 12/255, green: 14/255, blue: 24/255, alpha: 0.88)
        subtitleContainer.layer.cornerRadius = 18
        subtitleContainer.layer.borderWidth = 1
        subtitleContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        subtitleContainer.clipsToBounds = true
        view.addSubview(subtitleContainer)

        lyricHeaderBar.translatesAutoresizingMaskIntoConstraints = false
        lyricHeaderBar.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        subtitleContainer.addSubview(lyricHeaderBar)

        lyricTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        lyricTitleLabel.text = "🎵 Live Lyric & Gợi ý"
        lyricTitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        lyricTitleLabel.textColor = UIColor(red: 0.75, green: 0.82, blue: 1.0, alpha: 1.0)
        lyricHeaderBar.addSubview(lyricTitleLabel)

        configureHeaderActionButton(expandLyricButton, title: "🔍 Mở rộng", action: #selector(toggleLyricExpand))
        configureHeaderActionButton(copyLyricButton, title: "📋 Chép", action: #selector(copyLyricText))
        configureHeaderActionButton(clearLyricButton, title: "🗑️ Xóa", action: #selector(clearLyricHistory))

        let headerButtonsStack = UIStackView(arrangedSubviews: [clearLyricButton, copyLyricButton, expandLyricButton])
        headerButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        headerButtonsStack.axis = .horizontal
        headerButtonsStack.spacing = 6
        lyricHeaderBar.addSubview(headerButtonsStack)

        lyricTextView.translatesAutoresizingMaskIntoConstraints = false
        lyricTextView.backgroundColor = .clear
        lyricTextView.isEditable = false
        lyricTextView.isSelectable = true
        lyricTextView.showsVerticalScrollIndicator = true
        lyricTextView.indicatorStyle = .white
        lyricTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 12, right: 10)
        subtitleContainer.addSubview(lyricTextView)

        toggleSubButton.translatesAutoresizingMaskIntoConstraints = false
        toggleSubButton.setTitle("👁️ Ẩn khung chữ", for: .normal)
        toggleSubButton.setTitleColor(UIColor(white: 0.75, alpha: 1.0), for: .normal)
        toggleSubButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        toggleSubButton.addTarget(self, action: #selector(toggleSubtitleBox), for: .touchUpInside)
        view.addSubview(toggleSubButton)

        let heightConstraint = subtitleContainer.heightAnchor.constraint(equalToConstant: 175)
        self.subtitleHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            subtitleContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            subtitleContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            subtitleContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -88),
            heightConstraint,

            lyricHeaderBar.topAnchor.constraint(equalTo: subtitleContainer.topAnchor),
            lyricHeaderBar.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor),
            lyricHeaderBar.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor),
            lyricHeaderBar.heightAnchor.constraint(equalToConstant: 32),

            lyricTitleLabel.leadingAnchor.constraint(equalTo: lyricHeaderBar.leadingAnchor, constant: 12),
            lyricTitleLabel.centerYAnchor.constraint(equalTo: lyricHeaderBar.centerYAnchor),

            headerButtonsStack.trailingAnchor.constraint(equalTo: lyricHeaderBar.trailingAnchor, constant: -10),
            headerButtonsStack.centerYAnchor.constraint(equalTo: lyricHeaderBar.centerYAnchor),

            lyricTextView.topAnchor.constraint(equalTo: lyricHeaderBar.bottomAnchor),
            lyricTextView.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor),
            lyricTextView.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor),
            lyricTextView.bottomAnchor.constraint(equalTo: subtitleContainer.bottomAnchor),

            toggleSubButton.bottomAnchor.constraint(equalTo: subtitleContainer.topAnchor, constant: -42),
            toggleSubButton.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor, constant: -2)
        ])
    }

    private func configureHeaderActionButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(UIColor(white: 0.9, alpha: 1.0), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    // MARK: - Thanh Gợi Ý Sáng Tạo 1-Chạm (Creative Suggestion Chips)

    private func setupCreativeSuggestionsBar() {
        suggestionScrollView.translatesAutoresizingMaskIntoConstraints = false
        suggestionScrollView.showsHorizontalScrollIndicator = false
        view.addSubview(suggestionScrollView)

        suggestionStackView.translatesAutoresizingMaskIntoConstraints = false
        suggestionStackView.axis = .horizontal
        suggestionStackView.spacing = 8
        suggestionScrollView.addSubview(suggestionStackView)

        for (index, item) in creativePrompts.enumerated() {
            let chip = UIButton(type: .system)
            chip.tag = index
            chip.setTitle(item.title, for: .normal)
            chip.setTitleColor(.white, for: .normal)
            chip.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            chip.backgroundColor = UIColor(red: 0.28, green: 0.32, blue: 0.58, alpha: 0.55)
            chip.layer.cornerRadius = 15
            chip.layer.borderWidth = 1
            chip.layer.borderColor = UIColor(red: 0.61, green: 0.45, blue: 0.80, alpha: 0.5).cgColor
            chip.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            chip.addTarget(self, action: #selector(handleCreativeChipTap(_:)), for: .touchUpInside)
            suggestionStackView.addArrangedSubview(chip)
        }

        NSLayoutConstraint.activate([
            suggestionScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            suggestionScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            suggestionScrollView.bottomAnchor.constraint(equalTo: subtitleContainer.topAnchor, constant: -6),
            suggestionScrollView.heightAnchor.constraint(equalToConstant: 32),

            suggestionStackView.topAnchor.constraint(equalTo: suggestionScrollView.topAnchor),
            suggestionStackView.bottomAnchor.constraint(equalTo: suggestionScrollView.bottomAnchor),
            suggestionStackView.leadingAnchor.constraint(equalTo: suggestionScrollView.leadingAnchor),
            suggestionStackView.trailingAnchor.constraint(equalTo: suggestionScrollView.trailingAnchor),
            suggestionStackView.heightAnchor.constraint(equalTo: suggestionScrollView.heightAnchor)
        ])
    }

    private func setupFloatingPillBar() {
        pillBar.translatesAutoresizingMaskIntoConstraints = false
        pillBar.backgroundColor = UIColor(red: 20/255, green: 22/255, blue: 34/255, alpha: 0.95)
        pillBar.layer.cornerRadius = 32
        pillBar.layer.borderWidth = 1
        pillBar.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        view.addSubview(pillBar)

        let initialModeTitle = liveService.isManualTurnMode ? "✋ Thủ công" : "⚡ Tự động"
        configurePillButton(micButton, title: "🎙️ Mic", action: #selector(handleMicTap))
        configurePillButton(modeButton, title: initialModeTitle, action: #selector(handleModeTap))
        configurePillButton(camButton, title: "📷 Cam", action: #selector(handleCamTap))
        configurePillButton(powerButton, title: "▶️ Bắt đầu", action: #selector(handlePowerTap))
        powerButton.backgroundColor = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0)

        let stack = UIStackView(arrangedSubviews: [micButton, modeButton, camButton, powerButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        pillBar.addSubview(stack)

        NSLayoutConstraint.activate([
            pillBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pillBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            pillBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            pillBar.heightAnchor.constraint(equalToConstant: 64),

            stack.topAnchor.constraint(equalTo: pillBar.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: pillBar.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: pillBar.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: pillBar.trailingAnchor, constant: -10)
        ])
    }

    private func configurePillButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        button.layer.cornerRadius = 24
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    // MARK: - Hiển thị & Tự động cuộn Live Lyric

    private func renderLyricContent() {
        let attributed = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        paragraphStyle.paragraphSpacing = 10

        let userHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: UIColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        let userBodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: UIColor(white: 0.85, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        let geminiHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: UIColor(red: 0.95, green: 0.58, blue: 0.72, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        let geminiHistoryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: UIColor(white: 0.92, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        let geminiLiveActiveAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]

        if conversationHistory.isEmpty && activeUserStreamingText.isEmpty && activeGeminiStreamingText.isEmpty {
            let welcome = NSAttributedString(
                string: "✨ Chào bạn! Mình là Gemini (Giọng nữ \(liveService.voiceName)).\nHãy nhấn ▶️ Bắt đầu để trò chuyện hoặc chạm vào các thẻ Gợi ý sáng tạo phía trên nhé!",
                attributes: geminiHistoryAttributes
            )
            attributed.append(welcome)
        } else {
            // Hiển thị các lượt hội thoại trước đó
            for item in conversationHistory.suffix(12) {
                let header = item.isGemini ? "👩 Gemini (\(liveService.voiceName)): " : "🗣️ Bạn: "
                let headerAttr = item.isGemini ? geminiHeaderAttributes : userHeaderAttributes
                let bodyAttr = item.isGemini ? geminiHistoryAttributes : userBodyAttributes

                attributed.append(NSAttributedString(string: header, attributes: headerAttr))
                attributed.append(NSAttributedString(string: "\(item.text)\n", attributes: bodyAttr))
            }

            // Hiển thị câu đang nói trực tiếp (Live Streaming Lyric)
            if !activeUserStreamingText.isEmpty {
                attributed.append(NSAttributedString(string: "🗣️ Bạn (đang nói): ", attributes: userHeaderAttributes))
                attributed.append(NSAttributedString(string: "\(activeUserStreamingText)\n", attributes: userBodyAttributes))
            }

            if !activeGeminiStreamingText.isEmpty {
                attributed.append(NSAttributedString(string: "👩 Gemini (đang trả lời): ", attributes: geminiHeaderAttributes))
                attributed.append(NSAttributedString(string: "\(activeGeminiStreamingText)\n", attributes: geminiLiveActiveAttributes))
            }
        }

        lyricTextView.attributedText = attributed
        scrollToBottomOfLyric()
    }

    private func scrollToBottomOfLyric() {
        let length = lyricTextView.attributedText.length
        guard length > 0 else { return }
        let bottomRange = NSRange(location: max(0, length - 1), length: 1)
        lyricTextView.scrollRangeToVisible(bottomRange)
    }

    // MARK: - Vòng lặp Chuyển động 60 FPS (CADisplayLink)

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(renderOrbFrame))
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    @objc private func renderOrbFrame() {
        phase += 0.035
        currentAudioLevel += (targetAudioLevel - currentAudioLevel) * 0.22
        targetAudioLevel = max(0.03, targetAudioLevel * 0.92)

        let breath = sin(phase) * 0.04
        let scaleCore = 1.0 + currentAudioLevel * 0.35 + breath
        let scaleMid = 1.0 + currentAudioLevel * 0.55 - breath * 0.5
        let scaleOuter = 1.0 + currentAudioLevel * 0.85 + sin(phase * 0.7) * 0.06

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        innerCoreLayer.transform = CATransform3DMakeScale(scaleCore, scaleCore, 1)
        middleOrbLayer.transform = CATransform3DRotateAndScale(angle: phase * 0.4, scale: scaleMid)
        outerGlowLayer.transform = CATransform3DRotateAndScale(angle: -phase * 0.25, scale: scaleOuter)
        CATransaction.commit()
    }

    // MARK: - Xử lý Nút bấm & Tương tác

    @objc private func handleOrbTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if liveService.state == .disconnected {
            liveService.connect()
        } else {
            liveService.finishUserTurnManually()
        }
    }

    @objc private func handleCreativeChipTap(_ sender: UIButton) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let index = sender.tag
        guard index >= 0 && index < creativePrompts.count else { return }
        let selected = creativePrompts[index]
        liveService.sendCreativePrompt(selected.prompt)
    }

    @objc private func toggleLyricExpand() {
        isLyricExpanded.toggle()
        let targetHeight: CGFloat = isLyricExpanded ? 330 : 175
        subtitleHeightConstraint?.constant = targetHeight
        expandLyricButton.setTitle(isLyricExpanded ? "🔽 Thu gọn" : "🔍 Mở rộng", for: .normal)

        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
        scrollToBottomOfLyric()
    }

    @objc private func copyLyricText() {
        UIPasteboard.general.string = lyricTextView.text
        copyLyricButton.setTitle("✅ Đã chép", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyLyricButton.setTitle("📋 Chép", for: .normal)
        }
    }

    @objc private func clearLyricHistory() {
        conversationHistory.removeAll()
        activeUserStreamingText = ""
        activeGeminiStreamingText = ""
        renderLyricContent()
    }

    @objc private func openFemaleVoicePicker() {
        let sheet = UIAlertController(
            title: "👩 Chọn Giọng Nữ Gemini",
            message: "Tất cả giọng đọc đều là giọng nữ tự nhiên, truyền cảm và giàu cảm xúc.",
            preferredStyle: .actionSheet
        )

        for voice in GeminiFemaleVoice.allVoices {
            let isCurrent = (voice.id == liveService.voiceName)
            let prefix = isCurrent ? "✓ " : ""
            let actionTitle = "\(prefix)\(voice.title) — \(voice.styleDescription)"
            sheet.addAction(UIAlertAction(title: actionTitle, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.liveService.voiceName = voice.id
                self.voiceButton.setTitle("👩 \(voice.id)", for: .normal)
                self.renderLyricContent()
                if self.liveService.state != .disconnected {
                    self.liveService.connect()
                }
            })
        }

        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = voiceButton
            popover.sourceRect = voiceButton.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func handleMicTap() {
        liveService.toggleMute()
        micButton.setTitle(liveService.isMuted ? "🔇 Tắt" : "🎙️ Mic", for: .normal)
        micButton.backgroundColor = liveService.isMuted
            ? UIColor.systemRed.withAlphaComponent(0.7)
            : UIColor.white.withAlphaComponent(0.1)
    }

    @objc private func handleModeTap() {
        liveService.toggleTurnMode()
        let isManual = liveService.isManualTurnMode
        modeButton.setTitle(isManual ? "✋ Thủ công" : "⚡ Tự động", for: .normal)
        updateUIForState(liveService.state)
    }

    @objc private func handleCamTap() {
        isCameraEnabled.toggle()
        if isCameraEnabled {
            startCamera()
            previewLayer?.isHidden = false
            flipCamButton.isHidden = false
            camButton.backgroundColor = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 0.75)
        } else {
            stopCamera()
            previewLayer?.isHidden = true
            flipCamButton.isHidden = true
            camButton.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        }
    }

    @objc private func flipCamera() {
        isUsingFrontCamera.toggle()
        if isCameraEnabled {
            startCamera()
        }
    }

    @objc private func handlePowerTap() {
        if liveService.state == .disconnected {
            liveService.connect()
        } else {
            liveService.disconnect()
        }
    }

    @objc private func toggleSubtitleBox() {
        isSubtitleHidden.toggle()
        subtitleContainer.isHidden = isSubtitleHidden
        suggestionScrollView.isHidden = isSubtitleHidden
        toggleSubButton.setTitle(isSubtitleHidden ? "👁️ Hiện khung chữ" : "👁️ Ẩn khung chữ", for: .normal)
    }

    @objc private func openSettings() {
        let alert = UIAlertController(
            title: "Cài đặt Gemini Live (Giọng Nữ & Sáng Tạo)",
            message: "Tùy chỉnh API Key, Model, Giọng Nữ (Aoede/Kore/Leda/Zephyr/Callirrhoe) và Phong cách sáng tạo.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "API Key (AQ... hoặc AIzaSy...)"
            tf.text = self.liveService.apiKey
            tf.clearButtonMode = .whileEditing
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        alert.addTextField { tf in
            tf.placeholder = "Model (models/gemini-2.5-flash-native-audio-preview-12-2025)"
            tf.text = self.liveService.modelName
            tf.clearButtonMode = .whileEditing
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        alert.addTextField { tf in
            tf.placeholder = "Giọng Nữ: Aoede / Kore / Leda / Zephyr / Callirrhoe"
            tf.text = self.liveService.voiceName
            tf.clearButtonMode = .whileEditing
            tf.autocorrectionType = .no
        }
        alert.addTextField { tf in
            tf.placeholder = "System Prompt (Khơi gợi sáng tạo & gợi ý)"
            tf.text = self.liveService.systemPrompt
            tf.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu & Kết nối", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.liveService.apiKey = alert.textFields?[0].text ?? ""

            let model = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.liveService.modelName = model.isEmpty ? "models/gemini-2.5-flash-native-audio-preview-12-2025" : model

            let voice = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !voice.isEmpty {
                self.liveService.voiceName = voice
                self.voiceButton.setTitle("👩 \(self.liveService.voiceName)", for: .normal)
            }

            let prompt = alert.textFields?[3].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !prompt.isEmpty { self.liveService.systemPrompt = prompt }

            self.liveService.connect()
        })
        present(alert, animated: true)
    }

    private func updateUIForState(_ state: LiveState) {
        let modeText = liveService.isManualTurnMode ? "Thủ công" : "Tự động"
        switch state {
        case .disconnected:
            statusBadge.setTitle("⚪️ Chưa kết nối (\(modeText))", for: .normal)
            orbHintLabel.text = "Chạm để\nBắt đầu"
            powerButton.setTitle("▶️ Bắt đầu", for: .normal)
            powerButton.backgroundColor = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0)
        case .connecting:
            statusBadge.setTitle("🟡 Đang kết nối...", for: .normal)
            orbHintLabel.text = "Đang kết nối\nGemini..."
            powerButton.setTitle("✖️ Dừng", for: .normal)
            powerButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        case .listeningUser:
            statusBadge.setTitle("🟢 Đang nghe (\(modeText))", for: .normal)
            orbHintLabel.text = liveService.isManualTurnMode
                ? "Đang nghe bạn...\n(Chạm khi nói xong)"
                : "Đang nghe bạn..."
            powerButton.setTitle("✖️ Dừng", for: .normal)
            powerButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        case .waitingResponse:
            statusBadge.setTitle("🟣 Đang sáng tạo...", for: .normal)
            orbHintLabel.text = "Gemini đang\nsuy nghĩ..."
        case .geminiSpeaking:
            statusBadge.setTitle("🔵 Gemini (\(liveService.voiceName)) đang nói", for: .normal)
            orbHintLabel.text = "Đang trả lời\n(Chạm để ngắt lời)"
        case .muted:
            statusBadge.setTitle("🔴 Đang tắt Mic", for: .normal)
            orbHintLabel.text = "Đã tắt Mic"
        }
    }

    // MARK: - Camera & Tiết kiệm tài nguyên khi Chạy nền

    private func startCamera() {
        cameraQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.automaticallyConfiguresApplicationAudioSession = false
            self.captureSession.sessionPreset = .medium

            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }

            let position: AVCaptureDevice.Position = self.isUsingFrontCamera ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)

            if self.captureSession.outputs.isEmpty {
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.cameraQueue)
                if self.captureSession.canAddOutput(self.videoOutput) {
                    self.captureSession.addOutput(self.videoOutput)
                }
            }
            self.captureSession.commitConfiguration()
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    private func stopCamera() {
        cameraQueue.async { [weak self] in
            if self?.captureSession.isRunning == true {
                self?.captureSession.stopRunning()
            }
        }
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        displayLink?.isPaused = true
        if isCameraEnabled {
            stopCamera()
        }
    }

    @objc private func appWillEnterForeground() {
        displayLink?.isPaused = false
        if isCameraEnabled {
            startCamera()
        }
    }
}

// MARK: - Delegate Nhận Trạng thái & Phụ đề Cuộn Trực Tiếp

extension LiveViewController: GeminiLiveServiceDelegate {
    func didChangeState(_ state: LiveState) {
        updateUIForState(state)
    }

    func didUpdateAudioLevel(_ level: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            self?.targetAudioLevel = level
        }
    }

    func didUpdateTranscript(userText: String?, geminiText: String?, isTurnComplete: Bool) {
        if let u = userText, !u.isEmpty {
            activeUserStreamingText = u
        }
        if let g = geminiText, !g.isEmpty {
            activeGeminiStreamingText = g
        }

        if isTurnComplete {
            let trimmedUser = activeUserStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedUser.isEmpty {
                conversationHistory.append((speaker: "Bạn", text: trimmedUser, isGemini: false))
            }
            let trimmedGemini = activeGeminiStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedGemini.isEmpty {
                conversationHistory.append((speaker: "Gemini", text: trimmedGemini, isGemini: true))
            }
            activeUserStreamingText = ""
            activeGeminiStreamingText = ""
        }

        renderLyricContent()
    }

    func didEncounterError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.conversationHistory.append((speaker: "Hệ thống", text: "⚠️ \(message)", isGemini: true))
            self.renderLyricContent()
        }
    }
}

// MARK: - Nén Khung hình Camera (1 FPS JPEG) gửi lên Gemini Live

extension LiveViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastFrameSentTime >= 1.0 else { return }
        lastFrameSentTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.45) {
            liveService.sendVideoFrame(jpegData: jpegData)
        }
    }
}

private func CATransform3DRotateAndScale(angle: CGFloat, scale: CGFloat) -> CATransform3D {
    let rotate = CATransform3DMakeRotation(angle, 0, 0, 1)
    return CATransform3DScale(rotate, scale, scale, 1)
}
