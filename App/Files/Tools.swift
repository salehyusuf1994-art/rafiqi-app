import SwiftUI
import AVKit
import Translation
import PDFKit
import PhotosUI

// MARK: - الأدوات المتاحة لكل نوع ملف

enum ToolKind: String, Identifiable, CaseIterable {
    // صوت وفيديو
    case trim, split, toM4A, toMP3, toWAV, ringtone, speed, adjustAudio, transcribe, translate, removeMusic, removeVocals
    // فيديو
    case mute, replaceAudio, rotate, crop, text, compress, gif, reverse
    // صور
    case removeBG, sticker, ocr, barcode, compressImage, convertImage, rotateImage, toPDF, withAudio, scanImage
    // مستندات
    case pdfText, editText, pdfPages, docToPDF, print
    // عام للصوت والفيديو
    case metadata, burnSubs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trim: return L("قص المقطع")
        case .split: return L("تقسيم المقطع")
        case .toM4A: return L("تحويل إلى M4A (صوت)")
        case .toWAV: return L("تحويل إلى WAV")
        case .toMP3: return L("تحويل إلى MP3")
        case .removeMusic: return L("إزالة الموسيقى (إبقاء الصوت البشري)")
        case .removeVocals: return L("إزالة الصوت البشري (إبقاء الموسيقى)")
        case .ringtone: return L("تحويل إلى نغمة رنين")
        case .speed: return L("تغيير السرعة")
        case .adjustAudio: return L("تعديل الصوت (المستوى والتلاشي)")
        case .transcribe: return L("تفريغ المقطع إلى نص")
        case .translate: return L("ترجمة المقطع")
        case .mute: return L("كتم صوت الفيديو")
        case .replaceAudio: return L("استبدال صوت الفيديو")
        case .rotate: return L("تدوير الفيديو")
        case .crop: return L("قص حدود الفيديو")
        case .text: return L("الكتابة على الفيديو")
        case .compress: return L("تقليل حجم الفيديو")
        case .gif: return L("تحويل إلى GIF")
        case .reverse: return L("عكس الفيديو")
        case .removeBG: return L("إزالة الخلفية")
        case .sticker: return L("تحويل إلى ملصق (واتساب)")
        case .ocr: return L("استخراج النص من الصورة")
        case .barcode: return L("قراءة الباركود ورمز QR")
        case .compressImage: return L("ضغط الصورة")
        case .convertImage: return L("تغيير صيغة الصورة")
        case .rotateImage: return L("تدوير الصورة")
        case .toPDF: return L("تحويل إلى PDF")
        case .withAudio: return L("دمج الصورة مع صوت (فيديو)")
        case .pdfText: return L("استخراج النص من PDF")
        case .editText: return L("تحرير النص")
        case .pdfPages: return L("تعديل الصفحات (ترتيب، حذف، تدوير)")
        case .docToPDF: return L("تحويل إلى PDF")
        case .print: return L("طباعة")
        case .scanImage: return L("تحسين كمستند ممسوح (قص، فلاتر، توقيع)")
        case .metadata: return L("البيانات والصورة المصغّرة")
        case .burnSubs: return L("دمج الترجمة داخل الفيديو")
        }
    }

    var icon: String {
        switch self {
        case .trim: return "scissors"
        case .split: return "rectangle.split.3x1"
        case .toM4A: return "waveform"
        case .toWAV: return "waveform.path"
        case .toMP3: return "music.note"
        case .removeMusic: return "music.note.slash"
        case .removeVocals: return "person.wave.2.fill"
        case .ringtone: return "bell"
        case .speed: return "gauge.with.dots.needle.67percent"
        case .adjustAudio: return "slider.horizontal.3"
        case .transcribe: return "text.bubble"
        case .translate: return "character.bubble"
        case .mute: return "speaker.slash"
        case .replaceAudio: return "music.note.list"
        case .rotate: return "rotate.right"
        case .crop: return "crop"
        case .text: return "textformat"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .gif: return "photo.stack"
        case .reverse: return "backward"
        case .removeBG: return "person.crop.rectangle"
        case .sticker: return "face.smiling"
        case .ocr: return "text.viewfinder"
        case .barcode: return "qrcode.viewfinder"
        case .compressImage: return "arrow.down.right.and.arrow.up.left"
        case .convertImage: return "arrow.triangle.2.circlepath"
        case .rotateImage: return "rotate.right"
        case .toPDF: return "doc.richtext"
        case .withAudio: return "photo.badge.plus"
        case .pdfText: return "doc.text.magnifyingglass"
        case .editText: return "square.and.pencil"
        case .pdfPages: return "doc.on.doc"
        case .docToPDF: return "doc.richtext"
        case .print: return "printer"
        case .scanImage: return "doc.viewfinder"
        case .metadata: return "photo.badge.checkmark"
        case .burnSubs: return "captions.bubble"
        }
    }

    static func sections(for it: FileItem) -> [(String, [ToolKind])] {
        switch it.kind {
        case .video:
            return [
                (L("تعديل الفيديو"), [.trim, .split, .text, .crop, .rotate, .speed, .reverse, .mute, .replaceAudio, .compress, .metadata]),
                (L("التحويل"), [.toMP3, .toM4A, .gif, .ringtone]),
                (L("الذكاء الاصطناعي"), [.removeMusic, .removeVocals]),
                (L("النص والترجمة"), [.transcribe, .translate] + (VideoController.subtitles(for: it.url).isEmpty ? [] : [.burnSubs])),
            ]
        case .audio:
            return [
                (L("تعديل الصوت"), [.trim, .split, .adjustAudio, .speed, .metadata]),
                (L("التحويل"), [.toMP3, .toM4A, .toWAV, .ringtone]),
                (L("الذكاء الاصطناعي"), [.removeMusic, .removeVocals]),
                (L("النص"), [.transcribe]),
            ]
        case .image:
            return [
                (L("أدوات الصورة"), [.scanImage, .removeBG, .sticker, .ocr, .barcode, .rotateImage]),
                (L("التحويل"), [.compressImage, .convertImage, .toPDF, .withAudio, .print]),
            ]
        case .document:
            var t: [ToolKind] = []
            if it.ext == "pdf" { t.append(contentsOf: [.pdfPages, .pdfText]) }
            if ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "html", "htm", "pages", "key", "numbers", "csv", "md"].contains(it.ext) { t.append(.docToPDF) }
            t.append(.print)
            if ["txt", "md", "srt", "vtt", "csv", "json"].contains(it.ext) { t.append(.editText) }
            return t.isEmpty ? [] : [(L("أدوات المستند"), t)]
        default:
            return []
        }
    }

    /// أدوات تعمل مباشرة بلا إعدادات
    var direct: Bool { [.docToPDF, .toM4A, .toMP3, .toWAV, .mute, .rotate, .gif, .removeBG, .rotateImage, .toPDF, .burnSubs].contains(self) }
}

