import SwiftUI
import VisionKit
import Vision
import PDFKit
import PencilKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ZIPFoundation
import WebKit
import PhotosUI
import AVFoundation

// MARK: - الماسح الضوئي: مسح متعدد الصفحات، هوية، كتاب، باركود، نص، ترجمة — ثم محرر وتصدير

enum ScanMode: String, CaseIterable, Identifiable {
    case document, idCard, book, qr, text, translate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .document: return L("مستند")
        case .idCard: return L("هوية وجواز")
        case .book: return L("كتاب")
        case .qr: return L("QR وباركود")
        case .text: return L("استخراج نص")
        case .translate: return L("مسح وترجمة")
        }
    }
    var icon: String {
        switch self {
        case .document: return "doc.viewfinder"
        case .idCard: return "person.text.rectangle"
        case .book: return "book"
        case .qr: return "qrcode.viewfinder"
        case .text: return "text.viewfinder"
        case .translate: return "character.bubble"
        }
    }
    var hint: String {
        switch self {
        case .document: return L("صفحات متعددة، تُكتشف الحواف ويُعدَّل الميلان تلقائيًا")
        case .idCard: return L("الوجه ثم الظهر، في صفحة A4 واحدة")
        case .book: return L("صفحتا الكتاب المفتوح تُقسمان إلى صفحتين")
        case .qr: return L("قراءة مباشرة من الكاميرا")
        case .text: return L("صوّر الورقة واحصل على نصها")
        case .translate: return L("النص الأصلي والترجمة جنبًا إلى جنب")
        }
    }
}

enum ScanFilter: String, CaseIterable, Identifiable {
    case original, auto, magic, gray, bw, ink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return L("الأصل")
        case .auto: return L("تحسين")
        case .magic: return L("سحري")
        case .gray: return L("رمادي")
        case .bw: return L("أبيض وأسود")
        case .ink: return L("توفير الحبر")
        }
    }
}

struct ScanOverlay: Identifiable, Equatable {
    enum Kind: Equatable { case signature(UIImage), text(String) }
    var id = UUID()
    var kind: Kind
    /// المركز والعرض نسبةً إلى الصفحة
    var center = CGPoint(x: 0.7, y: 0.85)
    var width: CGFloat = 0.3
}

struct ScanPage: Identifiable, Equatable {
    var id = UUID()
    var source: UIImage
    var filter: ScanFilter = .magic
    var rotation = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var overlays: [ScanOverlay] = []
    var mosaics: [CGRect] = []     // نسب داخل الصفحة
}

// MARK: - المعالجة

enum ScanProcessor {
    static let ctx = CIContext(options: [.useSoftwareRenderer: false])

    static func ci(_ img: UIImage) -> CIImage {
        let c = CIImage(image: img) ?? CIImage()
        return c.oriented(CGImagePropertyOrientation(img.imageOrientation))
    }

    /// تصحيح المنظور بأربع زوايا (نسبية، أصل الإحداثيات أعلى اليسار)
    static func perspective(_ img: UIImage, _ q: [CGPoint]) -> UIImage {
        let c = ci(img)
        let e = c.extent
        func p(_ v: CGPoint) -> CIVector { CIVector(x: e.minX + v.x * e.width, y: e.minY + (1 - v.y) * e.height) }
        let f = CIFilter.perspectiveCorrection()
        f.inputImage = c
        f.topLeft = p(q[0]).cgPoint; f.topRight = p(q[1]).cgPoint; f.bottomRight = p(q[2]).cgPoint; f.bottomLeft = p(q[3]).cgPoint
        guard let o = f.outputImage, let cg = ctx.createCGImage(o, from: o.extent) else { return img }
        return UIImage(cgImage: cg)
    }

    /// اكتشاف حواف الورقة في صورة (مثلًا من الصور)
    static func detectQuad(_ img: UIImage) -> [CGPoint]? {
        guard let cg = img.cgImage else { return nil }
        let r = VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(img.imageOrientation)).perform([r])
        guard let o = r.results?.first else { return nil }
        func f(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        return [f(o.topLeft), f(o.topRight), f(o.bottomRight), f(o.bottomLeft)]
    }

