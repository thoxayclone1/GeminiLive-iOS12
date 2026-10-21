import UIKit
import AVFoundation

final class LiveViewController: UIViewController {
    private let liveService = GeminiLiveService()

    // MARK: - Camera (Vision Live)
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "com.geminilive.camera")
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

    // MARK: - Các lớp phủ giao diện
    private let topVignette = CAGradientLayer()
    private let bottomVignette = CAGradientLayer()
    private let statusBadge = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let flipCamButton = UIButton(type: .system)

    // Hộp thoại phụ đề ngắn (15pt)
    private let subtitleContainer = UIView()
    private let userSubtitleLabel = UILabel()
    private let geminiSubtitleLabel = UILabel()
    private let toggleSubButton = UIButton(type: .system)
    private var isSubtitleHidden = false

    // Thanh con nhộng điều khiển (Floating Pill Bar)
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
        setupFloatingPillBar()
        setupLifecycleObservers()
        startDisplayLink()
        updateUIForState(.disconnected)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        topVignette.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height * 0.18)
        bottomVignette.frame = CGRect(
            x: 0,
            y: view.bounds.height * 0.65,
            width: view.bounds.width,
            height: view.bounds.height * 0.35
        )
        layoutOrbLayers()
    }

    // MARK: - Dựng Giao Diện

    private func setupBackgroundAndVignettes() {
        // Nền đen sâu chuẩn Google Gemini (#06060E)
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
            UIColor.black.withAlphaComponent(0.88).cgColor
        ]
        view.layer.addSublayer(topVignette)
        view.layer.addSublayer(bottomVignette)
    }

    private func setupOrbView() {
        orbContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(orbContainer)

        NSLayoutConstraint.activate([
            orbContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            orbContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -45),
            orbContainer.widthAnchor.constraint(equalToConstant: 240),
            orbContainer.heightAnchor.constraint(equalToConstant: 240)
        ])

        // Tông màu chuẩn Google Gemini: Xanh (#4285F4) -> Tím (#9B72CB) -> Hồng đào (#D96570)
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
        orbHintLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        orbHintLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        orbHintLabel.textAlignment = .center
        orbHintLabel.numberOfLines = 2
        orbContainer.addSubview(orbHintLabel)

        NSLayoutConstraint.activate([
            orbHintLabel.centerXAnchor.constraint(equalTo: orbContainer.centerXAnchor),
            orbHintLabel.centerYAnchor.constraint(equalTo: orbContainer.centerYAnchor),
            orbHintLabel.widthAnchor.constraint(equalToConstant: 160)
        ])

        // Chạm vào Quả cầu để báo "Đã nói xong" (Tap-to-Finish) hoặc ngắt lời Gemini
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleOrbTap))
        orbContainer.addGestureRecognizer(tapGesture)
    }

    private func layoutOrbLayers() {
        let bounds = orbContainer.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let outerSize: CGFloat = 220
        outerGlowLayer.bounds = CGRect(x: 0, y: 0, width: outerSize, height: outerSize)
        outerGlowLayer.position = center
        outerGlowLayer.cornerRadius = outerSize / 2

        let midSize: CGFloat = 175
        middleOrbLayer.bounds = CGRect(x: 0, y: 0, width: midSize, height: midSize)
        middleOrbLayer.position = center
        middleOrbLayer.cornerRadius = midSize / 2

        let coreSize: CGFloat = 135
        innerCoreLayer.bounds = CGRect(x: 0, y: 0, width: coreSize, height: coreSize)
        innerCoreLayer.position = center
        innerCoreLayer.cornerRadius = coreSize / 2
    }

    private func setupTopBar() {
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        statusBadge.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        statusBadge.layer.cornerRadius = 16
        statusBadge.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        statusBadge.setTitleColor(.white, for: .normal)
        statusBadge.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        statusBadge.isUserInteractionEnabled = false
        view.addSubview(statusBadge)

        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.setTitle("⚙️ Cài đặt", for: .normal)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        settingsButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        settingsButton.layer.cornerRadius = 16
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        view.addSubview(settingsButton)

        flipCamButton.translatesAutoresizingMaskIntoConstraints = false
        flipCamButton.setTitle("🔄 Đổi Cam", for: .normal)
        flipCamButton.setTitleColor(.white, for: .normal)
        flipCamButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        flipCamButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        flipCamButton.layer.cornerRadius = 16
        flipCamButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        flipCamButton.isHidden = true
        flipCamButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        view.addSubview(flipCamButton)

        let topAnchor = view.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            statusBadge.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            statusBadge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            settingsButton.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            flipCamButton.centerYAnchor.constraint(equalTo: statusBadge.centerYAnchor),
            flipCamButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -8)
        ])
    }

    private func setupSubtitleBox() {
        subtitleContainer.translatesAutoresizingMaskIntoConstraints = false
        subtitleContainer.backgroundColor = UIColor(white: 0.08, alpha: 0.82)
        subtitleContainer.layer.cornerRadius = 16
        subtitleContainer.layer.borderWidth = 1
        subtitleContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        view.addSubview(subtitleContainer)

        userSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        userSubtitleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        userSubtitleLabel.textColor = UIColor(white: 0.72, alpha: 1.0)
        userSubtitleLabel.numberOfLines = 2
        userSubtitleLabel.text = "Bạn: (Nhấn Bắt đầu để trò chuyện)"

        geminiSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        geminiSubtitleLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        geminiSubtitleLabel.textColor = .white
        geminiSubtitleLabel.numberOfLines = 3
        geminiSubtitleLabel.text = "Gemini: Sẵn sàng lắng nghe bạn."

        toggleSubButton.translatesAutoresizingMaskIntoConstraints = false
        toggleSubButton.setTitle("Ẩn chữ", for: .normal)
        toggleSubButton.setTitleColor(UIColor(white: 0.65, alpha: 1.0), for: .normal)
        toggleSubButton.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        toggleSubButton.addTarget(self, action: #selector(toggleSubtitleBox), for: .touchUpInside)

        subtitleContainer.addSubview(userSubtitleLabel)
        subtitleContainer.addSubview(geminiSubtitleLabel)
        view.addSubview(toggleSubButton)

        NSLayoutConstraint.activate([
            subtitleContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            subtitleContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            subtitleContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -92),

            userSubtitleLabel.topAnchor.constraint(equalTo: subtitleContainer.topAnchor, constant: 12),
            userSubtitleLabel.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor, constant: 14),
            userSubtitleLabel.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor, constant: -14),

            geminiSubtitleLabel.topAnchor.constraint(equalTo: userSubtitleLabel.bottomAnchor, constant: 6),
            geminiSubtitleLabel.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor, constant: 14),
            geminiSubtitleLabel.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor, constant: -14),
            geminiSubtitleLabel.bottomAnchor.constraint(equalTo: subtitleContainer.bottomAnchor, constant: -12),

            toggleSubButton.bottomAnchor.constraint(equalTo: subtitleContainer.topAnchor, constant: -4),
            toggleSubButton.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor, constant: -4)
        ])
    }

    private func setupFloatingPillBar() {
        pillBar.translatesAutoresizingMaskIntoConstraints = false
        pillBar.backgroundColor = UIColor(red: 20/255, green: 22/255, blue: 34/255, alpha: 0.95)
        pillBar.layer.cornerRadius = 32
        pillBar.layer.borderWidth = 1
        pillBar.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        view.addSubview(pillBar)

        configurePillButton(micButton, title: "🎙️ Mic", action: #selector(handleMicTap))
        configurePillButton(modeButton, title: "✋ Thủ công", action: #selector(handleModeTap))
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
            pillBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
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

    // MARK: - Xử lý Nút bấm

    @objc private func handleOrbTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if liveService.state == .disconnected {
            liveService.connect()
        } else {
            liveService.finishUserTurnManually()
        }
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
        toggleSubButton.setTitle(isSubtitleHidden ? "Hiện phụ đề" : "Ẩn chữ", for: .normal)
    }

    @objc private func openSettings() {
        let alert = UIAlertController(
            title: "Cài đặt Gemini Live",
            message: "Nhập API Key từ Google AI Studio và tùy chỉnh giọng đọc (Puck, Charon, Kore, Fenrir, Aoede).",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Gemini API Key (AIzaSy...)"
            tf.text = self.liveService.apiKey
            tf.isSecureTextEntry = true
        }
        alert.addTextField { tf in
            tf.placeholder = "Tên giọng (Aoede / Puck / Kore)"
            tf.text = self.liveService.voiceName
        }
        alert.addTextField { tf in
            tf.placeholder = "System Prompt"
            tf.text = self.liveService.systemPrompt
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu & Kết nối", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.liveService.apiKey = alert.textFields?[0].text ?? ""
            let voice = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !voice.isEmpty { self.liveService.voiceName = voice }
            let prompt = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
            statusBadge.setTitle("🟣 Gemini đang suy nghĩ...", for: .normal)
            orbHintLabel.text = "Đang xử lý..."
        case .geminiSpeaking:
            statusBadge.setTitle("🔵 Gemini đang trả lời", for: .normal)
            orbHintLabel.text = "Gemini đang nói\n(Chạm để ngắt lời)"
        case .muted:
            statusBadge.setTitle("🔴 Đang tắt Mic", for: .normal)
            orbHintLabel.text = "Đã tắt Mic"
        }
    }

    // MARK: - Camera & Tiết kiệm tài nguyên khi Chạy nền (Khóa màn hình)

    private func startCamera() {
        cameraQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
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
        // Khi bấm nút nguồn tắt màn hình bỏ túi quần: tắt dựng hình 60fps & Camera để không bị iOS 12 đóng băng, giữ nguyên đàm thoại
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

// MARK: - Delegate Nhận Trạng thái & Phụ đề

extension LiveViewController: GeminiLiveServiceDelegate {
    func didChangeState(_ state: LiveState) {
        updateUIForState(state)
    }

    func didUpdateAudioLevel(_ level: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            self?.targetAudioLevel = level
        }
    }

    func didUpdateTranscript(userText: String?, geminiText: String?) {
        if let u = userText {
            userSubtitleLabel.text = "Bạn: \(u)"
        }
        if let g = geminiText {
            geminiSubtitleLabel.text = "Gemini: \(g)"
        }
    }

    func didEncounterError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.geminiSubtitleLabel.text = "⚠️ \(message)"
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
        guard now - lastFrameSentTime >= 1.0 else { return } // 1 khung hình / giây
        lastFrameSentTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
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
