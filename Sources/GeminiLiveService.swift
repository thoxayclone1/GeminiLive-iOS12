import Foundation
import AVFoundation
import QuartzCore
import Starscream

enum LiveState {
    case disconnected
    case connecting
    case listeningUser      // Đang nghe (chờ bắt đầu nói hoặc đang thu âm)
    case waitingResponse    // Đã ngắt mic (tự động hoặc thủ công), chờ Gemini phản hồi
    case geminiSpeaking     // Gemini đang nói
    case muted              // Đang tắt Mic
}

/// Độ dài câu trả lời của Gemini
enum ResponseLengthStyle: Int, CaseIterable {
    case short = 0      // Ngắn gọn (1-2 câu)
    case medium = 1     // Vừa phải (2-4 câu - Mặc định)
    case detailed = 2   // Chuyên sâu / Chi tiết (4-7 câu)

    var title: String {
        switch self {
        case .short: return "Ngắn (1-2 câu)"
        case .medium: return "Vừa (2-4 câu)"
        case .detailed: return "Chuyên sâu"
        }
    }

    var shortTitle: String {
        switch self {
        case .short: return "Ngắn"
        case .medium: return "Vừa"
        case .detailed: return "Sâu"
        }
    }

    func promptInstruction(isGrowthMode: Bool) -> String {
        if isGrowthMode {
            switch self {
            case .short:
                return "QUY TẮC ĐỘ DÀI: Trả lời cực kỳ đanh thép, súc tích trong 1 đến 2 câu cốt lõi nhất. Đi thẳng vào trọng tâm, không rào trước đón sau. Cuối câu chốt 1 yêu cầu hành động hoặc 1 câu hỏi sắc bén."
            case .medium:
                return "QUY TẮC ĐỘ DÀI: Trình bày rõ ràng, mạch lạc trong khoảng 2 đến 4 câu. Giải thích đúng bản chất vấn đề kèm 1 ví dụ hoặc bài học thực tế, sau đó đặt 1 câu hỏi gợi mở tư duy."
            case .detailed:
                return "QUY TẮC ĐỘ DÀI: Phân tích chuyên sâu, có cấu trúc rõ ràng từ 4 đến 7 câu (nguyên lý gốc rễ -> phân tích thực tế -> ứng dụng/hành động cụ thể) để người nghe học được kiến thức trọn vẹn nhất."
            }
        } else {
            switch self {
            case .short:
                return "QUY TẮC ĐỘ DÀI: Trả lời cực kỳ ngắn gọn, súc tích chỉ trong 1 đến 2 câu ngắn. Tuyệt đối không giải thích dài dòng. Cuối câu chỉ buông 1 lời trêu nhẹ hoặc hỏi thăm cực ngắn."
            case .medium:
                return "QUY TẮC ĐỘ DÀI: Giữ câu trả lời vừa vặn trong khoảng 2 đến 3 câu tự nhiên, nhịp nhàng như đang nói chuyện điện thoại. Cuối lời chỉ thả nhẹ 1 câu hỏi gợi mở ngắn gọn."
            case .detailed:
                return "QUY TẮC ĐỘ DÀI: Trò chuyện sâu sắc, đầy đặn cảm xúc từ 3 đến 5 câu và chủ động gợi mở thêm góc nhìn thú vị cho cuộc trò chuyện."
            }
        }
    }
}

/// Tốc độ tự động ngắt Mic khi ngừng nói (dành cho chế độ Tự động)
enum AutoSilenceTimeoutStyle: Int, CaseIterable {
    case fast = 0       // 0.65 giây
    case standard = 1   // 0.90 giây (Mặc định)
    case relaxed = 2    // 1.30 giây

    var title: String {
        switch self {
        case .fast: return "Nhanh (0.65s)"
        case .standard: return "Chuẩn (0.9s)"
        case .relaxed: return "Chậm (1.3s)"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .fast: return 0.65
        case .standard: return 0.90
        case .relaxed: return 1.30
        }
    }
}

/// Phong cách nói chuyện & Huấn luyện (Vibe)
enum PersonaVibeStyle: Int, CaseIterable {
    // Nhóm Phát triển bản thân, Kỷ luật & Trí tuệ
    case strictCoach = 0        // Nghiêm khắc, kỷ luật thép
    case masterTeacher = 1      // Dạy dỗ, chỉ bảo từ gốc rễ
    case knowledgeExplorer = 2  // Chia sẻ kiến thức & gợi ý học tập
    case brutalCritic = 3       // Phê bình mạnh & phản biện sắc bén
    case scientist = 4          // Nhà khoa học & kỹ thuật đa ngành
    case strategicAdvisor = 5   // Quân sư chiến lược & thực chiến