    static func render(_ p: ScanPage, maxSide: CGFloat = 2600) -> UIImage {
        var img = ci(p.source)
        // التدوير
        if p.rotation % 360 != 0 {
            let map: [Int: CGImagePropertyOrientation] = [90: .right, 180: .down, 270: .left]
            let o = map[((p.rotation % 360) + 360) % 360] ?? .up
            img = img.oriented(o)
        }
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        let k = min(1, maxSide / max(img.extent.width, img.extent.height))
        if k < 1 { img = img.transformed(by: CGAffineTransform(scaleX: k, y: k)) }
        img = applyFilter(img, p.filter)
        if p.brightness != 0 || p.contrast != 1 {
            let cc = CIFilter.colorControls(); cc.inputImage = img; cc.brightness = Float(p.brightness); cc.contrast = Float(p.contrast)
            img = cc.outputImage ?? img
        }
        let ext = img.extent
        // التمويه (موزاييك) على المناطق المحددة
        for r in p.mosaics {
            let rect = CGRect(x: ext.minX + r.minX * ext.width, y: ext.minY + (1 - r.maxY) * ext.height, width: r.width * ext.width, height: r.height * ext.height)
            let px = CIFilter.pixellate(); px.inputImage = img.clampedToExtent(); px.scale = Float(max(12, ext.width / 60))
            if let m = px.outputImage?.cropped(to: rect) { img = m.composited(over: img) }
        }
        guard let cg = ctx.createCGImage(img, from: ext) else { return p.source }
        var out = UIImage(cgImage: cg)
        // التوقيع والعلامة المائية
        if !p.overlays.isEmpty {
            let size = out.size
            out = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in
                out.draw(at: .zero)
                for o in p.overlays {
                    switch o.kind {
                    case .signature(let s):
                        let w = size.width * o.width, h = w * s.size.height / max(1, s.size.width)
                        s.draw(in: CGRect(x: o.center.x * size.width - w / 2, y: o.center.y * size.height - h / 2, width: w, height: h))
                    case .text(let t):
                        let fs = size.width * 0.05
                        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont(name: "Tajawal-Bold", size: fs) ?? .boldSystemFont(ofSize: fs),
                                                                    .foregroundColor: UIColor(white: 0.4, alpha: 0.28)]
                        let c = UIGraphicsGetCurrentContext()
                        c?.saveGState()
                        c?.translateBy(x: size.width / 2, y: size.height / 2)
                        c?.rotate(by: -.pi / 6)
                        let ts = (t as NSString).size(withAttributes: attrs)
                        var y = -size.height
                        while y < size.height {
                            var x = -size.width
                            while x < size.width { (t as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs); x += ts.width + fs * 2 }
                            y += ts.height * 3.2
                        }
                        c?.restoreGState()
                    }
                }
            }
        }
        return out
    }

    static func applyFilter(_ img: CIImage, _ f: ScanFilter) -> CIImage {
        switch f {
        case .original: return img
        case .auto:
            let cc = CIFilter.colorControls(); cc.inputImage = img; cc.contrast = 1.12; cc.saturation = 1.05; cc.brightness = 0.02
            let sh = CIFilter.unsharpMask(); sh.inputImage = cc.outputImage; sh.radius = 2; sh.intensity = 0.5
            return sh.outputImage ?? img
        case .magic, .bw, .ink:
            // إزالة الظلال: قسمة الصورة على نسخة مموّهة منها (تُبيّض الخلفية وتُبقي الحبر)
            let blur = CIFilter.gaussianBlur(); blur.inputImage = img.clampedToExtent(); blur.radius = Float(max(img.extent.width, img.extent.height) / 40)
            guard let bg = blur.outputImage?.cropped(to: img.extent) else { return img }
            let div = CIFilter.divideBlendMode(); div.inputImage = img; div.backgroundImage = bg
            var o = div.outputImage ?? img
            let cc = CIFilter.colorControls(); cc.inputImage = o; cc.contrast = f == .ink ? 1.3 : 1.45; cc.saturation = f == .magic ? 1.15 : 0; cc.brightness = f == .ink ? 0.06 : 0
            o = cc.outputImage ?? o
            if f == .bw {
                let t = CIFilter.colorThreshold(); t.inputImage = o; t.threshold = 0.62
                o = t.outputImage ?? o
            }
            return o.cropped(to: img.extent)
        case .gray:
            let m = CIFilter.photoEffectNoir(); m.inputImage = img
            let cc = CIFilter.colorControls(); cc.inputImage = m.outputImage; cc.contrast = 1.15
            return cc.outputImage ?? img
        }
    }

    static func ocr(_ img: UIImage) -> [VNRecognizedTextObservation] {
        guard let cg = img.cgImage else { return [] }
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .accurate
        r.usesLanguageCorrection = true
        r.recognitionLanguages = ["ar-SA", "en-US"]
        try? VNImageRequestHandler(cgImage: cg).perform([r])
        return r.results ?? []
    }

    static func text(of img: UIImage) -> String { ocr(img).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") }

    /// بطاقة الهوية: الوجهان على صفحة A4
    static func idSheet(_ front: UIImage, _ back: UIImage?) -> UIImage {
        let page = CGSize(width: 2480, height: 3508)
        return UIGraphicsImageRenderer(size: page, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { c in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: page))
            let w = page.width * 0.62
            for (i, img) in [front, back].compactMap({ $0 }).enumerated() {
                let h = w * img.size.height / max(1, img.size.width)
                img.draw(in: CGRect(x: (page.width - w) / 2, y: page.height * (i == 0 ? 0.12 : 0.55), width: w, height: h))
            }
        }
    }

    /// صفحتا الكتاب: تقسيم عمودي (العربي: اليمنى أولًا)
    static func splitBook(_ img: UIImage) -> [UIImage] {
        guard let cg = img.cgImage else { return [img] }
        let w = cg.width / 2
        guard let l = cg.cropping(to: CGRect(x: 0, y: 0, width: w, height: cg.height)),
              let r = cg.cropping(to: CGRect(x: w, y: 0, width: cg.width - w, height: cg.height)) else { return [img] }
        return [UIImage(cgImage: r, scale: 1, orientation: img.imageOrientation), UIImage(cgImage: l, scale: 1, orientation: img.imageOrientation)]
    }
}

