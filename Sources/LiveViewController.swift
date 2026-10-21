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
    private let lengthSegment = UISegmentedControl(items: ["Ngắn", "Vừa (Mặc định)", "Sâu sắc"])
    private let vibeSegment = UISegmentedControl(items: ["🔥 Quyến rũ", "💕 Ngọt ngào", "😎 Gen Z", "🍷 Tri kỷ"])

    // MARK: - Thanh Thẻ Tương Tác Thân Mật & Gen Z
    private let suggestionScrollView = UIScrollView()
    private let suggestionStackView = UIStackView()
    private let creativePrompts: [(title: String, prompt: String)] = [
        ("🔥 Trêu anh chút", "Nói gì đó vừa quyến rũ, ngọt ngào vừa hài hước kiểu Gen Z để trêu anh và hỏi thăm xem hôm nay anh thế nào đi, ngắn gọn thôi nhé!"),
        ("💕 Quan tâm anh đi", "Hôm nay anh hơi mệt một chút, em hãy hỏi han, dỗ dành và tiếp năng lượng cho anh bằng giọng ngọt ngào và cuốn hút nhất đi."),
        ("😏 Tâm sự mỏng", "Khơi gợi một chủ đề tâm sự vừa thú vị, vừa thân mật và hơi táo bạo một chút để hai đứa mình trò chuyện đi."),
        ("✨ Gợi ý chill", "Gợi ý nhanh cho anh 1 điều thú vị để làm hoặc thưởng thức ngay lúc này theo phong cách thật chill và tinh tế nhé."),
        ("📷 Nhìn anh nè", "Nhìn qua camera xem anh hoặc không gian quanh anh đang thế nào, rồi khen hoặc trêu anh một câu thật duyên nhé!")
    ]

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
        setupTuningOverlay()
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

        // Phối màu quyến rũ ấm áp hơn: Xanh tím -> Tím trầm -> Hồng san hô
        let geminiBlue = UIColor(red: 0.35, green: 0.48, blue: 0.96, alpha: 1.0).cgColor
        let geminiPurple = UIColor(red: 0.68, green: 0.38, blue: 0.82, alpha: 1.0).cgColor
        let geminiCoral = UIColor(red: 0.92, green: 0.38, blue: 0.52, alpha: 1.0).cgColor

        outerGlowLayer.colors = [geminiBlue, geminiPurple, geminiCoral]
        outerGlowLayer.startPoint = CGPoint(x: 0, y: 0)
        outerGlowLayer.endPoint = CGPoint(x: 1, y: 1)
        outerGlowLayer.opacity = 0.38

        middleOrbLayer.colors = [geminiPurple, geminiCoral, geminiBlue]
        middleOrbLayer.startPoint = CGPoint(x: 1, y: 0)
        middleOrbLayer.endPoint = CGPoint(x: 0, y: 1)
        middleOrbLayer.opacity = 0.68

        innerCoreLayer.colors = [geminiCoral, geminiPurple, geminiBlue]
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
        statusBadge.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        statusBadge.setTitleColor(.white, for: .normal)
        statusBadge.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        statusBadge.isUserInteractionEnabled = false
        view.addSubview(statusBadge)

        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.setTitle("⚙️", for: .normal)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        settingsButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        settingsButton.layer.cornerRadius = 15
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        view.addSubview(settingsButton)

        // Nút mở Bảng Điều Chỉnh Độ dài & Độ sáng tạo
        tuningButton.translatesAutoresizingMaskIntoConstraints = false
        tuningButton.setTitle("🎛️ Độ dài & Vibe", for: .normal)
        tuningButton.setTitleColor(.white, for: .normal)
        tuningButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        tuningButton.backgroundColor = UIColor(red: 0.88, green: 0.36, blue: 0.52, alpha: 0.38)
        tuningButton.layer.cornerRadius = 15
        tuningButton.layer.borderWidth = 1
        tuningButton.layer.borderColor = UIColor(red: 0.95, green: 0.50, blue: 0.65, alpha: 0.55).cgColor
        tuningButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        tuningButton.addTarget(self, action: #selector(showTuningPanel), for: .touchUpInside)
        view.addSubview(tuningButton)

        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        voiceButton.setTitle("👩 \(liveService.voiceName)", for: .normal)
        voiceButton.setTitleColor(.white, for: .normal)
        voiceButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        voiceButton.backgroundColor = UIColor(red: 0.61, green: 0.45, blue: 0.80, alpha: 0.35)
        voiceButton.layer.cornerRadius = 15
        voiceButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
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

    // MARK: - Bảng Điều Chỉnh Thông Số (Độ dài, Độ sáng tạo, Vibe)

    private func setupTuningOverlay() {
        tuningOverlay.translatesAutoresizingMaskIntoConstraints = false
        tuningOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        tuningOverlay.isHidden = true
        view.addSubview(tuningOverlay)

        tuningCard.translatesAutoresizingMaskIntoConstraints = false
        tuningCard.backgroundColor = UIColor(red: 18/255, green: 20/255, blue: 34/255, alpha: 0.98)
        tuningCard.layer.cornerRadius = 22
        tuningCard.layer.borderWidth = 1
        tuningCard.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        tuningOverlay.addSubview(tuningCard)

        let titleLabel = UILabel()
        titleLabel.text = "🎛️ Điều chỉnh Độ dài, Sáng tạo & Vibe"
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        // 1. Độ dài câu trả lời
        let lengthTitle = UILabel()
        lengthTitle.text = "📏 Độ dài câu trả lời của em:"
        lengthTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        lengthTitle.textColor = UIColor(white: 0.88, alpha: 1.0)

        lengthSegment.selectedSegmentIndex = liveService.responseLengthStyle.rawValue
        styleSegmentedControl(lengthSegment)

        // 2. Thanh trượt Độ sáng tạo (Temperature)
        let tempRow = UIStackView()
        tempRow.axis = .horizontal
        tempRow.distribution = .equalSpacing

        let tempTitle = UILabel()
        tempTitle.text = "✨ Độ sáng tạo & Bay bổng:"
        tempTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        tempTitle.textColor = UIColor(white: 0.88, alpha: 1.0)

        tempValueLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        tempValueLabel.textColor = UIColor(red: 0.95, green: 0.55, blue: 0.70, alpha: 1.0)
        updateTempLabelText(liveService.creativityTemperature)

        tempRow.addArrangedSubview(tempTitle)
        tempRow.addArrangedSubview(tempValueLabel)

        tempSlider.minimumValue = 0.3
        tempSlider.maximumValue = 1.2
        tempSlider.value = liveService.creativityTemperature
        tempSlider.minimumTrackTintColor = UIColor(red: 0.90, green: 0.42, blue: 0.58, alpha: 1.0)
        tempSlider.addTarget(self, action: #selector(handleTempSliderChanged(_:)), for: .valueChanged)

        let tempHint = UILabel()
        tempHint.text = "0.5: Thực tế, gọn • 0.75: Tự nhiên (Mặc định) • 1.0+: Rất bay bổng"
        tempHint.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        tempHint.textColor = UIColor(white: 0.6, alpha: 1.0)
        tempHint.textAlignment = .center

        // 3. Phong cách (Vibe)
        let vibeTitle = UILabel()
        vibeTitle.text = "💃 Phong cách nói chuyện (Vibe):"
        vibeTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        vibeTitle.textColor = UIColor(white: 0.88, alpha: 1.0)

        vibeSegment.selectedSegmentIndex = liveService.personaVibeStyle.rawValue
        styleSegmentedControl(vibeSegment)

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
        applyBtn.backgroundColor = UIColor(red: 0.88, green: 0.36, blue: 0.52, alpha: 1.0)
        applyBtn.layer.cornerRadius = 14
        applyBtn.addTarget(self, action: #selector(applyTuningChanges), for: .touchUpInside)

        btnRow.addArrangedSubview(cancelBtn)
        btnRow.addArrangedSubview(applyBtn)

        let mainStack = UIStackView(arrangedSubviews: [
            titleLabel,
            lengthTitle,
            lengthSegment,
            tempRow,
            tempSlider,
            tempHint,
            vibeTitle,
            vibeSegment,
            btnRow
        ])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.spacing = 11
        tuningCard.addSubview(mainStack)

        NSLayoutConstraint.activate([
            tuningOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            tuningOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tuningOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tuningOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tuningCard.centerXAnchor.constraint(equalTo: tuningOverlay.centerXAnchor),
            tuningCard.centerYAnchor.constraint(equalTo: tuningOverlay.centerYAnchor),
            tuningCard.leadingAnchor.constraint(equalTo: tuningOverlay.leadingAnchor, constant: 20),
            tuningCard.trailingAnchor.constraint(equalTo: tuningOverlay.trailingAnchor, constant: -20),

            mainStack.topAnchor.constraint(equalTo: tuningCard.topAnchor, constant: 18),
            mainStack.bottomAnchor.constraint(equalTo: tuningCard.bottomAnchor, constant: -18),
            mainStack.leadingAnchor.constraint(equalTo: tuningCard.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: tuningCard.trailingAnchor, constant: -16),

            btnRow.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func styleSegmentedControl(_ control: UISegmentedControl) {
        control.tintColor = UIColor(red: 0.88, green: 0.36, blue: 0.52, alpha: 1.0)
        if #available(iOS 13.0, *) {
            control.selectedSegmentTintColor = UIColor(red: 0.88, green: 0.36, blue: 0.52, alpha: 0.85)
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
            desc = "Gọn & Thực tế"
        } else if val <= 0.82 {
            desc = "Vừa đẹp"
        } else {
            desc = "Bay bổng"
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
        lyricTitleLabel.text = "💬 Live Lyric • \(liveService.personaVibeStyle.title)"
        lyricTitleLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        lyricTitleLabel.textColor = UIColor(red: 0.95, green: 0.68, blue: 0.80, alpha: 1.0)
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

    // MARK: - Thanh Thẻ Tương Tác Thân Mật

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
            chip.backgroundColor = UIColor(red: 0.45, green: 0.25, blue: 0.48, alpha: 0.58)
            chip.layer.cornerRadius = 15
            chip.layer.borderWidth = 1
            chip.layer.borderColor = UIColor(red: 0.90, green: 0.45, blue: 0.62, alpha: 0.5).cgColor
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
        powerButton.backgroundColor = UIColor(red: 0.88, green: 0.36, blue: 0.52, alpha: 1.0)

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
        lyricTitleLabel.text = "💬 Live Lyric • \(liveService.personaVibeStyle.title) • \(liveService.responseLengthStyle.title)"

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
            .foregroundColor: UIColor(red: 0.96, green: 0.52, blue: 0.68, alpha: 1.0),
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

        if conversationHistory.isEmpty && activeUserStreamingText.isEmpty && activeGeminiStreamingText.isEmpty {
            let tempStr = String(format: "%.2f", liveService.creativityTemperature)
            let welcome = NSAttributedString(
                string: "💕 Chào anh! Em đang ở chế độ \(liveService.personaVibeStyle.title) (Giọng \(liveService.voiceName), độ dài: \(liveService.responseLengthStyle.title), sáng tạo: \(tempStr)).\nAnh nhấn ▶️ Bắt đầu để tâm sự với em hoặc bấm 🎛️ ở trên để chỉnh độ dài câu nói nhé!",
                attributes: geminiHistoryAttributes
            )
            attributed.append(welcome)
        } else {
            for item in conversationHistory.suffix(12) {
                let header = item.isGemini ? "👩 Em (\(liveService.voiceName)): " : "🗣️ Anh: "
                let headerAttr = item.isGemini ? geminiHeaderAttributes : userHeaderAttributes
                let bodyAttr = item.isGemini ? geminiHistoryAttributes : userBodyAttributes

                attributed.append(NSAttributedString(string: header, attributes: headerAttr))
                attributed.append(NSAttributedString(string: "\(item.text)\n", attributes: bodyAttr))
            }

            if !activeUserStreamingText.isEmpty {
                attributed.append(NSAttributedString(string: "🗣️ Anh (đang nói): ", attributes: userHeaderAttributes))
                attributed.append(NSAttributedString(string: "\(activeUserStreamingText)\n", attributes: userBodyAttributes))
            }

            if !activeGeminiStreamingText.isEmpty {
                attributed.append(NSAttributedString(string: "👩 Em (đang thủ thỉ): ", attributes: geminiHeaderAttributes))
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
        tempSlider.value = liveService.creativityTemperature
        updateTempLabelText(liveService.creativityTemperature)
        lengthSegment.selectedSegmentIndex = liveService.responseLengthStyle.rawValue
        vibeSegment.selectedSegmentIndex = liveService.personaVibeStyle.rawValue
        tuningOverlay.isHidden = false
    }

    @objc private func hideTuningPanel() {
        tuningOverlay.isHidden = true
    }

    @objc private func handleTempSliderChanged(_ sender: UISlider) {
        let stepped = round(sender.value * 20) / 20
        sender.value = stepped
        updateTempLabelText(stepped)
    }

    @objc private func applyTuningChanges() {
        liveService.creativityTemperature = tempSlider.value
        if let length = ResponseLengthStyle(rawValue: lengthSegment.selectedSegmentIndex) {
            liveService.responseLengthStyle = length
        }
        if let vibe = PersonaVibeStyle(rawValue: vibeSegment.selectedSegmentIndex) {
            liveService.personaVibeStyle = vibe
        }

        tuningOverlay.isHidden = true
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
        guard index >= 0 && index < creativePrompts.count else { return }
        let selected = creativePrompts[index]
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
        renderLyricContent()
    }

    @objc private func openFemaleVoicePicker() {
        let sheet = UIAlertController(
            title: "👩 Chọn Giọng Nữ cho Em",
            message: "Kết hợp cùng Vibe \(liveService.personaVibeStyle.title) để có giọng điệu tự nhiên, gợi cảm nhất.",
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
            camButton.backgroundColor = UIColor(red: 0.88, green: 0.36, blue: 0.52, alpha: 0.75)
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
            message: "Để chỉnh Độ dài, Độ sáng tạo và Vibe nhanh, hãy bấm nút '🎛️ Độ dài & Vibe' trên màn hình chính.",
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
            tf.placeholder = "Ghi chú riêng cho em (VD: Gọi anh là Tuấn, thích trêu ghẹo...)"
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
        switch state {
        case .disconnected:
            statusBadge.setTitle("⚪️ Chưa kết nối", for: .normal)
            orbHintLabel.text = "Chạm để\nTrò chuyện"
            powerButton.setTitle("▶️ Bắt đầu", for: .normal)
            powerButton.backgroundColor = UIColor(red: 0.88, green: 0.36, blue: 0.52, alpha: 1.0)
        case .connecting:
            statusBadge.setTitle("🟡 Đang kết nối...", for: .normal)
            orbHintLabel.text = "Đang gọi\ncho em..."
            powerButton.setTitle("✖️ Dừng", for: .normal)
            powerButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        case .listeningUser:
            statusBadge.setTitle("🟢 Đang nghe (\(modeText))", for: .normal)
            orbHintLabel.text = liveService.isManualTurnMode
                ? "Em đang nghe...\n(Chạm khi nói xong)"
                : "Em đang nghe\nanh nói..."
            powerButton.setTitle("✖️ Dừng", for: .normal)
            powerButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        case .waitingResponse:
            statusBadge.setTitle("🟣 Em đang nghĩ...", for: .normal)
            orbHintLabel.text = "Đợi em\nmột nhịp..."
        case .geminiSpeaking:
            statusBadge.setTitle("💕 Em (\(liveService.voiceName)) đang nói", for: .normal)
            orbHintLabel.text = "Em đang nói\n(Chạm để ngắt lời)"
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
                conversationHistory.append((speaker: "Anh", text: trimmedUser, isGemini: false))
            }
            let trimmedGemini = activeGeminiStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedGemini.isEmpty {
                conversationHistory.append((speaker: "Em", text: trimmedGemini, isGemini: true))
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