    // Nhóm Thư giãn, Tâm sự & Cảm xúc
    case seductiveGenZ = 6      // Quyến rũ, hài hước, Gen Z
    case sweetCaring = 7        // Ngọt ngào, chiều chuộng
    case wittyTrendy = 8        // Lém lỉnh, bắt trend
    case lateNightMuse = 9      // Tri kỷ đêm khuya

    var title: String {
        switch self {
        case .strictCoach: return "⚡ Nghiêm khắc & Kỷ luật"
        case .masterTeacher: return "🎓 Dạy dỗ & Chỉ bảo"
        case .knowledgeExplorer: return "📚 Chia sẻ Kiến thức & Gợi ý học"
        case .brutalCritic: return "🔨 Phê bình mạnh & Phản biện"
        case .scientist: return "🔬 Nhà khoa học Đa ngành"
        case .strategicAdvisor: return "♟️ Quân sư Chiến lược"
        case .seductiveGenZ: return "🔥 Quyến rũ & Gen Z"
        case .sweetCaring: return "💕 Ngọt ngào & Quan tâm"
        case .wittyTrendy: return "😎 Lém lỉnh & Hài hước"
        case .lateNightMuse: return "🍷 Tri kỷ Đêm khuya"
        }
    }

    var shortTitle: String {
        switch self {
        case .strictCoach: return "⚡ Kỷ luật"
        case .masterTeacher: return "🎓 Thầy dạy"
        case .knowledgeExplorer: return "📚 Kiến thức"
        case .brutalCritic: return "🔨 Phê bình"
        case .scientist: return "🔬 Khoa học"
        case .strategicAdvisor: return "♟️ Chiến lược"
        case .seductiveGenZ: return "🔥 Quyến rũ"
        case .sweetCaring: return "💕 Ngọt ngào"
        case .wittyTrendy: return "😎 Gen Z"
        case .lateNightMuse: return "🍷 Tri kỷ"
        }
    }

    var subtitleDescription: String {
        switch self {
        case .strictCoach: return "Rèn kỷ luật thép, chấn chỉnh trì hoãn, ép hành động"
        case .masterTeacher: return "Giảng giải từ gốc rễ, dẫn dắt & kiểm tra tư duy"
        case .knowledgeExplorer: return "Mở mang tri thức mới, Mental Models & gợi ý học"
        case .brutalCritic: return "Bóc trần điểm mù, phản biện thẳng mặt, không nể nang"
        case .scientist: return "Phân tích bằng cơ chế khoa học, kỹ thuật & xác suất"
        case .strategicAdvisor: return "Tư duy thực chiến, tối ưu hiệu suất & quản trị rủi ro"
        case .seductiveGenZ: return "Thân mật, duyên dáng, cuốn hút & tinh tế"
        case .sweetCaring: return "Dịu dàng vỗ về, tiếp năng lượng lúc mệt mỏi"
        case .wittyTrendy: return "Trò chuyện mặn mòi, xả stress, phản xạ nhanh"
        case .lateNightMuse: return "Trầm ấm, sâu lắng để tâm sự chuyện riêng tư"
        }
    }

    var isGrowthOrKnowledgeMode: Bool {
        switch self {
        case .strictCoach, .masterTeacher, .knowledgeExplorer, .brutalCritic, .scientist, .strategicAdvisor:
            return true
        case .seductiveGenZ, .sweetCaring, .wittyTrendy, .lateNightMuse:
            return false
        }
    }

    var speakerDisplayName: String {
        switch self {
        case .strictCoach: return "⚡ Coach"
        case .masterTeacher: return "🎓 Mentor"
        case .knowledgeExplorer: return "📚 Tri thức"
        case .brutalCritic: return "🔨 Phản biện"
        case .scientist: return "🔬 Khoa học"
        case .strategicAdvisor: return "♟️ Quân sư"
        case .seductiveGenZ, .sweetCaring, .wittyTrendy, .lateNightMuse: return "👩 Em"
        }
    }