// MARK: - التصدير

enum ScanExport: String, CaseIterable, Identifiable {
    case pdf, jpg, txt, docx, longImage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .jpg: return L("صور JPG")
        case .txt: return L("نص TXT")
        case .docx: return "Word"
        case .longImage: return L("صورة طويلة")
        }
    }
}

enum ScanExporter {
    static var folder: URL {
        let d = FileStore.shared.root.appendingPathComponent(L("المسح الضوئي"), isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func defaultName() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH.mm"
        return L("مسح") + " " + f.string(from: Date())
    }

    /// يرجع الملفات الناتجة
    @MainActor
    static func export(_ pages: [ScanPage], as fmt: ScanExport, name: String, paper: Int, quality: CGFloat, searchable: Bool, password: String) async throws -> [URL] {
        let store = FileStore.shared
        let base = store.sanitize(name.isEmpty ? defaultName() : name)
        let dir = folder
        let side: CGFloat = quality > 0.8 ? 2600 : (quality > 0.55 ? 2000 : 1400)
        let imgs = pages.map { ScanProcessor.render($0, maxSide: side) }
        switch fmt {
        case .jpg:
            return imgs.enumerated().compactMap { i, img in
                let u = store.unique(imgs.count > 1 ? "\(base) (\(i + 1)).jpg" : "\(base).jpg", in: dir)
                return (try? img.jpegData(compressionQuality: quality)?.write(to: u)) != nil ? u : nil
            }
        case .longImage:
            let w = imgs.map(\.size.width).max() ?? 1000
            let h = imgs.reduce(0) { $0 + $1.size.height * w / max(1, $1.size.width) }
            let long = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in
                var y: CGFloat = 0
                for img in imgs { let ih = img.size.height * w / max(1, img.size.width); img.draw(in: CGRect(x: 0, y: y, width: w, height: ih)); y += ih }
            }
            let u = store.unique("\(base).jpg", in: dir)
            try long.jpegData(compressionQuality: quality)?.write(to: u)
            return [u]
        case .txt:
            let t = imgs.map { ScanProcessor.text(of: $0) }.joined(separator: "\n\n— — —\n\n")
            let u = store.unique("\(base).txt", in: dir)
            try t.write(to: u, atomically: true, encoding: .utf8)
            return [u]
        case .docx:
            let paras = imgs.map { ScanProcessor.text(of: $0) }
            let u = store.unique("\(base).docx", in: dir)
            try writeDocx(paras, to: u)
            return [u]
        case .pdf:
            let a4 = CGSize(width: 595, height: 842), letter = CGSize(width: 612, height: 792)
            let data = NSMutableData()
            UIGraphicsBeginPDFContextToData(data, .zero, [kCGPDFContextCreator as String: "Rafiqi"])
            for img in imgs {
                let pageSize = paper == 0 ? a4 : (paper == 1 ? letter : CGSize(width: 595, height: 595 * img.size.height / max(1, img.size.width)))
                UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: pageSize), nil)
                let k = min(pageSize.width / img.size.width, pageSize.height / img.size.height)
                let r = CGRect(x: (pageSize.width - img.size.width * k) / 2, y: (pageSize.height - img.size.height * k) / 2,
                               width: img.size.width * k, height: img.size.height * k)
                // الصورة مضغوطة بالجودة المختارة
                let jpg = img.jpegData(compressionQuality: quality).flatMap { UIImage(data: $0) } ?? img
                jpg.draw(in: r)
                // طبقة نص مخفية: الملف قابل للبحث والنسخ
                if searchable {
                    for o in ScanProcessor.ocr(img) {
                        guard let s = o.topCandidates(1).first?.string else { continue }
                        let b = o.boundingBox
                        let box = CGRect(x: r.minX + b.minX * r.width, y: r.minY + (1 - b.maxY) * r.height, width: b.width * r.width, height: b.height * r.height)
                        let font = UIFont.systemFont(ofSize: max(4, box.height * 0.8))
                        let natural = (s as NSString).size(withAttributes: [.font: font]).width
                        let scaled = UIFont.systemFont(ofSize: max(3, font.pointSize * min(1.5, box.width / max(1, natural))))
                        (s as NSString).draw(in: box, withAttributes: [.font: scaled, .foregroundColor: UIColor(white: 1, alpha: 0.01)])
                    }
                }
            }
            UIGraphicsEndPDFContext()
            let u = store.unique("\(base).pdf", in: dir)
            if !password.isEmpty, let doc = PDFDocument(data: data as Data) {
                doc.write(to: u, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password])
            } else {
                try (data as Data).write(to: u)
            }
            return [u]
        }
    }

    /// ملف Word بسيط (فقرات بالاتجاه من اليمين لليسار)
    static func writeDocx(_ paragraphs: [String], to url: URL) throws {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var body = ""
        for (i, p) in paragraphs.enumerated() {
            for line in p.components(separatedBy: "\n") {
                body += "<w:p><w:pPr><w:bidi/><w:jc w:val=\"right\"/></w:pPr><w:r><w:rPr><w:rtl/><w:rFonts w:ascii=\"Arial\" w:cs=\"Arial\"/><w:sz w:val=\"26\"/><w:szCs w:val=\"26\"/></w:rPr><w:t xml:space=\"preserve\">\(esc(line))</w:t></w:r></w:p>"
            }
            if i < paragraphs.count - 1 { body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" }
        }
        let doc = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)<w:sectPr><w:bidi/></w:sectPr></w:body></w:document>
        """
        let types = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """
        try? FileManager.default.removeItem(at: url)
        let a = try Archive(url: url, accessMode: .create)
        for (path, s) in [("[Content_Types].xml", types), ("_rels/.rels", rels), ("word/document.xml", doc)] {
            let d = Data(s.utf8)
            try a.addEntry(with: path, type: .file, uncompressedSize: Int64(d.count), compressionMethod: .deflate, provider: { pos, size in
                d.subdata(in: Int(pos)..<Int(pos) + size)
            })
        }
    }
}

