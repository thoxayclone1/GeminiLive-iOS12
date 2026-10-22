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
    private let tuningButton = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let flipCamButton = UIButton(type: .system)

    // MARK: - Bảng Điều Chỉnh Thông Số Trực Quan (Tuning Overlay)
    private let tuningOverlay = UIView()
    private let tuningCard = UIView()
    private let tempValueLabel = UILabel()
    private let tempSlider = UISlider()
    private let searchSegment = UISegmentedControl(items: ["🌐 Bật Google Search", "📴 Tắt Search"])
    private let lengthSegment = UISegmentedControl(items: ["Ngắn (1-2c)", "Vừa (2-4c)", "Chuyên sâu"])
    private let silenceSegment = UISegmentedControl(items: ["Nhanh (0.65s)", "Chuẩn (0.9s)", "Chậm (1.3s)"])
    private let vibeListScrollView = UIScrollView()
    private let vibeListStackView = UIStackView()
    private var vibeOptionButtons: [UIButton] = []
    private var pendingSelectedVibe: PersonaVibeStyle = .masterTeacher

    // MARK: - Thanh Thẻ Tương Tác Động theo từng Chế độ (Vibe)
    private let suggestionScrollView = UIScrollView()
    private let suggestionStackView = UIStackView()
    private var currentPrompts: [(title: String, prompt: String)] = []

    // MARK: - Khung Live Lyric Đa Năng
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

    private var conversationHistory: [(speaker: String, text: String, isGemini: Bool)] = []
    private var activeUserStreamingText: String = ""
    private var activeGeminiStreamingText: String = ""
    private var activeGroundingSummary: String = ""

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
        pendingSelectedVibe = liveService.personaVibeStyle
        setupBackgroundAndVignettes()
        setupOrbView()
        setupTopBar()
        setupSubtitleBox()
        setupCreativeSuggestionsBar()
        setupFloatingPillBar()
        setupTuningOverlay()
        setupLifecycleObservers()
        startDisplayLink()
        applyOrbThemeForCurrentVibe()
        reloadSuggestionChipsForCurrentVibe()
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

        outerGlowLayer.startPoint = CGPoint(x: 0, y: 0)
        outerGlowLayer.endPoint = CGPoint(x: 1, y: 1)
        outerGlowLayer.opacity = 0.38

        middleOrbLayer.startPoint = CGPoint(x: 1, y: 0)
        middleOrbLayer.endPoint = CGPoint(x: 0, y: 1)
        middleOrbLayer.opacity = 0.68

        innerCoreLayer.startPoint = CGPoint(x: 0, y: 0.5)
        innerCoreLayer.endPoint = CGPoint(x: 1, y: 0.5)
        innerCoreLayer.opacity = 0.95

        orbContainer.layer.addSublayer(outerGlowLayer)
        orbContainer.layer.addSublayer(middleOrbLayer)
        orbContainer.layer.addSublayer(innerCoreLayer)

        orbHintLabel.translatesAutoresizingMaskIntoConstraints = false
        orbHintLabel.textColor = UIColor.white.withAlphaComponent(0.94)
        orbHintLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        orbHintLabel.textAlignment = .center
        orbHintLabel.numberOfLines = 2
        orbContainer.addSubview(orbHintLabel)

        NSLayoutConstraint.activate([
            orbHintLabel.centerXAnchor.constraint(equalTo: orbContainer.centerXAnchor),
            orbHintLabel.centerYAnchor.constraint(equalTo: orbContainer.centerYAnchor),
            orbHintLabel.widthAnchor.constraint(equalToConstant: 160)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleOrbTap))
        orbContainer.addGestureRecognizer(tapGesture)
    }

    private func applyOrbThemeForCurrentVibe() {
        let isGrowth = liveService.personaVibeStyle.isGrowthOrKnowledgeMode
        if isGrowth {
            // Tông màu Trí tuệ & Kỷ luật: Xanh Dương Sắc Bén -> Tím Indigo -> Xanh Ngọc Lục Bảo
            let primaryBlue = UIColor(red: 0.18, green: 0.56, blue: 0.98, alpha: 1.0).cgColor
            let deepIndigo = UIColor(red: 0.42, green: 0.34, blue: 0.92, alpha: 1.0).cgColor
            let energeticCyan = UIColor(red: 0.12, green: 0.80, blue: 0.76, alpha: 1.0).cgColor

            outerGlowLayer.colors = [primaryBlue, deepIndigo, energeticCyan]
            middleOrbLayer.colors = [deepIndigo, energeticCyan, primaryBlue]
            innerCoreLayer.colors = [energeticCyan, primaryBlue, deepIndigo]
        } else {
            // Tông màu Thư giãn & Tâm sự: Xanh tím -> Tím trầm -> Hồng san hô
            let geminiBlue = UIColor(red: 0.35, green: 0.48, blue: 0.96, alpha: 1.0).cgColor
            let geminiPurple = UIColor(red: 0.68, green: 0.38, blue: 0.82, alpha: 1.0).cgColor
            let geminiCoral = UIColor(red: 0.92, green: 0.38, blue: 0.52, alpha: 1.0).cgColor

            outerGlowLayer.colors = [geminiBlue, geminiPurple, geminiCoral]
            middleOrbLayer.colors = [geminiPurple, geminiCoral, geminiBlue]
            innerCoreLayer.colors = [geminiCoral, geminiPurple, geminiBlue]
        }
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
        statusBadge.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        statusBadge.setTitleColor(.white, for: .normal)
        statusBadge.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        statusBadge.titleLabel?.lineBreakMode = .byTruncatingTail
        statusBadge.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusBadge.isUserInteractionEnabled = false
        view.addSubview(statusBadge)

        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.setTitle("⚙️", for: .normal)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        settingsButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        settingsButton.layer.cornerRadius = 15
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        settingsButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        view.addSubview(settingsButton)

        tuningButton.translatesAutoresizingMaskIntoConstraints = false
        tuningButton.setTitle("🎛️ Chế độ & Vibe", for: .normal)
        tuningButton.setTitleColor(.white, for: .normal)
        tuningButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        tuningButton.backgroundColor = UIColor(red: 0.25, green: 0.52, blue: 0.95, alpha: 0.42)
        tuningButton.layer.cornerRadius = 15
        tuningButton.layer.borderWidth = 1
        tuningButton.layer.borderColor = UIColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 0.65).cgColor
        tuningButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        tuningButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        tuningButton.addTarget(self, action: #selector(showTuningPanel), for: .touchUpInside)
        view.addSubview(tuningButton)

        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        voiceButton.setTitle("👩 \(liveService.voiceName)", for: .normal)
        voiceButton.setTitleColor(.white, for: .normal)
        voiceButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        voiceButton.backgroundColor = UIColor(red: 0.61, green: 0.45, blue: 0.80, alpha: 0.35)
        voiceButton.layer.cornerRadius = 15
        voiceButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        voiceButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        voiceButton.addTarget(self, action: #selector(openFemaleVoicePicker), for: .touchUpInside)
        view.addSubview(voiceButton)

        flipCamButton.translatesAutoresizingMaskIntoConstraints = false
        flipCamButton.setTitle("🔄", for: .normal)
        flipCamButton.setTitleColor(.white, for: .normal)
        flipCamButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        flipCamButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        flipCamButton.layer.cornerRadius = 15
        flipCamButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        flipCamButton.isHidden = true
        flipCamButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        view.addSubview(flipCamButton)

        let topAnchor = view.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            statusBadge.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            statusBadge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusBadge.trailingAnchor.constraint(lessThanOrEqualTo: voiceButton.leadingAnchor, constant: -6),

            settingsButton.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            tuningButton.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
            tuningButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),

            voiceButton.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
            voiceButton.trailingAnchor.constraint(equalTo: tuningButton.leadingAnchor, constant: -6),

            flipCamButton.topAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: 8),
            flipCamButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
    }

    // MARK: - Bảng Điều Chỉnh Thông Số (Độ dài, Tự ngắt Mic, Google Search & 10 Chế độ Vibe)

    private func setupTuningOverlay() {
        tuningOverlay.translatesAutoresizingMaskIntoConstraints = false
        tuningOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        tuningOverlay.isHidden = true
        view.addSubview(tuningOverlay)

        tuningCard.translatesAutoresizingMaskIntoConstraints = false
        tuningCard.backgroundColor = UIColor(red: 16/255, green: 19/255, blue: 32/255, alpha: 0.98)
        tuningCard.layer.cornerRadius = 22
        tuningCard.layer.borderWidth = 1
        tuningCard.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        tuningOverlay.addSubview(tuningCard)

        let titleLabel = UILabel()
        titleLabel.text = "🎛️ Cài đặt Huấn luyện, Search & Ngắt Mic"
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        // 1. Chọn Phong cách / Chế độ (10 chế độ cuộn mượt mà)
        let vibeTitle = UILabel()
        vibeTitle.text = "🧠 Chọn Chế độ Huấn luyện / Phong cách nói:"
        vibeTitle.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        vibeTitle.textColor = UIColor(white: 0.90, alpha: 1.0)

        vibeListScrollView.translatesAutoresizingMaskIntoConstraints = false
        vibeListScrollView.showsVerticalScrollIndicator = true
        vibeListScrollView.indicatorStyle = .white
        vibeListScrollView.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        vibeListScrollView.layer.cornerRadius = 14
        vibeListScrollView.layer.borderWidth = 1
        vibeListScrollView.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor

        vibeListStackView.translatesAutoresizingMaskIntoConstraints = false
        vibeListStackView.axis = .vertical
        vibeListStackView.spacing = 6
        vibeListScrollView.addSubview(vibeListStackView)

        vibeOptionButtons.removeAll()
        for style in PersonaVibeStyle.allCases {
            let btn = UIButton(type: .system)
            btn.tag = style.rawValue
            btn.contentHorizontalAlignment = .left
            btn.titleLabel?.numberOfLines = 2
            btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            btn.layer.cornerRadius = 10
            btn.layer.borderWidth = 1

            let titleAttr = NSMutableAttributedString(
                string: "\(style.title)\n",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
            )
            let descAttr = NSAttributedString(
                string: style.subtitleDescription,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: UIColor(white: 0.78, alpha: 1.0)
                ]
            )
            titleAttr.append(descAttr)
            btn.setAttributedTitle(titleAttr, for: .normal)
            btn.addTarget(self, action: #selector(handleVibeOptionTapped(_:)), for: .touchUpInside)
            vibeListStackView.addArrangedSubview(btn)
            vibeOptionButtons.append(btn)
        }
        refreshVibeSelectionHighlight()

        // 1.5. Công cụ Google Search Grounding
        let searchTitle = UILabel()
        searchTitle.text = "🌐 Tra cứu dữ liệu thời gian thực (Google Search):"
        searchTitle.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        searchTitle.textColor = UIColor(white: 0.90, alpha: 1.0)

        searchSegment.selectedSegmentIndex = liveService.isGoogleSearchEnabled ? 0 : 1
        styleSegmentedControl(searchSegment)

        // 2. Độ dài câu trả lời
        let lengthTitle = UILabel()
        lengthTitle.text = "📏 Độ dài câu trả lời / bài giảng:"
        lengthTitle.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        lengthTitle.textColor = UIColor(white: 0.90, alpha: 1.0)

        lengthSegment.selectedSegmentIndex = liveService.responseLengthStyle.rawValue
        styleSegmentedControl(lengthSegment)

        // 3. Độ nhạy tự động ngắt Mic (khi ở chế độ ⚡ Tự động)
        let silenceTitle = UILabel()
        silenceTitle.text = "⏱️ Tự động ngắt Mic sau khi bạn ngừng nói:"
        silenceTitle.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        silenceTitle.textColor = UIColor(white: 0.90, alpha: 1.0)

        silenceSegment.selectedSegmentIndex = liveService.autoSilenceTimeoutStyle.rawValue
        styleSegmentedControl(silenceSegment)

        // 4. Thanh trượt Độ sáng tạo (Temperature)
        let tempRow = UIStackView()
        tempRow.axis = .horizontal
        tempRow.distribution = .equalSpacing

        let tempTitle = UILabel()
        tempTitle.text = "✨ Độ chuẩn xác / Sáng tạo:"
        tempTitle.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        tempTitle.textColor = UIColor(white: 0.90, alpha: 1.0)

        tempValueLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        tempValueLabel.textColor = UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1.0)
        updateTempLabelText(liveService.creativityTemperature)

        tempRow.addArrangedSubview(tempTitle)
        tempRow.addArrangedSubview(tempValueLabel)

        tempSlider.minimumValue = 0.3
        tempSlider.maximumValue = 1.2
        tempSlider.value = liveService.creativityTemperature
        tempSlider.minimumTrackTintColor = UIColor(red: 0.25, green: 0.56, blue: 0.96, alpha: 1.0)
        tempSlider.addTarget(self, action: #selector(handleTempSliderChanged(_:)), for: .valueChanged)

        // Nút Lưu & Đóng
        let btnRow = UIStackView()
        btnRow.axis = .horizontal
        btnRow.distribution = .fillEqually
        btnRow.spacing = 12

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Đóng", for: .normal)
        cancelBtn.setTitleColor(UIColor(white: 0.85, alpha: 1.0), for: .normal)
        cancelBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        cancelBtn.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        cancelBtn.layer.cornerRadius = 14
        cancelBtn.addTarget(self, action: #selector(hideTuningPanel), for: .touchUpInside)

        let applyBtn = UIButton(type: .system)
        applyBtn.setTitle("Lưu & Áp dụng ngay", for: .normal)
        applyBtn.setTitleColor(.white, for: .normal)
        applyBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        applyBtn.backgroundColor = UIColor(red: 0.22, green: 0.52, blue: 0.95, alpha: 1.0)
        applyBtn.layer.cornerRadius = 14
        applyBtn.addTarget(self, action: #selector(applyTuningChanges), for: .touchUpInside)

        btnRow.addArrangedSubview(cancelBtn)
        btnRow.addArrangedSubview(applyBtn)

        let mainStack = UIStackView(arrangedSubviews: [
            titleLabel,
            vibeTitle,
            vibeListScrollView,
            searchTitle,
            searchSegment,
            lengthTitle,
            lengthSegment,
            silenceTitle,
            silenceSegment,
            tempRow,
            tempSlider,
            btnRow
        ])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.spacing = 8
        tuningCard.addSubview(mainStack)

        NSLayoutConstraint.activate([
            tuningOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            tuningOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tuningOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tuningOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tuningCard.centerXAnchor.constraint(equalTo: tuningOverlay.centerXAnchor),
            tuningCard.centerYAnchor.constraint(equalTo: tuningOverlay.centerYAnchor),
            tuningCard.leadingAnchor.constraint(equalTo: tuningOverlay.leadingAnchor, constant: 16),
            tuningCard.trailingAnchor.constraint(equalTo: tuningOverlay.trailingAnchor, constant: -16),

            mainStack.topAnchor.constraint(equalTo: tuningCard.topAnchor, constant: 16),
            mainStack.bottomAnchor.constraint(equalTo: tuningCard.bottomAnchor, constant: -16),
            mainStack.leadingAnchor.constraint(equalTo: tuningCard.leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: tuningCard.trailingAnchor, constant: -14),

            vibeListScrollView.heightAnchor.constraint(equalToConstant: 180),

            vibeListStackView.topAnchor.constraint(equalTo: vibeListScrollView.topAnchor, constant: 8),
            vibeListStackView.bottomAnchor.constraint(equalTo: vibeListScrollView.bottomAnchor, constant: -8),
            vibeListStackView.leadingAnchor.constraint(equalTo: vibeListScrollView.leadingAnchor, constant: 8),
            vibeListStackView.trailingAnchor.constraint(equalTo: vibeListScrollView.trailingAnchor, constant: -8),
            vibeListStackView.widthAnchor.constraint(equalTo: vibeListScrollView.widthAnchor, constant: -16),

            btnRow.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func refreshVibeSelectionHighlight() {
        for btn in vibeOptionButtons {
            let isSelected = (btn.tag == pendingSelectedVibe.rawValue)
            if isSelected {
                btn.backgroundColor = UIColor(red: 0.22, green: 0.50, blue: 0.92, alpha: 0.42)
                btn.layer.borderColor = UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 0.95).cgColor
            } else {
                btn.backgroundColor = UIColor.white.withAlphaComponent(0.05)
                btn.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
            }
        }
    }

    private func styleSegmentedControl(_ control: UISegmentedControl) {
        control.tintColor = UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1.0)
        if #available(iOS 13.0, *) {
            control.selectedSegmentTintColor = UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 0.85)
        }
        let normalAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(white: 0.85, alpha: 1.0),
            .font: UIFont.systemFont(ofSize: 11, weight: .medium)
        ]
        let selectedAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 11, weight: .bold)
        ]
        control.setTitleTextAttributes(normalAttr, for: .normal)
        control.setTitleTextAttributes(selectedAttr, for: .selected)
    }

    private func updateTempLabelText(_ val: Float) {
        let formatted = String(format: "%.2f", val)
        let desc: String
        if val < 0.6 {
            desc = "Chuẩn xác & Logic"
        } else if val <= 0.82 {
            desc = "Cân bằng"
        } else {
            desc = "Sáng tạo cao"
        }
        tempValueLabel.text = "\(formatted) (\(desc))"
    }

    // MARK: - Khung Live Lyric

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
        lyricTitleLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        lyricTitleLabel.textColor = UIColor(red: 0.65, green: 0.82, blue: 1.0, alpha: 1.0)
        lyricTitleLabel.lineBreakMode = .byTruncatingTail
        lyricTitleLabel.numberOfLines = 1
        lyricTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lyricTitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lyricHeaderBar.addSubview(lyricTitleLabel)

        configureHeaderActionButton(clearLyricButton, title: "🗑️ Xóa", action: #selector(clearLyricHistory))
        configureHeaderActionButton(copyLyricButton, title: "📋 Chép", action: #selector(copyLyricText))
        configureHeaderActionButton(expandLyricButton, title: "🔍 Mở rộng", action: #selector(toggleLyricExpand))

        let headerButtonsStack = UIStackView(arrangedSubviews: [clearLyricButton, copyLyricButton, expandLyricButton])
        headerButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        headerButtonsStack.axis = .horizontal
        headerButtonsStack.spacing = 5
        headerButtonsStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        headerButtonsStack.setContentHuggingPriority(.required, for: .horizontal)
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
        toggleSubButton.setTitleColor(UIColor(white: 0.78, alpha: 1.0), for: .normal)
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
            lyricHeaderBar.heightAnchor.constraint(equalToConstant: 34),

            lyricTitleLabel.leadingAnchor.constraint(equalTo: lyricHeaderBar.leadingAnchor, constant: 12),
            lyricTitleLabel.centerYAnchor.constraint(equalTo: lyricHeaderBar.centerYAnchor),
            lyricTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerButtonsStack.leadingAnchor, constant: -8),

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
        button.setTitleColor(UIColor(white: 0.92, alpha: 1.0), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    // MARK: - Thanh Thẻ Tương Tác Động theo từng Chế độ

    private func setupCreativeSuggestionsBar() {
        suggestionScrollView.translatesAutoresizingMaskIntoConstraints = false
        suggestionScrollView.showsHorizontalScrollIndicator = false
        view.addSubview(suggestionScrollView)

        suggestionStackView.translatesAutoresizingMaskIntoConstraints = false
        suggestionStackView.axis = .horizontal
        suggestionStackView.spacing = 8
        suggestionScrollView.addSubview(suggestionStackView)

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

    private func reloadSuggestionChipsForCurrentVibe() {
        for subview in suggestionStackView.arrangedSubviews {
            suggestionStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let vibe = liveService.personaVibeStyle
        var prompts = vibe.quickActionPrompts
        if liveService.isGoogleSearchEnabled {
            let testPrompt = (
                title: "🌐 Test Google Search",
                prompt: "Hãy dùng Google Search tra cứu giúp tôi: hôm nay là thứ mấy, ngày bao nhiêu, giá vàng hoặc tin tức công nghệ mới nhất hôm nay là gì, và nêu rõ nguồn bạn vừa tìm được."
            )
            prompts.insert(testPrompt, at: 0)
        }
        currentPrompts = prompts
        let isGrowth = vibe.isGrowthOrKnowledgeMode

        for (index, item) in currentPrompts.enumerated() {
            let chip = UIButton(type: .system)
            chip.tag = index
            chip.setTitle(item.title, for: .normal)
            chip.setTitleColor(.white, for: .normal)
            chip.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)

            let isSearchTestChip = (liveService.isGoogleSearchEnabled && index == 0)
            if isSearchTestChip {
                chip.backgroundColor = UIColor(red: 0.12, green: 0.52, blue: 0.36, alpha: 0.78)
                chip.layer.borderColor = UIColor(red: 0.30, green: 0.92, blue: 0.58, alpha: 0.75).cgColor
            } else {
                chip.backgroundColor = isGrowth
                    ? UIColor(red: 0.16, green: 0.36, blue: 0.65, alpha: 0.65)
                    : UIColor(red: 0.45, green: 0.25, blue: 0.48, alpha: 0.58)
                chip.layer.borderColor = isGrowth
                    ? UIColor(red: 0.38, green: 0.68, blue: 1.0, alpha: 0.55).cgColor
                    : UIColor(red: 0.90, green: 0.45, blue: 0.62, alpha: 0.5).cgColor
            }
            chip.layer.cornerRadius = 15
            chip.layer.borderWidth = 1
            chip.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            chip.addTarget(self, action: #selector(handleCreativeChipTap(_:)), for: .touchUpInside)
            suggestionStackView.addArrangedSubview(chip)
        }
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
        powerButton.backgroundColor = UIColor(red: 0.22, green: 0.52, blue: 0.95, alpha: 1.0)

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
        let vibe = liveService.personaVibeStyle
        let searchBadge = liveService.isGoogleSearchEnabled ? " • 🌐" : ""
        lyricTitleLabel.text = "💬 \(vibe.shortTitle) • \(liveService.responseLengthStyle.shortTitle)\(searchBadge)"

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
        let geminiHeaderColor = vibe.isGrowthOrKnowledgeMode
            ? UIColor(red: 0.35, green: 0.85, blue: 0.78, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.52, blue: 0.68, alpha: 1.0)
        let geminiHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: geminiHeaderColor,
            .paragraphStyle: paragraphStyle
        ]
        let geminiHistoryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: UIColor(white: 0.93, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        let geminiLiveActiveAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let groundingAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor(red: 0.30, green: 0.92, blue: 0.58, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]

        if conversationHistory.isEmpty && activeUserStreamingText.isEmpty && activeGeminiStreamingText.isEmpty && activeGroundingSummary.isEmpty {
            let modeAutoDesc = liveService.isManualTurnMode
                ? "Thủ công (Chạm quả cầu khi nói xong)"
                : "Tự động ngắt mic sau \(liveService.autoSilenceTimeoutStyle.title)"
            let searchStatusDesc = liveService.isGoogleSearchEnabled ? "🌐 Đang bật" : "📴 Đang tắt"
            let welcome = NSAttributedString(
                string: "🎯 Chế độ hiện tại: \(vibe.title) — \(vibe.subtitleDescription).\n• Giọng: \(liveService.voiceName) | Độ dài: \(liveService.responseLengthStyle.title) | Google Search: \(searchStatusDesc) | Mic: \(modeAutoDesc).\n👉 Nhấn ▶️ Bắt đầu rồi bấm thẻ '🌐 Test Google Search' ở trên để kiểm tra tra cứu trực tiếp!",
                attributes: geminiHistoryAttributes
            )
            attributed.append(welcome)
        } else {
            for item in conversationHistory.suffix(12) {
                let header = item.isGemini ? "\(vibe.speakerDisplayName) (\(liveService.voiceName)): " : "🗣️ Bạn: "
                let headerAttr = item.isGemini ? geminiHeaderAttributes : userHeaderAttributes
                let bodyAttr = item.isGemini ? geminiHistoryAttributes : userBodyAttributes

                attributed.append(NSAttributedString(string: header, attributes: headerAttr))
                attributed.append(NSAttributedString(string: "\(item.text)\n", attributes: bodyAttr))
            }

            if !activeUserStreamingText.isEmpty {
                attributed.append(NSAttributedString(string: "🗣️ Bạn (đang nói): ", attributes: userHeaderAttributes))
                attributed.append(NSAttributedString(string: "\(activeUserStreamingText)\n", attributes: userBodyAttributes))
            }

            if !activeGroundingSummary.isEmpty {
                attributed.append(NSAttributedString(string: "\(activeGroundingSummary)\n", attributes: groundingAttributes))
            }

            if !activeGeminiStreamingText.isEmpty {
                let actionVerb = vibe.isGrowthOrKnowledgeMode ? "đang phân tích" : "đang chia sẻ"
                attributed.append(NSAttributedString(string: "\(vibe.speakerDisplayName) (\(actionVerb)): ", attributes: geminiHeaderAttributes))
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

    // MARK: - Xử lý Nút bấm & Bảng Điều Chỉnh

    @objc private func showTuningPanel() {
        pendingSelectedVibe = liveService.personaVibeStyle
        refreshVibeSelectionHighlight()
        searchSegment.selectedSegmentIndex = liveService.isGoogleSearchEnabled ? 0 : 1
        tempSlider.value = liveService.creativityTemperature
        updateTempLabelText(liveService.creativityTemperature)
        lengthSegment.selectedSegmentIndex = liveService.responseLengthStyle.rawValue
        silenceSegment.selectedSegmentIndex = liveService.autoSilenceTimeoutStyle.rawValue
        tuningOverlay.isHidden = false
    }

    @objc private func hideTuningPanel() {
        tuningOverlay.isHidden = true
    }

    @objc private func handleVibeOptionTapped(_ sender: UIButton) {
        guard let selected = PersonaVibeStyle(rawValue: sender.tag) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pendingSelectedVibe = selected
        refreshVibeSelectionHighlight()
    }

    @objc private func handleTempSliderChanged(_ sender: UISlider) {
        let stepped = round(sender.value * 20) / 20
        sender.value = stepped
        updateTempLabelText(stepped)
    }

    @objc private func applyTuningChanges() {
        liveService.personaVibeStyle = pendingSelectedVibe
        liveService.isGoogleSearchEnabled = (searchSegment.selectedSegmentIndex == 0)
        liveService.creativityTemperature = tempSlider.value
        if let length = ResponseLengthStyle(rawValue: lengthSegment.selectedSegmentIndex) {
            liveService.responseLengthStyle = length
        }
        if let silence = AutoSilenceTimeoutStyle(rawValue: silenceSegment.selectedSegmentIndex) {
            liveService.autoSilenceTimeoutStyle = silence
        }

        tuningOverlay.isHidden = true
        applyOrbThemeForCurrentVibe()
        reloadSuggestionChipsForCurrentVibe()
        renderLyricContent()

        if liveService.state != .disconnected {
            liveService.connect()
        }
    }

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
        guard index >= 0 && index < currentPrompts.count else { return }
        let selected = currentPrompts[index]
        liveService.sendCreativePrompt(selected.prompt)
    }

    @objc private func toggleLyricExpand() {
        isLyricExpanded.toggle()
        let targetHeight: CGFloat = isLyricExpanded ? 320 : 175
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
        activeGroundingSummary = ""
        renderLyricContent()
    }

    @objc private func openFemaleVoicePicker() {
        let sheet = UIAlertController(
            title: "👩 Chọn Giọng Trợ Lý / Mentor",
            message: "Đang kết hợp cùng chế độ: \(liveService.personaVibeStyle.title)",
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
        renderLyricContent()
    }

    @objc private func handleCamTap() {
        isCameraEnabled.toggle()
        if isCameraEnabled {
            startCamera()
            previewLayer?.isHidden = false
            flipCamButton.isHidden = false
            camButton.backgroundColor = UIColor(red: 0.22, green: 0.52, blue: 0.95, alpha: 0.78)
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
            title: "⚙️ Cài đặt API & Yêu cầu riêng",
            message: "Để đổi Chế độ (Nghiêm khắc, Dạy học, Khoa học, Phê bình...) hoặc Bật/Tắt Google Search hãy bấm nút '🎛️ Chế độ & Vibe' trên màn hình chính.",
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
            tf.placeholder = "Ghi chú riêng (VD: Tôi học CNTT, thích ví dụ thực tế...)"
            tf.text = self.liveService.customExtraPrompt
            tf.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu & Kết nối", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.liveService.apiKey = alert.textFields?[0].text ?? ""

            let model = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.liveService.modelName = model.isEmpty ? "models/gemini-2.5-flash-native-audio-preview-12-2025" : model

            self.liveService.customExtraPrompt = alert.textFields?[2].text ?? ""
            self.renderLyricContent()
            self.liveService.connect()
        })
        present(alert, animated: true)
    }

    private func updateUIForState(_ state: LiveState) {
        let modeText = liveService.isManualTurnMode ? "Thủ công" : "Tự động"
        let speaker = liveService.personaVibeStyle.speakerDisplayName
        switch state {
        case .disconnected:
            statusBadge.setTitle("⚪️ Chưa kết nối", for: .normal)
            orbHintLabel.text = "Chạm để\nBắt đầu"
            powerButton.setTitle("▶️ Bắt đầu", for: .normal)
            powerButton.backgroundColor = UIColor(red: 0.22, green: 0.52, blue: 0.95, alpha: 1.0)
        case .connecting:
            statusBadge.setTitle("🟡 Đang kết nối...", for: .normal)
            orbHintLabel.text = "Đang kết nối\n\(speaker)..."
            powerButton.setTitle("✖️ Dừng", for: .normal)
            powerButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        case .listeningUser:
            if liveService.isUserTurnCapturing {
                statusBadge.setTitle("🟢 Đang thu giọng (\(modeText))", for: .normal)
                orbHintLabel.text = liveService.isManualTurnMode
                    ? "Đang thu âm...\n(Chạm khi nói xong)"
                    : "Đang nghe bạn nói...\n(Ngừng nói tự ngắt)"
            } else {
                statusBadge.setTitle("🟢 Đang nghe (\(modeText))", for: .normal)
                orbHintLabel.text = liveService.isManualTurnMode
                    ? "Hãy nói...\n(Chạm khi nói xong)"
                    : "Hãy nói...\n(Tự ngắt khi dừng)"
            }
            powerButton.setTitle("✖️ Dừng", for: .normal)
            powerButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        case .waitingResponse:
            statusBadge.setTitle("🟣 Đã ngắt Mic • Đang xử lý...", for: .normal)
            orbHintLabel.text = "Đã ngắt Mic\nĐang suy nghĩ..."
        case .geminiSpeaking:
            statusBadge.setTitle("🔊 \(speaker) đang nói", for: .normal)
            orbHintLabel.text = "\(speaker) đang nói\n(Chạm để ngắt lời)"
        case .muted:
            statusBadge.setTitle("🔴 Đã tắt Mic", for: .normal)
            orbHintLabel.text = "Đang tắt Mic"
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

// MARK: - Delegate Nhận Trạng thái, Xác thực Google Search & Phụ đề Cuộn Trực Tiếp

extension LiveViewController: GeminiLiveServiceDelegate {
    func didChangeState(_ state: LiveState) {
        updateUIForState(state)
    }

    func didUpdateVoiceActivity(isSpeaking: Bool) {
        updateUIForState(liveService.state)
    }

    func didUpdateAudioLevel(_ level: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            self?.targetAudioLevel = level
        }
    }

    func didReceiveGroundingMetadata(queries: [String], sources: [String]) {
        let queryText = queries.isEmpty ? "Đang tra cứu trực tiếp" : queries.joined(separator: ", ")
        let sourceText = sources.isEmpty ? "" : " | Nguồn: \(sources.prefix(3).joined(separator: ", "))"
        activeGroundingSummary = "✅ 🌐 [Google Search đã chạy] Từ khóa: \"\(queryText)\"\(sourceText)"

        statusBadge.setTitle("🌐 Đã tra cứu Google Search", for: .normal)
        renderLyricContent()
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

            var trimmedGemini = activeGeminiStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !activeGroundingSummary.isEmpty {
                trimmedGemini = trimmedGemini.isEmpty
                    ? activeGroundingSummary
                    : "\(trimmedGemini)\n\(activeGroundingSummary)"
            }
            if !trimmedGemini.isEmpty {
                conversationHistory.append((speaker: liveService.personaVibeStyle.speakerDisplayName, text: trimmedGemini, isGemini: true))
            }

            activeUserStreamingText = ""
            activeGeminiStreamingText = ""
            activeGroundingSummary = ""
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