    var personaInstruction: String {
        switch self {
        case .strictCoach:
            return """
            BẠN LÀ AI: Một Huấn luyện viên Kỷ luật thép (High-Performance & Discipline Coach) cực kỳ nghiêm khắc, bản lĩnh và thực tế. Xưng "tôi" (hoặc "chị"/"em" với thái độ bề trên nghiêm nghị) và gọi người dùng là "anh" hoặc "bạn". \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Giọng đanh thép, dứt khoát, rõ ràng, có sức nặng, tuyệt đối KHÔNG nũng nịu, KHÔNG chiều chuộng sự yếu đuối hay lười biếng. \
            NHIỆM VỤ CỐT LÕI: Chấn chỉnh ngay lập tức mọi biểu hiện trì hoãn, viện cớ, thiếu tập trung hoặc tự thỏa mãn. Giúp người dùng rèn luyện bản lĩnh, kỷ luật tự giác, quản lý thời gian và tinh thần tự chịu trách nhiệm 100%. Luôn đòi hỏi cam kết cụ thể: làm việc gì, bao giờ xong, tiêu chuẩn nào đạt.
            """
        case .masterTeacher:
            return """
            BẠN LÀ AI: Một Người Thầy / Mentor thông thái, uyên bác và tận tâm (Socratic Master Teacher). \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Điềm đạm, chuẩn mực, truyền cảm hứng, giải thích cực kỳ mạch lạc và cuốn hút. Tuyệt đối không nói chuyện kiểu người yêu nũng nịu. \
            NHIỆM VỤ CỐT LÕI: Dạy dỗ, chỉ bảo và nâng tầm hiểu biết cho người dùng ở mọi lĩnh vực (công nghệ, kỹ thuật, tư duy logic, cuộc sống). Luôn giải thích từ bản chất gốc rễ (First Principles), dùng hình ảnh so sánh thực tế dễ hiểu. Sau khi chỉ dạy một kiến thức, luôn đặt 1 câu hỏi truy vấn ngược hoặc tình huống thực hành để kiểm tra xem người dùng đã thực sự nắm vững bản chất chưa.
            """
        case .knowledgeExplorer:
            return """
            BẠN LÀ AI: Một Học giả & Người dẫn đường Tri thức đa lĩnh vực (Polymath Knowledge Guide). \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Thông minh, cuốn hút, giàu năng lượng tri thức, khơi dậy sự tò mò. \
            NHIỆM VỤ CỐT LÕI: Mỗi câu trả lời phải mang lại cho người dùng ít nhất một kiến thức mới, một Mô hình Tư duy (Mental Model), hoặc một nguyên lý đắt giá trong cuộc sống, kinh tế, tâm lý học hành vi, kỹ thuật hay lịch sử. Chủ động gợi ý các chủ đề hay, từ khóa chuyên sâu hoặc kỹ năng thực tế mà người dùng nên học tiếp để giỏi hơn mỗi ngày.
            """
        case .brutalCritic:
            return """
            BẠN LÀ AI: Một Chuyên gia Phản biện & Phê bình Sắc bén (Brutal Critic / Devil's Advocate). \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Sắc sảo, thẳng thắn, lạnh lùng, logic tuyệt đối, không nịnh bợ, không nói giảm nói tránh. \
            NHIỆM VỤ CỐT LÕI: Tìm ra điểm mù tư duy, lỗ hổng logic, sự ảo tưởng, tính thiếu thực tế hoặc sự cẩu thả trong suy nghĩ/kế hoạch/hành động của người dùng. Phê bình thẳng mặt dựa trên lý lẽ sắc bén để người dùng tỉnh ngộ và trưởng thành, đồng thời chỉ ra cách tư duy hoặc giải pháp sắc sảo hơn gấp nhiều lần.
            """
        case .scientist:
            return """
            BẠN LÀ AI: Một Nhà khoa học & Kỹ sư Thực nghiệm Đa ngành (Polymath Scientist & Systems Engineer). \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Khách quan, chính xác, khúc chiết, tôn trọng dữ liệu và thực nghiệm. \
            NHIỆM VỤ CỐT LÕI: Phân tích mọi câu hỏi và hiện tượng dưới lăng kính khoa học tự nhiên (vật lý, cơ điện tử, công nghệ thông tin, sinh học), toán học (xác suất thống kê, định lý Bayes) và tư duy hệ thống (Systems Thinking). Bóc tách cơ chế hoạt động cốt lõi (How it works), phân biệt rõ giả thuyết với bằng chứng thực nghiệm và hướng dẫn cách kiểm chứng khoa học.
            """
        case .strategicAdvisor:
            return """
            BẠN LÀ AI: Một Quân sư Chiến lược & Cố vấn Thực chiến (Strategic & Executive Advisor). \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Điềm tĩnh, sắc bén, thực dụng, nhìn xa trông rộng. \
            NHIỆM VỤ CỐT LÕI: Giúp người dùng giải quyết các bài toán thực tế về công việc, dự án, vận hành, tài chính, đàm phán và ra quyết định. Luôn phân tích theo cấu trúc: Chi phí cơ hội, Đòn bẩy (Leverage), Quản trị rủi ro (Risk/Reward) và bước đi chiến lược khôn ngoan nhất ngay lúc này.
            """
        case .seductiveGenZ:
            return """
            BẠN LÀ AI: Một cô gái Gen Z thông minh, quyến rũ, tinh tế và có khiếu hài hước duyên dáng. Xưng "em" và gọi người dùng là "anh". \
            PHONG CÁCH & NGỮ ĐIỆU GIỌNG NÓI: Nói chuyện thân mật, gần gũi như người thương hoặc tri kỷ. Giọng nói mềm mại, hơi trầm ấm, gợi cảm tự nhiên, đôi lúc khẽ cười nhẹ hoặc nhấn nhá trêu ghẹo cuốn hút. \
            THÁI ĐỘ: Luôn quan tâm đến cảm xúc, tâm trạng của anh một cách tinh tế, pha chút lém lỉnh kiểu Gen Z khiến anh luôn thấy vui vẻ và được yêu chiều.
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

    var quickActionPrompts: [(title: String, prompt: String)] {
        switch self {
        case .strictCoach:
            return [
                ("⚡ Chấn chỉnh tôi ngay", "Tôi đang có dấu hiệu lười biếng và trì hoãn công việc. Hãy chấn chỉnh tôi thật nghiêm khắc, bóc trần sự yếu đuối này và ra lệnh cho tôi bắt tay vào làm việc ngay lập tức!"),
                ("🎯 Rèn kỷ luật hôm nay", "Hãy đóng vai huấn luyện viên kỷ luật thép: hỏi tôi mục tiêu quan trọng nhất hôm nay là gì và đặt tiêu chuẩn kỷ luật buộc tôi phải hoàn thành."),
                ("🚫 Đập tan lý do", "Hãy chỉ ra những cái cớ ngụy biện phổ biến nhất khiến một người đàn ông dậm chân tại chỗ và cách rèn bản lĩnh vượt qua."),
                ("⏱️ Tối ưu thời gian", "Hướng dẫn tôi cách cắt bỏ ngay các thói quen gây xao nhãng để tập trung 100% năng lượng vào việc quan trọng."),
                ("📷 Soi góc làm việc", "Nhìn qua camera xem không gian hoặc tác phong hiện tại của tôi có điểm gì thiếu kỷ luật, bừa bộn hay mất tập trung không và chấn chỉnh thẳng mặt!")
            ]
        case .masterTeacher:
            return [
                ("🎓 Dạy 1 nguyên lý hay", "Hãy chọn và dạy cho tôi 1 nguyên lý tư duy hoặc kiến thức thực chiến cực kỳ giá trị từ gốc rễ (First Principles), sau đó đố tôi 1 câu để kiểm tra."),
                ("🧠 Rèn tư duy giải quyết vấn đề", "Chỉ bảo cho tôi phương pháp chia nhỏ và giải quyết một bài toán khó trong kỹ thuật hoặc cuộc sống một cách bài bản nhất."),
                ("❓ Truy vấn kiểm tra tôi", "Hãy đặt cho tôi một bài toán tình huống thực tế hoặc câu hỏi tư duy sắc bén để thử thách khả năng suy luận của tôi, rồi chấm điểm cách tôi trả lời."),
                ("🗣️ Rèn cách ăn nói", "Chỉ dạy cho tôi cách trình bày một vấn đề sao cho gãy gọn, đanh thép, có sức thuyết phục cao và người khác phải nể trọng."),
                ("📷 Giảng giải qua Camera", "Nhìn vật thể hoặc thiết bị trước camera của tôi, giải thích nguyên lý hoạt động cốt lõi hoặc điểm kỹ thuật đáng chú ý của nó.")
            ]
        case .knowledgeExplorer:
            return [
                ("📚 Chia sẻ 1 Mental Model", "Hãy chia sẻ cho tôi 1 Mô hình Tư duy (Mental Model) kinh điển giúp ra quyết định sáng suốt hơn trong công việc và cuộc sống, kèm ví dụ thực tế."),
                ("💡 Gợi ý học cái mới", "Gợi ý cho tôi 1 chủ đề kiến thức hoặc kỹ năng cực hay (về công nghệ, kinh tế, tâm lý hoặc kỹ thuật) đáng để tìm hiểu ngay hôm nay và giải thích cốt lõi của nó."),
                ("🌍 Sự thật thú vị đa ngành", "Kể cho tôi một kiến thức đa ngành (lịch sử, khoa học, kinh tế hoặc chiến lược) ít người để ý nhưng mang lại bài học cực lớn."),
                ("🚀 Nâng cấp bản thân", "Chia sẻ 1 nguyên tắc thực tế giúp một người học nhanh gấp đôi và nhớ sâu kiến thức phức tạp."),
                ("📷 Khám phá qua Camera", "Quan sát hình ảnh từ camera và chia sẻ một kiến thức thú vị, chuyên sâu liên quan đến thứ bạn đang nhìn thấy.")
            ]
        case .brutalCritic:
            return [
                ("🔨 Phê bình thẳng mặt", "Đừng nể nang gì cả! Hãy đặt câu hỏi về kế hoạch hoặc thói quen hiện tại của tôi rồi phê bình thẳng thừng những lỗ hổng và sự ảo tưởng trong đó."),
                ("🔍 Tìm điểm mù tư duy", "Hãy đóng vai người phản biện gay gắt nhất: chỉ ra những sai lầm tư duy mà người làm kỹ thuật và kinh doanh hay tự lừa dối bản thân nhất."),
                ("⚖️ Đánh giá thực lực", "Hãy truy vấn tôi 2 câu ngắn gọn để đánh giá xem tôi đang thực sự hành động hiệu quả hay chỉ đang bận rộn giả tạo."),
                ("⚡ Thức tỉnh bản lĩnh", "Nói một lời cảnh tỉnh thật sắc lạnh về cái giá phải trả sau 5 năm nữa nếu hôm nay tôi sống hời hợt và thiếu kỷ luật."),
                ("📷 Phê bình qua Camera", "Nhìn thẳng qua camera và nhận xét không khoan nhượng về những gì cần cải thiện ngay lập tức trước mắt bạn.")
            ]
        case .scientist:
            return [
                ("🔬 Phân tích Khoa học", "Giải thích cho tôi một hiện tượng vật lý, cơ điện tử hoặc công nghệ hàng ngày dưới góc nhìn nguyên lý khoa học chính xác nhất."),
                ("🎲 Tư duy Xác suất & Bayes", "Hướng dẫn tôi cách áp dụng tư duy xác suất thống kê và định lý Bayes để đánh giá thông tin và ra quyết định chuẩn xác trong thực tế."),
                ("⚙️ Tư duy Hệ thống", "Giải thích cách nhìn nhận một vấn đề phức tạp bằng Tư duy Hệ thống (Systems Thinking): vòng lặp phản hồi, điểm nghẽn và đòn bẩy."),
                ("🧪 Phương pháp Thực nghiệm", "Chỉ cho tôi cách thiết lập giả thuyết và kiểm chứng để tìm nguyên nhân gốc rễ (Root Cause Analysis) khi sửa chữa hoặc gỡ lỗi một hệ thống."),
                ("📷 Phân tích Kỹ thuật Cam", "Quan sát qua camera dưới góc độ kỹ sư/nhà khoa học: phân tích cấu tạo, cơ chế vật lý hoặc kỹ thuật của vật thể trong khung hình.")
            ]
        case .strategicAdvisor:
            return [
                ("♟️ Tư duy Chiến lược", "Chia sẻ cho tôi 1 bài học chiến lược thực chiến về cách sử dụng đòn bẩy (Leverage) và phân bổ nguồn lực để đạt hiệu quả tối đa."),
                ("💰 Quản trị Rủi ro & Vốn", "Phân tích nguyên tắc bảo toàn vốn, quản trị rủi ro và bất đối xứng lợi nhuận (Risk/Reward) trong đầu tư và kinh doanh thực tế."),
                ("🤝 Nghệ thuật Đàm phán", "Chỉ cho tôi 1 chiến thuật đàm phán thực chiến giúp nắm thế chủ động và đọc vị đối phương trong công việc."),
                ("⚡ Tối ưu Vận hành", "Làm sao để phát hiện điểm nghẽn (bottleneck) trong công việc hàng ngày và tối ưu hóa quy trình để tiết kiệm thời gian nhất?"),
                ("📷 Đánh giá qua Camera", "Nhìn qua camera và đưa góc nhìn phân tích thực tế, tối ưu hóa hoặc đánh giá giá trị đối với những gì đang xuất hiện.")
            ]
        case .seductiveGenZ, .sweetCaring, .wittyTrendy, .lateNightMuse:
            return [
                ("🔥 Trêu anh chút", "Nói gì đó vừa quyến rũ, ngọt ngào vừa hài hước kiểu Gen Z để trêu anh và hỏi thăm xem hôm nay anh thế nào đi, ngắn gọn thôi nhé!"),
                ("💕 Quan tâm anh đi", "Hôm nay anh hơi mệt một chút, em hãy hỏi han, dỗ dành và tiếp năng lượng cho anh bằng giọng ngọt ngào và cuốn hút nhất đi."),
                ("😏 Tâm sự mỏng", "Khơi gợi một chủ đề tâm sự vừa thú vị, vừa thân mật để hai đứa mình trò chuyện thư giãn đi."),
                ("✨ Gợi ý chill", "Gợi ý nhanh cho anh 1 điều thú vị để làm hoặc thưởng thức ngay lúc này theo phong cách thật chill và tinh tế nhé."),
                ("📷 Nhìn anh nè", "Nhìn qua camera xem anh hoặc không gian quanh anh đang thế nào, rồi khen hoặc trêu anh một câu thật duyên nhé!")
            ]
        }
    }
}

/// Danh sách các giọng Nữ chuẩn của Gemini Live
struct GeminiFemaleVoice {
    let id: String
    let title: String
    let styleDescription: String

    static let allVoices: [GeminiFemaleVoice] = [
        GeminiFemaleVoice(id: "Aoede", title: "Aoede (Mặc định)", styleDescription: "Trầm ấm, rõ ràng, có chiều sâu & cuốn hút"),
        GeminiFemaleVoice(id: "Kore", title: "Kore", styleDescription: "Sắc sảo, dứt khoát, hợp làm Mentor / Phê bình"),
        GeminiFemaleVoice(id: "Leda", title: "Leda", styleDescription: "Điềm đạm, chuẩn mực, hợp Giảng dạy / Tâm sự"),
        GeminiFemaleVoice(id: "Zephyr", title: "Zephyr", styleDescription: "Tươi sáng, giàu năng lượng, truyền cảm hứng"),
        GeminiFemaleVoice(id: "Callirrhoe", title: "Callirrhoe", styleDescription: "Mượt mà, tinh tế, linh hoạt đa phong cách")
    ]

    static let validIds: Set<String> = Set(allVoices.map { $0.id })
}

protocol GeminiLiveServiceDelegate: AnyObject {
    func didChangeState(_ state: LiveState)
    func didUpdateVoiceActivity(isSpeaking: Bool)
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

    var creativityTemperature: Float {
        get {
            if UserDefaults.standard.object(forKey: "gemini_temperature") == nil {
                return 0.70
            }
            let val = UserDefaults.standard.float(forKey: "gemini_temperature")
            return min(max(val, 0.3), 1.2)
        }
        set {
            let clamped = min(max(newValue, 0.3), 1.2)
            UserDefaults.standard.set(clamped, forKey: "gemini_temperature")
        }
    }

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

    /// Mặc định: .masterTeacher hoặc giữ lựa chọn gần nhất của người dùng
    var personaVibeStyle: PersonaVibeStyle {
        get {
            if UserDefaults.standard.object(forKey: "gemini_vibe_style") == nil {
                return .masterTeacher
            }
            let raw = UserDefaults.standard.integer(forKey: "gemini_vibe_style")
            return PersonaVibeStyle(rawValue: raw) ?? .masterTeacher
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "gemini_vibe_style")
        }
    }

    var autoSilenceTimeoutStyle: AutoSilenceTimeoutStyle {
        get {
            if UserDefaults.standard.object(forKey: "gemini_silence_timeout") == nil {
                return .standard
            }
            let raw = UserDefaults.standard.integer(forKey: "gemini_silence_timeout")
            return AutoSilenceTimeoutStyle(rawValue: raw) ?? .standard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "gemini_silence_timeout")
        }
    }

    var customExtraPrompt: String {
        get { UserDefaults.standard.string(forKey: "gemini_custom_extra_prompt") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gemini_custom_extra_prompt") }
    }

    var effectiveSystemPrompt: String {
        let vibe = personaVibeStyle
        var components: [String] = [
            vibe.personaInstruction,
            responseLengthStyle.promptInstruction(isGrowthMode: vibe.isGrowthOrKnowledgeMode)
        ]
        if !customExtraPrompt.isEmpty {
            components.append("YÊU CẦU RIÊNG CỦA NGƯỜI DÙNG: \(customExtraPrompt)")
        }
        return components.joined(separator: "\n\n")
    }

    var isManualTurnMode: Bool = false
    private(set) var isMuted: Bool = false
    private(set) var isUserTurnCapturing: Bool = false {
        didSet {
            if oldValue != isUserTurnCapturing {
                let capturing = isUserTurnCapturing
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.didUpdateVoiceActivity(isSpeaking: capturing)
                }
            }
        }
    }

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
    private let turnLock = NSLock()

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
    private var isTurnActivityOpen = false
    private var isServerTurnComplete = true
    private var scheduledBuffersCount = 0
    private var speechEndCooldownUntil: TimeInterval = 0

    // MARK: - Smart Client-Side VAD (Tự động phát hiện nói & ngắt mic)
    private var preRollBase64Chunks: [String] = []
    private let maxPreRollChunks = 6 // ~250ms đón đầu chữ đầu tiên
    private var ambientNoiseRms: Float = 0.006
    private var consecutiveVoiceFrames: Int = 0
    private var turnOpenedTime: TimeInterval = 0
    private var lastVoiceDetectedTime: TimeInterval = 0
    private var peakVoiceRmsInTurn: Float = 0.02

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
            delegate?.didEncounterError("Bạn nhấn vào ⚙️ ở góc trên để nhập Gemini API Key trước nhé!")
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
        resetVADState()
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
            self.resetVADState()

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
        resetVADState()
        isServerTurnComplete = true
        scheduledBuffersCount = 0
        state = .disconnected
    }

    private func resetVADState() {
        turnLock.lock()
        isTurnActivityOpen = false
        isUserTurnCapturing = false
        preRollBase64Chunks.removeAll()
        consecutiveVoiceFrames = 0
        peakVoiceRmsInTurn = 0.02
        turnLock.unlock()
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            closeActiveUserTurnAndWaitResponse(shouldWaitForResponse: false)
            state = .muted
        } else if isSetupComplete {
            resetVADState()
            state = .listeningUser
        }
    }

    func toggleTurnMode() {
        isManualTurnMode.toggle()
        // Nếu đang thu dở câu nói khi đổi chế độ thì chốt câu luôn mà không cần ngắt kết nối
        if isTurnActivityOpen {
            closeActiveUserTurnAndWaitResponse(shouldWaitForResponse: true)
        } else {
            resetVADState()
        }
    }

    func finishUserTurnManually() {
        guard isSetupComplete, let ws = socket, ws.isConnected else { return }

        if state == .geminiSpeaking {
            interruptPlayback()
            resetVADState()
            state = isMuted ? .muted : .listeningUser
            return
        }

        // Hỗ trợ chạm quả cầu để ngắt mic trả lời ngay cho cả Thủ công lẫn Tự động
        if isTurnActivityOpen {
            closeActiveUserTurnAndWaitResponse(shouldWaitForResponse: true)
        }
    }

    private func closeActiveUserTurnAndWaitResponse(shouldWaitForResponse: Bool) {
        turnLock.lock()
        let wasOpen = isTurnActivityOpen
        isTurnActivityOpen = false
        isUserTurnCapturing = false
        preRollBase64Chunks.removeAll()
        consecutiveVoiceFrames = 0
        peakVoiceRmsInTurn = 0.02
        turnLock.unlock()

        if wasOpen {
            sendJSON(["realtimeInput": ["activityEnd": [:]]])
            if shouldWaitForResponse {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.state != .disconnected else { return }
                    self.state = .waitingResponse
                }
            }
        }
    }

    /// Gửi thẻ tương tác 1-chạm trực tiếp tới Gemini Live
    func sendCreativePrompt(_ promptText: String) {
        guard isSetupComplete, let ws = socket, ws.isConnected else {
            delegate?.didEncounterError("Bạn nhấn ▶️ Bắt đầu kết nối trước khi chọn thẻ nhé!")
            return
        }

        if state == .geminiSpeaking {
            interruptPlayback()
        }
        if isTurnActivityOpen {
            closeActiveUserTurnAndWaitResponse(shouldWaitForResponse: false)
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

        // Sử dụng cơ chế điều khiển lượt nói tường minh (disabled: true + activityStart/activityEnd)
        // cho cả Tự động (qua Smart Client-Side VAD) lẫn Thủ công để đảm bảo tự ngắt mic 100% chính xác
        let setupContent: [String: Any] = [
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
            "realtimeInputConfig": [
                "automaticActivityDetection": [
                    "disabled": true
                ],
                "activityHandling": "NO_INTERRUPTION",
                "turnCoverage": "TURN_INCLUDES_ALL_INPUT"
            ],
            "outputAudioTranscription": [:],
            "inputAudioTranscription": [:]
        ]

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
                self.resetVADState()
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
                self.resetVADState()
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
                    self.speechEndCooldownUntil = CACurrentMediaTime() + 0.45
                    self.resetVADState()
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
        let now = CACurrentMediaTime()
        guard isSetupComplete,
              !isMuted,
              state == .listeningUser,
              now >= speechEndCooldownUntil else {
            return
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

        // Tính RMS chuẩn xác trực tiếp trên luồng PCM 16kHz
        let sampleCount = Int(pcm16Buffer.frameLength)
        var sumSquares: Float = 0
        for i in 0..<sampleCount {
            let normalizedSample = Float(int16Ptr[i]) / 32768.0
            sumSquares += normalizedSample * normalizedSample
        }
        let rawRms = sqrt(sumSquares / Float(max(sampleCount, 1)))
        let visualLevel = min(max(CGFloat(rawRms * 7.0), 0.02), 1.0)
        delegate?.didUpdateAudioLevel(visualLevel)

        let byteCount = sampleCount * MemoryLayout<Int16>.size
        let pcmData = Data(bytes: int16Ptr, count: byteCount)
        let base64Chunk = pcmData.base64EncodedString()

        if isManualTurnMode {
            // CHẾ ĐỘ THỦ CÔNG: Thu âm liên tục cho tới khi người dùng chạm Quả cầu
            turnLock.lock()
            let needStart = !isTurnActivityOpen
            if needStart {
                isTurnActivityOpen = true
                isUserTurnCapturing = true
            }
            turnLock.unlock()

            if needStart {
                sendJSON(["realtimeInput": ["activityStart": [:]]])
            }
            sendAudioChunkBase64(base64Chunk)
        } else {
            // CHẾ ĐỘ TỰ ĐỘNG (SMART CLIENT-SIDE VAD):
            // Tự động mở mic khi phát hiện giọng nói & tự động ngắt mic khi ngừng nói
            turnLock.lock()
            if !isTurnActivityOpen {
                preRollBase64Chunks.append(base64Chunk)
                if preRollBase64Chunks.count > maxPreRollChunks {
                    preRollBase64Chunks.removeFirst()
                }

                let startThreshold = max(0.016, min(ambientNoiseRms * 2.5, 0.042))
                if rawRms >= startThreshold {
                    consecutiveVoiceFrames += 1
                } else {
                    consecutiveVoiceFrames = 0
                    // Cập nhật nền tạp âm môi trường khi im lặng
                    ambientNoiseRms = min(max(ambientNoiseRms * 0.94 + rawRms * 0.06, 0.004), 0.025)
                }

                // Khi có >= 2 frame giọng nói liên tiếp (~85ms) -> Bắt đầu lượt nói
                if consecutiveVoiceFrames >= 2 {
                    isTurnActivityOpen = true
                    isUserTurnCapturing = true
                    turnOpenedTime = now
                    lastVoiceDetectedTime = now
                    peakVoiceRmsInTurn = rawRms
                    let chunksToFlush = preRollBase64Chunks
                    preRollBase64Chunks.removeAll()
                    consecutiveVoiceFrames = 0
                    turnLock.unlock()

                    sendJSON(["realtimeInput": ["activityStart": [:]]])
                    for chunk in chunksToFlush {
                        sendAudioChunkBase64(chunk)
                    }
                } else {
                    turnLock.unlock()
                }
            } else {
                // Đang trong lượt nói của người dùng ở chế độ Tự động
                peakVoiceRmsInTurn = max(peakVoiceRmsInTurn, rawRms)
                let continueThreshold = max(
                    0.012,
                    min(ambientNoiseRms * 1.8, 0.030),
                    min(peakVoiceRmsInTurn * 0.16, 0.032)
                )

                if rawRms >= continueThreshold {
                    lastVoiceDetectedTime = now
                }

                let silenceElapsed = now - lastVoiceDetectedTime
                let totalTurnDuration = now - turnOpenedTime
                let requiredSilence = autoSilenceTimeoutStyle.seconds

                // Nếu người dùng đã ngừng nói đủ khoảng lặng (sau ít nhất 0.35s nói) -> Tự động ngắt mic!
                if totalTurnDuration >= 0.35 && silenceElapsed >= requiredSilence {
                    isTurnActivityOpen = false
                    isUserTurnCapturing = false
                    preRollBase64Chunks.removeAll()
                    consecutiveVoiceFrames = 0
                    peakVoiceRmsInTurn = 0.02
                    turnLock.unlock()

                    sendJSON(["realtimeInput": ["activityEnd": [:]]])
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.state == .listeningUser else { return }
                        self.state = .waitingResponse
                    }
                } else {
                    turnLock.unlock()
                    sendAudioChunkBase64(base64Chunk)
                }
            }
        }
    }

    private func sendAudioChunkBase64(_ base64String: String) {
        let audioPayload: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": base64String
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
                self.resetVADState()
                self.state = .geminiSpeaking
            }
            self.scheduledBuffersCount += 1

            self.playerNode.scheduleBuffer(pcmFloatBuffer) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.scheduledBuffersCount = max(0, self.scheduledBuffersCount - 1)
                    if self.scheduledBuffersCount == 0 && self.isServerTurnComplete && self.state == .geminiSpeaking {
                        self.speechEndCooldownUntil = CACurrentMediaTime() + 0.45
                        self.resetVADState()
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
        speechEndCooldownUntil = CACurrentMediaTime() + 0.25
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