// MARK: - الشاشة الرئيسية للماسح

struct ScannerHome: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ScanMode = .document
    @State private var pages: [ScanPage] = []
    @State private var showCamera = false
    @State private var showLive = false
    @State private var idFront: UIImage?
    @State private var resultText: String?
    @State private var translateText: String?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ScanMode.allCases) { m in
                            Button { start(m) } label: {
                                VStack(spacing: 8) {
                                    Badge(name: m.icon, size: 48, active: mode == m)
                                    Text(verbatim: m.title).font(Theme.f(.footnote, .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                                    Text(verbatim: m.hint).font(Theme.f(.caption2)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                                        .lineLimit(3).frame(height: 44, alignment: .top)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(mode == m ? Theme.gold.opacity(0.5) : Theme.stroke, lineWidth: 1))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    Button { showPhotos = true } label: {
                        Label("مسح من صور موجودة", systemImage: "photo.on.rectangle").font(Theme.f(.subheadline, .bold)).foregroundStyle(Theme.gold)
                            .frame(maxWidth: .infinity).padding(.vertical, 12).background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                    }
                    if let resultText {
                        ResultText(title: L("النص المستخرج"), text: resultText)
                    }
                    if let translateText {
                        TranslatePanel(source: translateText)
                    }
                    Text("كل المعالجة على جوالك: لا تُرفع صورك ولا مستنداتك إلى أي خادم.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("الماسح الضوئي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .navigationDestination(isPresented: Binding(get: { !pages.isEmpty }, set: { if !$0 { pages = [] } })) {
                ScanEditor(pages: $pages) { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocCamera { imgs in
                showCamera = false
                handle(imgs)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showLive) {
            LiveScanner(text: mode == .text) { showLive = false }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 30, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var imgs: [UIImage] = []
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        // اكتشاف حواف الورقة في الصورة وتصحيحها
                        if let q = ScanProcessor.detectQuad(img) { imgs.append(ScanProcessor.perspective(img, q)) } else { imgs.append(img) }
                    }
                }
                photoItems = []
                handle(imgs)
            }
        }
    }

    private func start(_ m: ScanMode) {
        mode = m
        resultText = nil; translateText = nil
        if m == .qr { showLive = DataScannerViewController.isSupported; if !showLive { resultText = L("القراءة المباشرة غير مدعومة في هذا الجهاز.") }; return }
        guard VNDocumentCameraViewController.isSupported else { resultText = L("الكاميرا غير متاحة. استخدم «مسح من صور موجودة»."); return }
        showCamera = true
    }

    private func handle(_ imgs: [UIImage]) {
        guard !imgs.isEmpty else { return }
        switch mode {
        case .document, .qr:
            pages += imgs.map { ScanPage(source: $0) }
        case .idCard:
            if imgs.count >= 2 { pages = [ScanPage(source: ScanProcessor.idSheet(imgs[0], imgs[1]), filter: .auto)] }
            else if let f = idFront { pages = [ScanPage(source: ScanProcessor.idSheet(f, imgs[0]), filter: .auto)]; idFront = nil }
            else { idFront = imgs[0]; resultText = L("صُوّر الوجه. اضغط «هوية وجواز» مرة أخرى لتصوير الظهر."); }
        case .book:
            pages += imgs.flatMap { ScanProcessor.splitBook($0) }.map { ScanPage(source: $0) }
        case .text:
            resultText = imgs.map { ScanProcessor.text(of: $0) }.joined(separator: "\n\n")
        case .translate:
            translateText = imgs.map { ScanProcessor.text(of: $0) }.joined(separator: "\n\n")
        }
    }
}

/// كاميرا المستندات من أبل (اكتشاف الحواف والالتقاط التلقائي وتعدد الصفحات)
struct DocCamera: UIViewControllerRepresentable {
    let done: ([UIImage]) -> Void
    func makeCoordinator() -> Coord { Coord(done: done) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let c = VNDocumentCameraViewController(); c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coord: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done([]) }
    }
}

/// القراءة المباشرة: باركود/QR أو نص
struct LiveScanner: UIViewControllerRepresentable {
    let text: Bool
    let close: () -> Void
    func makeCoordinator() -> Coord { Coord(close: close) }
    func makeUIViewController(context: Context) -> UINavigationController {
        let types: Set<DataScannerViewController.RecognizedDataType> = text ? [.text()] : [.barcode()]
        let vc = DataScannerViewController(recognizedDataTypes: types, qualityLevel: .accurate, recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in context.coordinator.close() })
        try? vc.startScanning()
        return UINavigationController(rootViewController: vc)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coord: NSObject, DataScannerViewControllerDelegate {
        let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            var value = ""
            switch item {
            case .barcode(let b): value = b.payloadStringValue ?? ""
            case .text(let t): value = t.transcript
            @unknown default: break
            }
            guard !value.isEmpty else { return }
            let a = UIAlertController(title: nil, message: value, preferredStyle: .actionSheet)
            a.addAction(UIAlertAction(title: L("نسخ"), style: .default) { _ in UIPasteboard.general.string = value })
            if let u = URL(string: value), u.scheme?.hasPrefix("http") == true {
                a.addAction(UIAlertAction(title: L("فتح الرابط"), style: .default) { _ in UIApplication.shared.open(u) })
            }
            a.addAction(UIAlertAction(title: L("إلغاء"), style: .cancel))
            dataScanner.present(a, animated: true)
        }
    }
}

struct ResultText: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title).font(Theme.f(.headline)).foregroundStyle(.white)
            Text(verbatim: text.isEmpty ? L("لم يُعثر على نص.") : text).font(Theme.f(.body)).foregroundStyle(.white).textSelection(.enabled)
            HStack(spacing: 10) {
                Button { UIPasteboard.general.string = text } label: { Label("نسخ", systemImage: "doc.on.doc") }
                Button {
                    let u = FileStore.shared.unique(ScanExporter.defaultName() + ".txt", in: ScanExporter.folder)
                    try? text.write(to: u, atomically: true, encoding: .utf8)
                    FileStore.shared.touch()
                    FileOpener.share([u])
                } label: { Label("حفظ ومشاركة", systemImage: "square.and.arrow.up") }
            }
            .font(Theme.f(.subheadline, .bold)).foregroundStyle(Theme.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading).glassCard(padding: 16)
    }
}