// MARK: - تشغيل الأداة في صفحة موحّدة (الإعدادات ← التقدّم ← النتيجة)

@MainActor
enum ToolRunner {
    /// وضع الفحص فقط (-splitTest): نغمة ٩٠ ثانية في «إدارة الملفات» وتُفتح عليها أداة «تقسيم المقطع»
    static func splitSelfTest() {
        let u = FileStore.shared.root.appendingPathComponent("اختبار التقسيم.m4a")
        Task.detached {
            try? FileManager.default.removeItem(at: u)
            let rate = 44_100.0, frames = AVAudioFrameCount(rate * 90)
            if let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
               let file = try? AVAudioFile(forWriting: u, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1]),
               let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames), let p = buf.floatChannelData?[0] {
                buf.frameLength = frames
                for i in 0..<Int(frames) { p[i] = 0.2 * sinf(2 * .pi * 440 * Float(i) / Float(rate)) }
                try? file.write(from: buf)
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { FileStore.shared.touch(); run(.split, on: u, toast: { _ in }) }
        }
    }

    static func run(_ t: ToolKind, on url: URL, toast: @escaping (String) -> Void) {
        // ننتظر إغلاق قائمة الإجراءات ثم نعرض صفحة الأداة
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            if t == .print { FilePrinter.print([url]); return }
            if t == .scanImage, let img = UIImage(contentsOfFile: url.path) {
                let src = ScanProcessor.detectQuad(img).map { ScanProcessor.perspective(img, $0) } ?? img
                let host = UIHostingController(rootView: ScanEditorHost(pages: [ScanPage(source: src)]).font(Theme.f(.body))
                    .environment(\.layoutDirection, Lang.dir).digitsLocale())
                host.overrideUserInterfaceStyle = .dark
                host.modalPresentationStyle = .fullScreen
                FileOpener.mark(host, [url])
                FileOpener.top()?.present(host, animated: true)
                return
            }
            let host = UIHostingController(rootView: ToolHost(tool: t, url: url).font(Theme.f(.body))
                .environment(\.layoutDirection, Lang.dir).digitsLocale())
            host.overrideUserInterfaceStyle = .dark
            if let s = host.sheetPresentationController { s.detents = [.large()]; s.prefersGrabberVisible = true }
            FileOpener.mark(host, [url])
            FileOpener.top()?.present(host, animated: true)
        }
    }
}