/// الأصل والترجمة جنبًا إلى جنب
struct TranslatePanel: View {
    let source: String
    @State private var target = "en"
    @State private var translated: String?
    @State private var go = false
    @State private var cues: [(Double, Double, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $target) { Text("English").tag("en"); Text("العربية").tag("ar") }.pickerStyle(.segmented)
            HStack(alignment: .top, spacing: 10) {
                column(L("الأصل"), source)
                column(L("الترجمة"), translated ?? (go ? L("جارٍ الترجمة…") : "—"))
            }
            Button {
                cues = source.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { (0, 0, $0) }
                go = true
            } label: {
                Text("ترجمة").font(Theme.f(.headline)).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gold))
            }
            if let translated { ResultText(title: L("الترجمة"), text: translated) }
        }
        .glassCard(padding: 16)
        .modifier(CueTranslator(active: $go, source: target == "en" ? "ar" : "en", target: target, cues: cues) { out, err in
            go = false
            translated = err ?? out.map(\.2).joined(separator: "\n")
        })
    }

    private func column(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: t).font(Theme.f(.caption, .bold)).foregroundStyle(Theme.gold)
            Text(verbatim: s).font(Theme.f(.footnote)).foregroundStyle(.white).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }
}

// MARK: - المحرر

struct ScanEditor: View {
    @Binding var pages: [ScanPage]
    let finished: () -> Void
    @State private var index = 0
    @State private var preview: [UUID: UIImage] = [:]
    @State private var cropping = false
    @State private var signing = false
    @State private var watermark = false
    @State private var watermarkText = ""
    @State private var mosaicMode = false
    @State private var exporting = false
    @State private var addMore = false

    private var page: ScanPage? { pages.indices.contains(index) ? pages[index] : nil }

    var body: some View {
        VStack(spacing: 10) {
            if let p = page {
                ZStack {
                    if let img = preview[p.id] {
                        Image(uiImage: img).resizable().scaledToFit()
                            .overlay { if mosaicMode { MosaicPicker { r in pages[index].mosaics.append(r); refresh() } } }
                    } else {
                        ProgressView().tint(Theme.gold)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                Text(LF("صفحة %@ من %@", ar(index + 1), ar(pages.count))).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                thumbs
                filters
                tools
            }
        }
        .background(AppBackground())
        .navigationTitle(mosaicMode ? L("اسحب لتحديد منطقة الإخفاء") : L("تعديل المسح"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if mosaicMode { Button("تم") { mosaicMode = false } } else { Button("حفظ") { exporting = true }.bold() }
            }
        }
        .task(id: pages) { refresh() }
        .sheet(isPresented: $cropping) { if let p = page { CropView(image: p.source) { img in pages[index].source = img; refresh() } } }
        .sheet(isPresented: $signing) { SignaturePad { img in pages[index].overlays.append(ScanOverlay(kind: .signature(img))); refresh() } }
        .sheet(isPresented: $exporting) { ExportSheet(pages: pages) { finished() } }
        .fullScreenCover(isPresented: $addMore) { DocCamera { imgs in addMore = false; pages += imgs.map { ScanPage(source: $0) } }.ignoresSafeArea() }
        .alert(L("علامة مائية"), isPresented: $watermark) {
            TextField(L("النص، مثل: نسخة لـ…"), text: $watermarkText)
            Button(L("إضافة لكل الصفحات")) {
                for i in pages.indices { pages[i].overlays.removeAll { if case .text = $0.kind { return true }; return false }
                    if !watermarkText.isEmpty { pages[i].overlays.append(ScanOverlay(kind: .text(watermarkText))) } }
                refresh()
            }
            Button(L("إلغاء"), role: .cancel) {}
        }
    }

    private var thumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                    Button { index = i } label: {
                        Group {
                            if let img = preview[p.id] { Image(uiImage: img).resizable().scaledToFill() } else { Color.white.opacity(0.08) }
                        }
                        .frame(width: 46, height: 60).clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(i == index ? Theme.gold : Color.clear, lineWidth: 2))
                    }
                }
                Button { addMore = VNDocumentCameraViewController.isSupported } label: {
                    Image(systemName: "plus").foregroundStyle(Theme.gold).frame(width: 46, height: 60)
                        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.gold.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ScanFilter.allCases) { f in
                    let on = page?.filter == f
                    Button { pages[index].filter = f } label: {
                        Text(verbatim: f.title).font(Theme.f(.footnote, on ? .bold : .medium)).foregroundStyle(on ? Color.black : .white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(on ? Theme.gold : Theme.card))
                    }
                }
                Button { for i in pages.indices { pages[i].filter = page?.filter ?? .magic } } label: {
                    Text("للكل").font(Theme.f(.footnote, .bold)).foregroundStyle(Theme.gold).padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var tools: some View {
        HStack(spacing: 0) {
            tool("crop", L("قص")) { cropping = true }
            tool("rotate.right", L("تدوير")) { pages[index].rotation += 90 }
            tool("sun.max", L("سطوع")) { pages[index].brightness = pages[index].brightness >= 0.15 ? -0.1 : pages[index].brightness + 0.05 }
            tool("signature", L("توقيع")) { signing = true }
            tool("drop.halffull", L("علامة مائية")) { watermark = true }
            tool("square.grid.3x3.fill", L("إخفاء")) { mosaicMode = true }
            tool("trash", L("حذف")) {
                pages.remove(at: index)
                index = max(0, min(index, pages.count - 1))
            }
        }
        .padding(.vertical, 8)
        .background(Theme.card)
    }

    private func tool(_ icon: String, _ t: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(verbatim: t).font(Theme.f(.caption2)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity)
        }
    }