struct ToolHost: View {
    let tool: ToolKind
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var progress: Double = 0
    @State private var running = false
    @State private var job: Task<Void, Never>?
    @State private var result: URL?
    @State private var text: String?
    @State private var codes: [String] = []
    @State private var error: String?
    // الإعدادات
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var total: Double = 0
    @State private var speed: Double = 1.5
    @State private var aspect: CGFloat = 1
    @State private var overlay = ""
    @State private var pos = 2
    @State private var fontK: CGFloat = 0.07
    @State private var color = Color.white
    @State private var quality = 1
    @State private var imgQuality: Double = 0.7
    @State private var maxSide: Double = 2048
    @State private var format = "jpg"
    @State private var gain: Double = 0
    @State private var fadeIn = false
    @State private var fadeOut = false
    @State private var lang = "ar-SA"
    @State private var audioPick: URL?
    @State private var keepOriginal = false
    @State private var target = "en"
    @State private var cues: [(Double, Double, String)] = []
    @State private var player: AVPlayer?
    @State private var editBody = ""
    /// ترميز الملف الأصلي (يُحفظ به)؛ nil = تعذّرت قراءته فلا يُسمح بالحفظ حتى لا يُمسح محتواه
    @State private var editEncoding: String.Encoding? = nil
    @State private var metaTitle = ""
    @State private var metaArtist = ""
    @State private var metaAlbum = ""
    @State private var cover: UIImage?
    @State private var coverItem: PhotosPickerItem?
    // التقسيم
    @State private var splitSec: Double = 600
    @State private var splitCustom = false
    @State private var splitMin = ""
    @State private var splitSecs = ""
    @State private var splitExact = false
    @State private var splitParts: [URL] = []
    @State private var splitFolder: URL?
    @State private var splitStep: (Int, Int)?
    @AppStorage("sep.engine") private var sepEngine = "high"
    /// فصل سابق منقطع لهذا الملف (نسبته) — «إكمال» يتابع من حيث توقف
    @State private var sepPending: Double?
    @State private var runStart = Date()
    @State private var batteryAsk = false
    @State private var mediaSeconds: Double = 0
    @ObservedObject private var sepStore = SepModelStore.shared
    @FocusState private var splitFocus: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.f(.subheadline)).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading).glassCard(padding: 14)
                    }
                    if !splitParts.isEmpty { splitCard }
                    else if let result { resultCard(result) }
                    else if let text { textCard(text) }
                    else if !codes.isEmpty { codesCard }
                    else if running || translating { progressCard }
                    else { params; if tool != .pdfPages { runButton } }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .hiddenNavBar()
            // لوحة الأرقام بلا زر إنهاء: «تم» فوقها
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("تم")) { splitFocus = false }.font(Theme.f(.headline)).tint(Theme.gold)
                }
            }
        }
        .task { await prepare() }
        // إغلاق الأداة يوقف المهمة الجارية (لا تبقى تعمل في الخلفية وتسخّن الجوال)
        .onDisappear { player?.pause(); job?.cancel() }
        .modifier(CueTranslator(active: $translating, source: String(lang.prefix(2)), target: target, cues: cues) { out, err in
            translating = false
            if let err { error = err; return }
            let base = url.deletingPathExtension()
            let dir = url.deletingLastPathComponent(), stem = base.lastPathComponent
            // لا نكتب فوق ملف موجود للمستخدم: اسم جديد إن وُجد بنفس الاسم
            try? MediaTools.srt(out).write(to: uniqueFileURL("\(stem).\(target).srt", in: dir), atomically: true, encoding: .utf8)
            // ملف الترجمة الذي يقرؤه المشغّل تلقائيًا — فقط إن لم يكن للفيديو ترجمة أصلًا
            let auto = base.appendingPathExtension("srt")
            if !FileManager.default.fileExists(atPath: auto.path) {
                try? MediaTools.srt(out).write(to: auto, atomically: true, encoding: .utf8)
            }
            FileStore.shared.touch()
            text = out.map(\.2).joined(separator: "\n")
        })
    }

    private var header: some View {
        HStack(spacing: 12) {
            Badge(name: tool.icon, size: 46, active: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: tool.title).font(Theme.f(.headline)).foregroundStyle(.white)
                Text(verbatim: url.lastPathComponent).font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            CircleButton(icon: "xmark", size: 38) { dismiss() }
        }
    }

    // MARK: الإعدادات لكل أداة

    @ViewBuilder private var params: some View {
        switch tool {
        case .trim, .ringtone:
            trimEditor
        case .split:
            splitEditor
        case .speed:
            card {
                Text(LF("السرعة: %@", ar(String(format: "%g", speed)) + "×")).font(Theme.f(.headline)).foregroundStyle(.white)
                Picker("", selection: $speed) {
                    ForEach([0.25, 0.5, 0.75, 1.25, 1.5, 2, 3], id: \.self) { Text(verbatim: ar(String(format: "%g", $0)) + "×").tag($0) }
                }
                .pickerStyle(.segmented)
                note("أقل من ١ يبطّئ المقطع، وأكثر من ١ يسرّعه. تبقى نبرة الصوت طبيعية.")
            }
        case .crop:
            card {
                Text("النسبة").font(Theme.f(.headline)).foregroundStyle(.white)
                Picker("", selection: $aspect) {
                    Text(verbatim: "1:1").tag(CGFloat(1))
                    Text(verbatim: "9:16").tag(CGFloat(9.0 / 16))
                    Text(verbatim: "16:9").tag(CGFloat(16.0 / 9))
                    Text(verbatim: "4:5").tag(CGFloat(4.0 / 5))
                    Text(verbatim: "4:3").tag(CGFloat(4.0 / 3))
                }
                .pickerStyle(.segmented)
                note("يُقص الفيديو من المنتصف بالنسبة المختارة (١:١ للمربع، و٩:١٦ للقصص والريلز).")
            }
        case .text:
            card {
                TextField(L("اكتب النص"), text: $overlay, axis: .vertical).lineLimit(1...4)
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                Picker("", selection: $pos) {
                    Text("أعلى").tag(0); Text("الوسط").tag(1); Text("أسفل").tag(2)
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("الحجم").foregroundStyle(Theme.sub)
                    Slider(value: $fontK, in: 0.04...0.14).tint(Theme.gold)
                    ColorPicker("", selection: $color).labelsHidden()
                }
            }
        case .compress:
            card {
                Text("الجودة").font(Theme.f(.headline)).foregroundStyle(.white)
                Picker("", selection: $quality) {
                    Text("متوسطة").tag(0); Text("٩٦٠×٥٤٠").tag(1); Text("٦٤٠×٤٨٠").tag(2)
                }
                .pickerStyle(.segmented)
                note("كلما قلّت الجودة صغر حجم الملف.")
            }
        case .adjustAudio:
            card {
                Text(LF("مستوى الصوت: %@ ديسيبل", ar(String(format: "%+.0f", gain)))).font(Theme.f(.headline)).foregroundStyle(.white)
                Slider(value: $gain, in: -20...20, step: 1).tint(Theme.gold)
                Toggle(L("تلاشٍ في البداية (٣ ثوانٍ)"), isOn: $fadeIn).tint(Theme.gold)
                Toggle(L("تلاشٍ في النهاية (٣ ثوانٍ)"), isOn: $fadeOut).tint(Theme.gold)
            }
        case .transcribe, .translate:
            card {
                Text("لغة الكلام في المقطع").font(Theme.f(.headline)).foregroundStyle(.white)
                Picker("", selection: $lang) {
                    Text("العربية").tag("ar-SA"); Text("English").tag("en-US")
                }
                .pickerStyle(.segmented)
                // الترجمة دائمًا إلى اللغة الأخرى (الترجمة إلى لغة الكلام نفسها تفشل برسالة مضلِّلة)
                .onChange(of: lang) { _, l in target = l.hasPrefix("en") ? "ar" : "en" }
                if tool == .translate {
                    Text("الترجمة إلى").font(Theme.f(.headline)).foregroundStyle(.white).padding(.top, 6)
                    Picker("", selection: $target) {
                        Text("English").tag("en"); Text("العربية").tag("ar")
                    }
                    .pickerStyle(.segmented)
                    note("تُحفظ الترجمة ملف ترجمة (SRT) بجانب الفيديو، وتظهر تلقائيًا عند تشغيله في رفيقي.")
                } else {
                    note("يُفرَّغ الكلام على جهازك، ويُحفظ نصًا (TXT) وملف ترجمة (SRT) بجانب المقطع.")
                }
            }
        case .replaceAudio, .withAudio:
            card {
                Text("اختر الملف الصوتي").font(Theme.f(.headline)).foregroundStyle(.white)
                AudioChooser(selected: $audioPick)
                if tool == .replaceAudio { Toggle(L("إبقاء صوت الفيديو الأصلي ومزجه"), isOn: $keepOriginal).tint(Theme.gold) }
            }
        case .compressImage:
            card {
                Text(LF("الجودة: %@٪", ar(Int(imgQuality * 100)))).font(Theme.f(.headline)).foregroundStyle(.white)
                Slider(value: $imgQuality, in: 0.3...0.95).tint(Theme.gold)
                Text("أقصى بُعد").font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
                Picker("", selection: $maxSide) {
                    Text(verbatim: ar("4096")).tag(4096.0); Text(verbatim: ar("2048")).tag(2048.0); Text(verbatim: ar("1280")).tag(1280.0); Text(verbatim: ar("800")).tag(800.0)
                }
                .pickerStyle(.segmented)
            }
        case .convertImage:
            card {
                Picker("", selection: $format) {
                    Text(verbatim: "JPG").tag("jpg"); Text(verbatim: "PNG").tag("png"); Text(verbatim: "HEIC").tag("heic")
                }
                .pickerStyle(.segmented)
            }
        case .editText:
            TextEditor(text: $editBody)
                .font(Theme.f(.body)).scrollContentBackground(.hidden)
                .frame(minHeight: 320).padding(10)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        case .sticker:
            card {
                note("يُقص العنصر البارز في الصورة ويوضع على خلفية شفافة بمقاس ملصقات واتساب (٥١٢×٥١٢).")
                note("لإضافته في واتساب: احفظه في «الصور»، ثم افتح الملصقات في أي محادثة ← «إنشاء ملصق» واختر الصورة.")
            }
        case .reverse:
            card { note("يُعكس الفيديو كاملًا بدون الصوت. المقاطع الطويلة تأخذ وقتًا أطول.") }
        case .removeMusic, .removeVocals:
            card {
                note(tool == .removeMusic
                     ? "يفصل الذكاء الاصطناعي الصوت البشري ويحذف الموسيقى والإيقاعات. تتم المعالجة على جوالك بدون إنترنت، والمقاطع الطويلة تأخذ بضع دقائق."
                     : "يحذف الذكاء الاصطناعي الصوت البشري ويبقي الموسيقى. تتم المعالجة على جوالك بدون إنترنت، والمقاطع الطويلة تأخذ بضع دقائق.")
                if !Separator.available { note("نموذج الفصل غير مضمّن في هذه النسخة.") }
            }
            card { SepEngineCard() }
                .onChange(of: sepEngine) { _, _ in refreshPending() }
            if highTooLong {
                card {
                    Label(LF("المقطع %@، والنموذج عالي الدقة يفصل حتى ٣٠ دقيقة. اختر «السريع» (حتى ٤ ساعات)، أو قسّمه بأداة «تقسيم» إلى أجزاء.", lengthWords(mediaSeconds)),
                          systemImage: "clock.badge.exclamationmark")
                        .font(Theme.f(.subheadline, .semibold)).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let f = sepPending {
                card {
                    Label(LF("فصل غير مكتمل لهذا الملف (%@٪). «إكمال» يتابع من حيث توقف.", ar(Int(f * 100))), systemImage: "arrow.clockwise.circle.fill")
                        .font(Theme.f(.subheadline, .semibold)).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                    pill("البدء من جديد", "trash") {
                        SepLong.discard(url, keep: tool == .removeMusic ? .vocals : .music, engine: sepEngine == "fast" ? "fast" : "high")
                        refreshPending()
                    }
                }
            }
        case .pdfPages:
            PDFPagesEditor(url: url) { dismiss() }
        case .metadata:
            card {
                field(L("العنوان"), $metaTitle)
                field(L("الفنان أو القارئ"), $metaArtist)
                field(L("الألبوم"), $metaAlbum)
                HStack(spacing: 12) {
                    if let cover { Image(uiImage: cover).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    PhotosPicker(selection: $coverItem, matching: .images) {
                        Label(cover == nil ? L("اختيار صورة مصغّرة") : L("تغيير الصورة"), systemImage: "photo").font(Theme.f(.subheadline, .bold)).foregroundStyle(Theme.gold)
                    }
                }
                note("تظهر الصورة والعنوان في شاشة القفل والمشغّلات الأخرى.")
            }
            .onChange(of: coverItem) { _, it in
                Task { if let d = try? await it?.loadTransferable(type: Data.self) { cover = UIImage(data: d) } }
            }
        default:
            EmptyView()
        }
    }

    private var trimEditor: some View {
        card {
            if let player, MediaTools.isVideo(url) {
                VideoPlayer(player: player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            HStack {
                Text(verbatim: durationText(start)).font(Theme.font(14, .bold).monospacedDigit()).foregroundStyle(Theme.gold)
                Spacer()
                Text(LF("المدة: %@", durationText(max(0, end - start)))).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                Spacer()
                Text(verbatim: durationText(end)).font(Theme.font(14, .bold).monospacedDigit()).foregroundStyle(Theme.gold)
            }
            .environment(\.layoutDirection, .leftToRight)
            VStack(alignment: .leading, spacing: 2) {
                Text("البداية").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                Slider(value: Binding(get: { start }, set: { start = min($0, end - 0.5); seekPreview(start) }), in: 0...max(0.5, total)).tint(Theme.gold)
                Text("النهاية").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                Slider(value: Binding(get: { end }, set: {
                    var v = max($0, start + 0.5)
                    if tool == .ringtone { v = min(v, start + 40) }
                    end = v; seekPreview(end - 1)
                }), in: 0...max(0.5, total)).tint(Theme.gold)
            }
            .environment(\.layoutDirection, .leftToRight)
            Button {
                guard let player else { return }
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600)); player.play()
                let stopAt = end
                Task { while let t = player.currentItem?.currentTime().seconds, t < stopAt, player.rate > 0 { try? await Task.sleep(nanoseconds: 100_000_000) }; player.pause() }
            } label: { Label("استمع للجزء المحدد", systemImage: "play.circle.fill").font(Theme.f(.subheadline, .bold)).foregroundStyle(Theme.gold) }
            if tool == .ringtone {
                note("النغمة حتى ٤٠ ثانية بصيغة M4R. لتعيينها نغمة رنين: افتح «فتح باستخدام» ← GarageBand، أو انسخها لجهاز كمبيوتر عبر Finder.")
            }
        }
    }

    private func seekPreview(_ t: Double) { player?.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }

    private var runButton: some View {
        Button {
            if needsBatteryWarning { batteryAsk = true } else { job = Task { await go() } }
        } label: {
            Text(tool == .editText ? L("حفظ") : (isSeparation && sepPending != nil ? L("إكمال") : L("تنفيذ"))).font(Theme.f(.headline)).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gold))
        }
        .disabled(runBlocked)
        .opacity(runBlocked ? 0.5 : 1)
        .confirmationDialog(LF("البطارية %@٪ والمقطع طويل", ar(batteryPercent)), isPresented: $batteryAsk, titleVisibility: .visible) {
            Button("ابدأ على أي حال") { job = Task { await go() } }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("الفصل الطويل يستهلك البطارية بسرعة. الأفضل توصيل الجوال بالشاحن. وإن نفدت البطارية يكمل لاحقًا من حيث توقف.")
        }
    }

    private var isSeparation: Bool { tool == .removeMusic || tool == .removeVocals }

    private var batteryPercent: Int { Int((UIDevice.current.batteryLevel * 100).rounded()) }

    /// تنبيه قبل فصل أطول من ٢٠ دقيقة والبطارية أقل من ٣٠٪ وليست على الشاحن
    private var needsBatteryWarning: Bool {
        guard isSeparation, mediaSeconds > 20 * 60 else { return false }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let lvl = UIDevice.current.batteryLevel
        return lvl >= 0 && lvl < 0.3 && UIDevice.current.batteryState == .unplugged
    }

    private func refreshPending() {
        guard isSeparation else { return }
        sepPending = SepLong.pending(url, keep: tool == .removeMusic ? .vocals : .music, engine: sepEngine == "fast" ? "fast" : "high")
    }

    /// الوقت المتبقي من سرعة الفصل الفعلية
    private var etaText: String? {
        let el = Date().timeIntervalSince(runStart)
        guard progress > 0.02, progress < 0.995, el > 20 else { return nil }
        let rem = el * (1 - progress) / progress
        if rem < 60 { return L("أقل من دقيقة") }
        return lengthWords(Double(Int(rem / 60 + 0.5) * 60))
    }

    private var runBlocked: Bool {
        (tool == .text && overlay.trimmingCharacters(in: .whitespaces).isEmpty)
            || ((tool == .replaceAudio || tool == .withAudio) && audioPick == nil)
            || (tool == .split && splitCount < 2)
            // عالي الدقة يحتاج النموذج منزّلًا (أو اختيار «السريع»)
            || ((tool == .removeMusic || tool == .removeVocals) && sepEngine == "high" && sepStore.state != .ready)
            || highTooLong
    }

    /// النموذج عالي الدقة: حتى ٣٠ دقيقة على الجوال
    private var highTooLong: Bool {
        isSeparation && sepEngine == "high" && mediaSeconds > Separator.highMaxSeconds + 1
    }

    private var progressCard: some View {
        card {
            ProgressView(value: progress).tint(Theme.gold)
            if tool == .split, let st = splitStep {
                Text(LF("جزء %@ من %@", ar(st.0), ar(st.1))).font(Theme.f(.headline)).foregroundStyle(.white)
            }
            Text(LF("جارٍ التنفيذ… %@٪", ar(Int(progress * 100)))).font(Theme.f(.subheadline)).foregroundStyle(.white)
            if isSeparation, let eta = etaText {
                Text(LF("باقي تقريبًا %@", eta)).font(Theme.f(.headline)).foregroundStyle(Theme.gold)
            }
            note("الشاشة تبقى مضاءة حتى ينتهي. أبقِ التطبيق مفتوحًا.")
            if isSeparation {
                note("إن ألغيت أو انقطع الفصل، تكمله لاحقًا من حيث توقف.")
            }
            if tool == .split || isSeparation {
                pill("إلغاء", "xmark") { job?.cancel() }
            }
        }
    }

    // MARK: التقسيم

    /// المدد الجاهزة (تظهر فقط الأقصر من المقطع حتى ينتج جزءان على الأقل)
    private static let splitPresets: [Double] = [60, 120, 300, 600, 900, 1200, 1800, 3600]

    private func splitLabel(_ s: Double) -> String {
        switch s {
        case 1800: return L("نصف ساعة")
        case 3600: return L("ساعة")
        default: return minutesText(Int(s / 60))
        }
    }

    /// المدة بالكلمات: «١٠ دقائق»، «نصف ساعة»، «ساعة و٢٠ دقيقة»، «دقيقتان و٣٠ ثانية»
    private func lengthWords(_ s: Double) -> String {
        let t = max(1, Int(s.rounded()))
        if t == 1800 { return L("نصف ساعة") }
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        var parts: [String] = []
        if h > 0 { parts.append(countText(h, one: "ساعة", two: "ساعتان", few: "ساعات", many: "ساعة", en: h == 1 ? "hour" : "hours")) }
        if m > 0 { parts.append(minutesText(m)) }
        if sec > 0 { parts.append(sec == 2 && !Lang.isEN ? "ثانيتان" : secondsText(sec)) }
        return parts.joined(separator: Lang.isEN ? " " : " و")
    }

    /// يقبل الأرقام العربية والإنجليزية
    private func number(_ t: String) -> Int {
        Int(String(t.compactMap { $0.wholeNumberValue.map { Character(String($0)) } }).prefix(5)) ?? 0
    }

    private var splitSeconds: Double {
        splitCustom ? Double(number(splitMin) * 60 + number(splitSecs)) : splitSec
    }
    private var splitRanges: [ClosedRange<Double>] { MediaTools.splitRanges(total: total, every: splitSeconds) }
    private var splitCount: Int { let n = splitRanges.count; return n <= MediaTools.maxSplitParts ? n : 0 }

    private var splitEditor: some View {
        let presets = Self.splitPresets.filter { $0 < total }
        let ranges = splitRanges
        return card {
            Text(LF("مدة المقطع: %@", durationText(total))).font(Theme.f(.subheadline)).foregroundStyle(Theme.sub)
            Text("طول كل جزء").font(Theme.f(.headline)).foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(presets, id: \.self) { v in
                    Chip(title: splitLabel(v), on: !splitCustom && splitSec == v) { splitCustom = false; splitSec = v }
                        .accessibilityAddTraits(!splitCustom && splitSec == v ? .isSelected : [])
                }
                Chip(title: "مدة أخرى", on: splitCustom) { splitCustom = true }
                    .accessibilityAddTraits(splitCustom ? .isSelected : [])
            }
            if splitCustom {
                HStack(spacing: 10) {
                    splitField("دقائق", $splitMin)
                    splitField("ثوانٍ", $splitSecs)
                }
            }
            if ranges.count > MediaTools.maxSplitParts {
                Label(LF("عدد الأجزاء كبير جدًا (الحد %@ جزء). اختر مدة أطول.", ar(MediaTools.maxSplitParts)), systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.f(.subheadline)).foregroundStyle(.orange)
            } else if ranges.count >= 2, let last = ranges.last {
                let lastLen = last.upperBound - last.lowerBound
                let partsText = countText(ranges.count, one: "جزء واحد", two: "جزأين", few: "أجزاء", many: "جزءًا", en: "parts")
                VStack(alignment: .leading, spacing: 4) {
                    Text(LF("سيُقسَّم إلى %@، مدة كل جزء %@.", partsText, lengthWords(splitSeconds)))
                        .font(Theme.f(.headline)).foregroundStyle(Theme.gold)
                    if abs(lastLen - splitSeconds) >= 1 {
                        Text(LF("والجزء الأخير %@.", lengthWords(lastLen))).font(Theme.f(.subheadline)).foregroundStyle(.white)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if total > 0 && (!splitCustom || splitSeconds >= 1) {
                note("المدة المختارة أطول من المقطع أو تساويه، فلن يُقسَّم.")
            } else if total <= 0 {
                note("تعذّرت قراءة مدة المقطع.")
            }
            Toggle(L("قص دقيق بالثانية (أبطأ)"), isOn: $splitExact).tint(Theme.gold)
            note(splitExact
                 ? "يُعاد ترميز كل جزء ليبدأ وينتهي على الثانية بالضبط. يستغرق وقتًا أطول."
                 : "يُقسَّم بدون إعادة ضغط، فيبقى بنفس الجودة وبسرعة عالية. قد يتقدّم موضع القص أو يتأخر ثانية أو ثانيتين.")
            note("تُحفظ الأجزاء مرتبة في مجلد جديد بجانب الملف الأصلي.")
        }
    }

    private func splitField(_ title: String, _ v: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(title)).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            TextField(ar("0"), text: v).keyboardType(.numberPad).multilineTextAlignment(.center)
                .focused($splitFocus)
                .font(Theme.font(18, .bold).monospacedDigit())
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .accessibilityLabel(L(title))
        }
    }

    private var splitCard: some View {
        card {
            Label("تم بنجاح", systemImage: "checkmark.seal.fill").font(Theme.f(.headline)).foregroundStyle(Color(red: 0.45, green: 0.80, blue: 0.62))
            Text(LF("قُسِّم المقطع إلى %@.", countText(splitParts.count, one: "جزء واحد", two: "جزأين", few: "أجزاء", many: "جزءًا", en: "parts")))
                .font(Theme.f(.subheadline)).foregroundStyle(.white)
            if let f = splitFolder {
                Label(f.lastPathComponent, systemImage: "folder.fill").font(Theme.f(.subheadline)).foregroundStyle(Theme.gold)
            }
            HStack(spacing: 10) {
                pill("تشغيل", "play.fill") {
                    let ps = splitParts; dismiss()
                    Task { try? await Task.sleep(nanoseconds: 400_000_000); if let f = ps.first { FileOpener.open(f, siblings: ps) } }
                }
                pill("مشاركة", "square.and.arrow.up") { FileOpener.share(splitParts) }
                if splitParts.allSatisfy({ FileKind.of($0, isDir: false) == .video }) {
                    pill("إلى الصور", "square.and.arrow.down") { let ps = splitParts; Task { _ = await FileStore.shared.saveToPhotos(ps) } }
                }
            }
            note("حُفظت الأجزاء مرتبة في مجلد جديد بجانب الملف الأصلي.")
        }
    }

    private func resultCard(_ u: URL) -> some View {
        card {
            Label("تم بنجاح", systemImage: "checkmark.seal.fill").font(Theme.f(.headline)).foregroundStyle(Color(red: 0.45, green: 0.80, blue: 0.62))
            Text(verbatim: u.lastPathComponent).font(Theme.f(.subheadline)).foregroundStyle(.white)
            Text(verbatim: sizeText(Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            HStack(spacing: 10) {
                pill("فتح", "play.fill") { let r = u; dismiss(); Task { try? await Task.sleep(nanoseconds: 400_000_000); FileOpener.open(r) } }
                pill("مشاركة", "square.and.arrow.up") { FileOpener.share([u]) }
                if [.image, .video].contains(FileKind.of(u, isDir: false)) {
                    pill("إلى الصور", "square.and.arrow.down") { Task { _ = await FileStore.shared.saveToPhotos([u]) } }
                }
            }
            note("حُفظ الملف في المجلد نفسه بجانب الملف الأصلي.")
            if tool == .removeMusic || tool == .removeVocals, let rep = Roformer.lastReport {
                Label(rep, systemImage: "gauge.with.dots.needle.67percent").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func textCard(_ t: String) -> some View {
        card {
            ScrollView { Text(verbatim: t).font(Theme.f(.body)).foregroundStyle(.white).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 360)
            HStack(spacing: 10) {
                pill("نسخ", "doc.on.doc") { UIPasteboard.general.string = t }
                pill("مشاركة", "square.and.arrow.up") { FileOpener.share([saveText(t)].compactMap { $0 }) }
            }
        }
    }

    private var codesCard: some View {
        card {
            ForEach(codes, id: \.self) { c in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: c).font(Theme.f(.body)).foregroundStyle(.white).textSelection(.enabled)
                    HStack(spacing: 10) {
                        pill("نسخ", "doc.on.doc") { UIPasteboard.general.string = c }
                        if let u = URL(string: c), u.scheme?.hasPrefix("http") == true {
                            pill("فتح الرابط", "safari") { UIApplication.shared.open(u) }
                        }
                    }
                }
            }
        }
    }

    // MARK: عناصر مساعدة

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { c() }.frame(maxWidth: .infinity, alignment: .leading).glassCard(padding: 16)
    }

    private func field(_ title: String, _ v: Binding<String>) -> some View {
        TextField(title, text: v).padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }

    private func note(_ s: String) -> some View {
        Text(L(s)).font(Theme.f(.caption)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L(title), systemImage: icon).font(Theme.f(.subheadline, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func saveText(_ t: String) -> URL? {
        let dest = MediaTools.output(for: url, suffix: L("نص"), ext: "txt")
        return (try? t.write(to: dest, atomically: true, encoding: .utf8)) != nil ? dest : nil
    }

    // MARK: التنفيذ

    private func prepare() async {
        if isSeparation {
            let d = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            mediaSeconds = d.isFinite ? d : 0
            refreshPending()
        }
        if tool == .split {
            let d = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            total = d.isFinite ? d : 0
            // الافتراضي ١٠ دقائق، وإن كان المقطع أقصر فأطول مدة جاهزة تعطي جزأين على الأقل
            if let v = Self.splitPresets.last(where: { $0 <= 600 && $0 < total }) ?? Self.splitPresets.first(where: { $0 < total }) { splitSec = v }
            else { splitCustom = true }
        }
        if tool == .trim || tool == .ringtone {
            let d = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            total = d.isFinite ? d : 0
            end = tool == .ringtone ? min(total, 30) : total
            player = AVPlayer(url: url)
        }
        if tool == .editText {
            if let d = try? Data(contentsOf: url) {
                let arabic = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)))
                // UTF-16 فقط مع علامته (BOM)؛ وإلا العربية القديمة (Windows-1256) — تحفظ البايتات كما هي إن لم يُعدَّل النص
                let bom16 = d.starts(with: [0xFF, 0xFE]) || d.starts(with: [0xFE, 0xFF])
                for enc in (bom16 ? [String.Encoding.utf16] : [String.Encoding.utf8, arabic]) {
                    if let t = String(data: d, encoding: enc) { editBody = t; editEncoding = enc; break }
                }
                if d.isEmpty { editBody = ""; editEncoding = .utf8 }
            }
            if editEncoding == nil { error = L("تعذّرت قراءة نص هذا الملف، فلن يُعدَّل حتى لا يضيع محتواه.") }
        }
        if tool == .metadata {
            let m = await MediaTools.readMetadata(url)
            metaTitle = m.title ?? url.deletingPathExtension().lastPathComponent
            metaArtist = m.artist ?? ""
            metaAlbum = m.album ?? ""
            cover = m.art
        }
        if tool.direct { await go() }
    }

    private func go() async {
        error = nil
        running = true
        progress = 0
        runStart = Date()
        // الشاشة تبقى مضاءة طوال المهمة (فصل الصوت قد يستغرق دقائق)
        KeepAwake.begin()
        let bg = KeepAwake.Background("rafiqi.tool")
        defer { running = false; FileStore.shared.touch(); KeepAwake.end(); bg.finish() }
        let p: (Double) -> Void = { v in Task { @MainActor in progress = v } }
        do {
            switch tool {
            case .trim: result = try await MediaTools.trim(url, start: start, end: end, progress: p)
            case .split:
                splitStep = nil; splitFolder = nil
                splitParts = try await MediaTools.split(url, every: splitSeconds, exact: splitExact,
                    folderReady: { f in Task { @MainActor in splitFolder = f } },
                    part: { i, n in Task { @MainActor in splitStep = (i, n) } },
                    progress: p)
            case .ringtone: result = try await MediaTools.trim(url, start: start, end: min(end, start + 40), ringtone: true, progress: p)
            case .toM4A: result = try await MediaTools.toM4A(url, progress: p)
            case .toWAV: result = try await MediaTools.toWAV(url, progress: p)
            case .toMP3: result = try await MediaTools.toMP3(url, progress: p)
            case .removeMusic, .removeVocals:
                let keep: Separator.Keep = tool == .removeMusic ? .vocals : .music
                Roformer.lastReport = nil
                let video = MediaTools.isVideo(url)
                // يكمل بعد الخروج من التطبيق (iOS 26، على المعالج)، ويرجع لكرت الشاشة عند العودة
                SepContinued.shared.begin(title: tool == .removeMusic ? L("إزالة الموسيقى") : L("إزالة الصوت البشري"), subtitle: url.lastPathComponent)
                var ok = false
                defer { SepContinued.shared.end(success: ok) }
                let engine: Separator.Engine = sepEngine == "fast" ? .builtIn : .roformer
                let sep = try await Separator.run(url, keep: keep, engine: engine, progress: { v in
                    Task { @MainActor in progress = video ? v * 0.97 : v; SepContinued.shared.update(video ? v * 0.97 : v) } })
                let stem = sep.main
                if video {
                    // الصورة تُنسخ كما هي، والصوت الجديد يبدأ من موضع الصوت الأصلي نفسه (مزامنة مطابقة للأصل)
                    let v = try await MediaTools.replaceAudio(url, with: stem, keepOriginal: false, audioStart: sep.audioStart, loop: false,
                                                              progress: { x in Task { @MainActor in progress = 0.97 + x * 0.03 } })
                    try? FileManager.default.removeItem(at: stem)
                    let named = MediaTools.output(for: url, suffix: keep == .vocals ? L("بدون موسيقى") : L("بدون صوت بشري"), ext: v.pathExtension)
                    try? FileManager.default.moveItem(at: v, to: named)
                    result = FileManager.default.fileExists(atPath: named.path) ? named : v
                } else {
                    result = stem
                }
                ok = true
            case .speed: result = try await MediaTools.speed(url, factor: speed, progress: p)
            case .adjustAudio: result = try await MediaTools.adjustAudio(url, gainDB: Float(gain), fadeIn: fadeIn ? 3 : 0, fadeOut: fadeOut ? 3 : 0, progress: p)
            case .mute: result = try await MediaTools.mute(url, progress: p)
            case .rotate: result = try await MediaTools.rotate(url, progress: p)
            case .crop: result = try await MediaTools.crop(url, aspect: aspect, progress: p)
            case .text: result = try await MediaTools.text(url, text: overlay, position: pos, size: fontK, color: UIColor(color), progress: p)
            case .compress:
                let preset = [AVAssetExportPresetMediumQuality, AVAssetExportPreset960x540, AVAssetExportPreset640x480][quality]
                result = try await MediaTools.compress(url, preset: preset, progress: p)
            case .gif: result = try await MediaTools.gif(url, progress: p)
            case .reverse: result = try await MediaTools.reverse(url, progress: p)
            case .replaceAudio:
                guard let a = audioPick else { return }
                result = try await MediaTools.replaceAudio(url, with: a, keepOriginal: keepOriginal, progress: p)
            case .withAudio:
                guard let a = audioPick else { return }
                result = try await MediaTools.imageWithAudio(url, audio: a, progress: p)
            case .transcribe:
                let r = try await MediaTools.transcribe(url, lang: lang, progress: p)
                let base = url.deletingPathExtension()
                let dir = url.deletingLastPathComponent(), stem = base.lastPathComponent
                // ملفات جديدة دائمًا؛ لا يُستبدل نص أو ترجمة موجودة للمستخدم
                try? r.text.write(to: uniqueFileURL("\(stem).txt", in: dir), atomically: true, encoding: .utf8)
                if !r.srt.isEmpty {
                    let auto = base.appendingPathExtension("srt")
                    let dest = FileManager.default.fileExists(atPath: auto.path) ? uniqueFileURL("\(stem).\(lang.prefix(2)).srt", in: dir) : auto
                    try? MediaTools.srt(r.srt).write(to: dest, atomically: true, encoding: .utf8)
                }
                text = r.text
            case .translate:
                let r = try await MediaTools.transcribe(url, lang: lang, progress: { v in Task { @MainActor in progress = v * 0.7 } })
                cues = r.srt
                try await translateCues()
            case .removeBG: result = try await MediaTools.removeBackground(url)
            case .sticker: result = try await MediaTools.sticker(url)
            case .ocr, .pdfText:
                let t = try await MediaTools.recognizeText(url)
                text = t
            // أدوات الصور تعمل في الخلفية: الصور الكبيرة لا تجمّد الواجهة
            case .barcode: let u = url; codes = try await Task.detached(priority: .userInitiated) { try MediaTools.barcodes(u) }.value
            case .compressImage:
                let u = url, q = imgQuality, m = maxSide
                result = try await Task.detached(priority: .userInitiated) { try MediaTools.compressImage(u, quality: q, maxSide: m) }.value
            case .convertImage: let u = url, f = format; result = try await Task.detached(priority: .userInitiated) { try MediaTools.convertImage(u, to: f) }.value
            case .rotateImage: let u = url; result = try await Task.detached(priority: .userInitiated) { try MediaTools.rotateImage(u) }.value
            case .toPDF: let u = url; result = try await Task.detached(priority: .userInitiated) { try MediaTools.imagesToPDF([u]) }.value
            case .metadata:
                result = try await MediaTools.writeMetadata(url, title: metaTitle, artist: metaArtist, album: metaAlbum, art: cover, progress: p)
            case .burnSubs:
                result = try await MediaTools.burnSubtitles(url, cues: VideoController.subtitles(for: url), progress: p)
            case .pdfPages, .print, .scanImage:
                break
            case .docToPDF:
                result = try await DocToPDF.convert(url)
            case .editText:
                guard let enc = editEncoding else { return }
                // يُحفظ بترميزه الأصلي؛ وإن احتوى حروفًا لا يدعمها فبـUTF-8
                if (try? editBody.write(to: url, atomically: true, encoding: enc)) == nil {
                    try editBody.write(to: url, atomically: true, encoding: .utf8)
                }
                dismiss()
            }
        } catch is CancellationError {
            // أُغلقت الأداة: لا رسالة خطأ؛ و«إلغاء» التقسيم يوضّح ما بقي
            if tool == .split, let st = splitStep, st.0 > 1, let f = splitFolder {
                error = LF("أُلغي التقسيم. بقيت الأجزاء المكتملة (%@ من %@) في مجلد «%@».", ar(st.0 - 1), ar(st.1), f.lastPathComponent)
            }
            if isSeparation {
                refreshPending()
                if sepPending != nil { error = L("توقف الفصل وحُفظ تقدّمه. «إكمال» يتابع من حيث توقف.") }
            }
        } catch {
            self.error = error.localizedDescription
            refreshPending()
        }
    }

    /// ترجمة المقطع على الجهاز (iOS 18 فأحدث)
    private func translateCues() async throws {
        guard !cues.isEmpty else { throw ToolError.failed(L("لم يُتعرّف على كلام في المقطع.")) }
        guard #available(iOS 18.0, *) else { throw ToolError.failed(L("الترجمة تحتاج iOS 18 أو أحدث.")) }
        progress = 0.8
        translating = true
    }

    @State private var translating = false
}

/// يترجم جمل المقطع بإطار الترجمة في iOS (على الجهاز)
struct CueTranslator: ViewModifier {
    @Binding var active: Bool
    let source: String
    let target: String
    let cues: [(Double, Double, String)]
    let done: ([(Double, Double, String)], String?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(CueTranslator18(active: $active, source: source, target: target, cues: cues, done: done))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
struct CueTranslator18: ViewModifier {
    @Binding var active: Bool
    let source: String
    let target: String
    let cues: [(Double, Double, String)]
    let done: ([(Double, Double, String)], String?) -> Void
    @State private var config: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: active) { _, on in
                if on {
                    config = TranslationSession.Configuration(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
                }
            }
            .translationTask(config) { session in
                let reqs = cues.enumerated().map { TranslationSession.Request(sourceText: $0.element.2, clientIdentifier: String($0.offset)) }
                do {
                    let res = try await session.translations(from: reqs)
                    var out = cues
                    for r in res { if let i = Int(r.clientIdentifier ?? ""), out.indices.contains(i) { out[i].2 = r.targetText } }
                    await MainActor.run { done(out, nil); config = nil }
                } catch {
                    await MainActor.run { done([], L("تعذّرت الترجمة. نزّل لغة الترجمة من الإعدادات ← التطبيقات ← الترجمة ← اللغات، ثم حاول مرة أخرى.")); config = nil }
                }
            }
    }
}

/// اختيار ملف صوتي من «ملفاتي»
struct AudioChooser: View {
    @Binding var selected: URL?
    @ObservedObject private var store = FileStore.shared
    var body: some View {
        let list = store.deepList(store.root).filter { ($0.kind == .audio || $0.kind == .video) && !store.isTrash($0.url) }
        if list.isEmpty {
            Text("لا توجد ملفات صوتية في «ملفاتي». استورد ملفًا صوتيًا أولًا.").font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
        } else {
            VStack(spacing: 6) {
                ForEach(list.prefix(60)) { f in
                    Button { selected = f.url } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected == f.url ? "checkmark.circle.fill" : "circle").foregroundStyle(selected == f.url ? Theme.gold : Theme.sub)
                            Text(verbatim: f.name).font(Theme.f(.subheadline)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            FileSubtitle(item: f).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - تعديل صفحات PDF: ترتيب وحذف وتدوير ودمج

struct PDFPagesEditor: View {
    let url: URL
    let done: () -> Void
    @State private var doc: PDFDocument?
    @State private var thumbs: [UIImage] = []
    @State private var selected: Set<Int> = []
    @State private var saved = false
    @State private var failed = false
    @State private var saveFailed = false

    var body: some View {
        VStack(spacing: 12) {
            if failed {
                // ملف تالف أو محمي بكلمة مرور: رسالة واضحة بدل انتظار بلا نهاية
                Text("تعذّر فتح ملف PDF (قد يكون تالفًا أو محميًا بكلمة مرور).").font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
            } else if let doc {
                Text(verbatim: pagesText(doc.pageCount) + " · " + L("اضغط لتحديد صفحة أو أكثر")).font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(Array(thumbs.enumerated()), id: \.offset) { i, img in
                        Button { if selected.contains(i) { selected.remove(i) } else { selected.insert(i) } } label: {
                            VStack(spacing: 4) {
                                Image(uiImage: img).resizable().scaledToFit().frame(height: 120)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected.contains(i) ? Theme.gold : Color.white.opacity(0.15), lineWidth: selected.contains(i) ? 3 : 1))
                                Text(verbatim: ar(i + 1)).font(Theme.f(.caption, .bold)).foregroundStyle(selected.contains(i) ? Theme.gold : Theme.sub)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    tool("rotate.right", L("تدوير")) { for i in selected { if let p = doc.page(at: i) { p.rotation = (p.rotation + 90) % 360 } }; refresh() }
                    tool("arrow.up", L("للأمام")) { move(-1) }
                    tool("arrow.down", L("للخلف")) { move(1) }
                    tool("trash", L("حذف")) {
                        for i in selected.sorted(by: >) where doc.pageCount > 1 { doc.removePage(at: i) }
                        selected = []; refresh()
                    }
                }
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.45 : 1)
                Button {
                    if doc.write(to: url) { saved = true; FileStore.shared.touch(); done() } else { saveFailed = true }
                } label: {
                    Text("حفظ التعديلات").font(Theme.f(.headline)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gold))
                }
                Text("للكتابة والتوقيع على الملف: افتحه من «ملفاتي» واضغط زر التعليق (القلم) في الأعلى.")
                    .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            } else {
                ProgressView().tint(Theme.gold)
            }
        }
        .task {
            doc = PDFDocument(url: url)
            if doc == nil || doc?.isLocked == true { doc = nil; failed = true }
            refresh()
        }
        .alert(L("تعذّر حفظ التعديلات"), isPresented: $saveFailed) { Button(L("حسنًا"), role: .cancel) {} }
    }

    private func tool(_ icon: String, _ t: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) { Image(systemName: icon).font(.system(size: 18)); Text(verbatim: t).font(Theme.f(.caption)) }
                .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        }
        .buttonStyle(.plain)
    }

    private func move(_ d: Int) {
        guard let doc, selected.count == 1, let i = selected.first else { return }
        let j = i + d
        guard j >= 0, j < doc.pageCount, let p = doc.page(at: i) else { return }
        doc.removePage(at: i)
        doc.insert(p, at: j)
        selected = [j]
        refresh()
    }

    private func refresh() {
        guard let doc else { return }
        thumbs = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.thumbnail(of: CGSize(width: 200, height: 260), for: .mediaBox) }
    }
}

extension MediaTools {
    /// دمج ملفات PDF بالترتيب
    static func mergePDFs(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw ToolError.failed(L("اختر ملفين على الأقل.")) }
        let out = PDFDocument()
        for u in urls {
            guard let d = PDFDocument(url: u) else { continue }
            for i in 0..<d.pageCount { if let p = d.page(at: i) { out.insert(p, at: out.pageCount) } }
        }
        guard out.pageCount > 0 else { throw ToolError.failed(L("تعذّر الدمج.")) }
        let dest = output(for: first, suffix: L("مدمج"), ext: "pdf")
        guard out.write(to: dest) else { throw ToolError.failed(L("تعذّر الحفظ.")) }
        return dest
    }
}