    private func refresh() {
        let snapshot = pages
        Task.detached(priority: .userInitiated) {
            var out: [UUID: UIImage] = [:]
            for p in snapshot { out[p.id] = ScanProcessor.render(p, maxSide: 1200) }
            await MainActor.run { preview = out }
        }
    }
}

/// تحديد منطقة الإخفاء بالسحب
struct MosaicPicker: View {
    let add: (CGRect) -> Void
    @State private var start: CGPoint?
    @State private var current: CGPoint?
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                if let s = start, let c = current {
                    Rectangle().stroke(Theme.gold, lineWidth: 2).background(Theme.gold.opacity(0.15))
                        .frame(width: abs(c.x - s.x), height: abs(c.y - s.y)).offset(x: min(s.x, c.x), y: min(s.y, c.y))
                }
            }
            .gesture(DragGesture(minimumDistance: 4).onChanged { v in start = v.startLocation; current = v.location }.onEnded { v in
                let r = CGRect(x: min(v.startLocation.x, v.location.x) / g.size.width, y: min(v.startLocation.y, v.location.y) / g.size.height,
                               width: abs(v.location.x - v.startLocation.x) / g.size.width, height: abs(v.location.y - v.startLocation.y) / g.size.height)
                start = nil; current = nil
                if r.width > 0.01, r.height > 0.01 { add(r) }
            })
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// القص اليدوي بالزوايا الأربع مع تصحيح المنظور
struct CropView: View {
    let image: UIImage
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var q: [CGPoint] = [CGPoint(x: 0.05, y: 0.05), CGPoint(x: 0.95, y: 0.05), CGPoint(x: 0.95, y: 0.95), CGPoint(x: 0.05, y: 0.95)]

    var body: some View {
        NavigationStack {
            GeometryReader { g in
                let fit = AVMakeRectWithAspectRatioInsideRect(image.size, CGRect(origin: .zero, size: g.size))
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: g.size.width, height: g.size.height)
                    Path { p in
                        let pts = q.map { CGPoint(x: fit.minX + $0.x * fit.width, y: fit.minY + $0.y * fit.height) }
                        p.addLines(pts); p.closeSubpath()
                    }
                    .stroke(Theme.gold, lineWidth: 2)
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(Theme.gold).frame(width: 28, height: 28).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .position(x: fit.minX + q[i].x * fit.width, y: fit.minY + q[i].y * fit.height)
                            .gesture(DragGesture().onChanged { v in
                                q[i] = CGPoint(x: min(1, max(0, (v.location.x - fit.minX) / fit.width)), y: min(1, max(0, (v.location.y - fit.minY) / fit.height)))
                            })
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(20)
            .background(Color.black)
            .navigationTitle("قص المستند")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("اكتشاف تلقائي") { if let d = ScanProcessor.detectQuad(image) { q = d } } }
                ToolbarItem(placement: .confirmationAction) { Button("تم") { done(ScanProcessor.perspective(image, q)); dismiss() }.bold() }
            }
            .onAppear { if let d = ScanProcessor.detectQuad(image) { q = d } }
        }
    }
}

/// لوحة التوقيع (بالإصبع أو القلم)
struct SignaturePad: View {
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                CanvasRep(canvas: canvas)
                    .frame(height: 240).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
                Text("وقّع داخل المربع. يُضاف التوقيع أسفل الصفحة الحالية، ويُحفظ لاستخدامه لاحقًا.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                if let saved = SignatureStore.load() {
                    Button { done(saved); dismiss() } label: {
                        HStack { Image(uiImage: saved).resizable().scaledToFit().frame(height: 50).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("استخدام التوقيع المحفوظ").font(Theme.f(.subheadline, .bold)).foregroundStyle(Theme.gold) }
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(AppBackground())
            .navigationTitle("التوقيع")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("مسح") { canvas.drawing = PKDrawing() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") {
                        let b = canvas.drawing.bounds
                        guard !b.isEmpty else { dismiss(); return }
                        let img = canvas.drawing.image(from: b.insetBy(dx: -8, dy: -8), scale: 3)
                        SignatureStore.save(img)
                        done(img); dismiss()
                    }.bold()
                }
            }
        }
    }
}

enum SignatureStore {
    static var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("signature.png") }
    static func save(_ img: UIImage) { try? img.pngData()?.write(to: url) }
    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
}

struct CanvasRep: UIViewRepresentable {
    let canvas: PKCanvasView
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        return canvas
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

/// خيارات الحفظ
struct ExportSheet: View {
    let pages: [ScanPage]
    let finished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ScanExporter.defaultName()
    @State private var format: ScanExport = .pdf
    @State private var paper = 0
    @State private var quality = 1
    @State private var searchable = true
    @State private var password = ""
    @State private var working = false
    @State private var result: [URL] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField(L("اسم الملف"), text: $name) } header: { Text("الاسم") }
                Section {
                    Picker(L("الصيغة"), selection: $format) { ForEach(ScanExport.allCases) { Text($0.title).tag($0) } }
                    if format == .pdf || format == .jpg || format == .longImage {
                        Picker(L("الجودة"), selection: $quality) { Text("عالية").tag(1); Text("متوسطة").tag(2); Text("صغيرة الحجم").tag(3) }
                    }
                    if format == .pdf {
                        Picker(L("مقاس الصفحة"), selection: $paper) { Text(verbatim: "A4").tag(0); Text(verbatim: "Letter").tag(1); Text("بحجم المسح").tag(2) }
                        Toggle(L("قابل للبحث والنسخ (التعرّف على النص)"), isOn: $searchable)
                        SecureField(L("كلمة مرور للملف (اختياري)"), text: $password)
                    }
                } footer: {
                    Text(format == .docx || format == .txt ? "يُستخرج النص من الصفحات بالتعرّف الضوئي (العربية والإنجليزية)." : "يُحفظ في «ملفاتي ← المسح الضوئي».")
                }
                if let error { Section { Text(verbatim: error).foregroundStyle(.orange) } }
                if !result.isEmpty {
                    Section {
                        ForEach(result, id: \.self) { u in Text(verbatim: u.lastPathComponent) }
                        Button { FileOpener.share(result) } label: { Label("مشاركة", systemImage: "square.and.arrow.up") }
                        Button { FilePrinter.print(result) } label: { Label("طباعة", systemImage: "printer") }
                        Button { let u = result[0]; dismiss(); finished(); Task { try? await Task.sleep(nanoseconds: 600_000_000); FileOpener.open(u) } } label: { Label("فتح", systemImage: "doc") }
                    } header: { Text("تم الحفظ") }
                }
            }
            .glassList()
            .tint(Theme.gold)
            .navigationTitle("حفظ المسح")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(result.isEmpty ? "إلغاء" : "تم") { dismiss(); if !result.isEmpty { finished() } } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else if result.isEmpty {
                        Button("حفظ") {
                            working = true
                            Task {
                                do {
                                    result = try await ScanExporter.export(pages, as: format, name: name, paper: paper,
                                                                           quality: [1: 0.9, 2: 0.7, 3: 0.45][quality] ?? 0.9, searchable: searchable, password: password)
                                    FileStore.shared.touch()
                                } catch { self.error = error.localizedDescription }
                                working = false
                            }
                        }.bold()
                    }
                }
            }
        }
    }
}

// MARK: - الطباعة وتحويل المستندات إلى PDF

@MainActor
enum FilePrinter {
    static func print(_ urls: [URL]) {
        let p = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = urls.first?.lastPathComponent ?? "Rafiqi"
        p.printInfo = info
        p.printingItems = urls
        p.present(animated: true)
    }
}

/// Word وExcel وPowerPoint والنصوص وصفحات HTML ← PDF (عبر محرّك عرض المستندات في iOS)
@MainActor
final class DocToPDF: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var cont: CheckedContinuation<URL, Error>?
    private var src: URL?
    private static var keep: [DocToPDF] = []

    static func convert(_ url: URL) async throws -> URL {
        let c = DocToPDF()
        keep.append(c)
        defer { keep.removeAll { $0 === c } }
        return try await c.run(url)
    }

    private func run(_ url: URL) async throws -> URL {
        src = url
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 595, height: 842))
        w.navigationDelegate = self
        web = w
        return try await withCheckedThrowingContinuation { c in
            cont = c
            w.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            let r = UIPrintPageRenderer()
            r.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
            let page = CGRect(x: 0, y: 0, width: 595, height: 842)
            r.setValue(NSValue(cgRect: page), forKey: "paperRect")
            r.setValue(NSValue(cgRect: page.insetBy(dx: 36, dy: 36)), forKey: "printableRect")
            let data = NSMutableData()
            UIGraphicsBeginPDFContextToData(data, page, nil)
            for i in 0..<max(1, r.numberOfPages) {
                UIGraphicsBeginPDFPage()
                r.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
            }
            UIGraphicsEndPDFContext()
            guard let src else { return }
            let out = MediaTools.output(for: src, suffix: "PDF", ext: "pdf")
            do { try (data as Data).write(to: out); cont?.resume(returning: out) } catch { cont?.resume(throwing: error) }
            cont = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { cont?.resume(throwing: error); cont = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { cont?.resume(throwing: error); cont = nil }
}

extension CIVector { var cgPoint: CGPoint { CGPoint(x: x, y: y) } }


/// محرر المسح لصورة موجودة (من أدوات الصورة)
struct ScanEditorHost: View {
    @State var pages: [ScanPage]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { ScanEditor(pages: $pages) { dismiss() } }
            .onChange(of: pages.isEmpty) { _, e in if e { dismiss() } }
    }
}
