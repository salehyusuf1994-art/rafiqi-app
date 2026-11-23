import SwiftUI
import AVFoundation

/// شاشة «دمج المقاطع»: ترتيب الملفات بالسحب قبل الدمج، ثم دمج سريع (بلا إعادة ترميز) إن أمكن، مع التقدم والإلغاء
struct MergeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urls: [URL]
    /// رسالة تظهر في إدارة الملفات بعد الإغلاق
    var done: (String) -> Void = { _ in }

    private struct Info { var thumb: UIImage?; var duration: Double; var size: Int64 }
    @State private var info: [URL: Info] = [:]
    @State private var fast: Bool?
    @State private var running = false
    @State private var progress = 0.0
    @State private var job: Task<Void, Never>?
    @State private var result: URL?
    @State private var error = ""

    init(urls: [URL], done: @escaping (String) -> Void = { _ in }) {
        // الترتيب الطبيعي بالاسم: ١، ٢، ٣ … ١٠ (لا ١، ١٠، ٢)
        _urls = State(initialValue: urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        self.done = done
    }

    private var isVideo: Bool { urls.allSatisfy(MediaTools.isVideo) }
    private var totalDuration: Double { urls.reduce(0) { $0 + (info[$1]?.duration ?? 0) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                if let result {
                    resultCard(result)
                    Spacer(minLength: 0)
                } else {
                    list
                    bottom
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(AppBackground())
            .hiddenNavBar()
        }
        .interactiveDismissDisabled(running)
        .task { await load() }
        .onDisappear { job?.cancel() }
    }

    // MARK: الرأس

    private var header: some View {
        HStack(spacing: 12) {
            Badge(name: "rectangle.stack.badge.plus", size: 46, active: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("دمج المقاطع").font(Theme.f(.headline)).foregroundStyle(.white)
                Text(verbatim: summary).font(Theme.f(.caption)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer()
            CircleButton(icon: "xmark", size: 38) { job?.cancel(); dismiss() }
                .accessibilityLabel(L("إغلاق"))
        }
    }

    private var summary: String {
        let n = countText(urls.count, one: "ملف واحد", two: "ملفان", few: "ملفات", many: "ملفًا", en: "files")
        return totalDuration > 0 ? n + " · " + LF("المدة الكلية %@", durationText(totalDuration)) : n
    }

    // MARK: القائمة

    private var list: some View {
        List {
            Section {
                ForEach(Array(urls.enumerated()), id: \.element) { i, u in
                    row(i, u)
                        .listRowBackground(Theme.card)
                }
                .onMove { from, to in urls.move(fromOffsets: from, toOffset: to) }
                .moveDisabled(running)
            } header: {
                HStack {
                    Text("الترتيب").font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white)
                    Spacer()
                    Menu {
                        Button { withAnimation { urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } } } label: {
                            Label("حسب الاسم", systemImage: "textformat")
                        }
                        Button { withAnimation { urls.reverse() } } label: { Label("عكس الترتيب", systemImage: "arrow.up.arrow.down") }
                    } label: {
                        Label("ترتيب", systemImage: "arrow.up.arrow.down").font(Theme.f(.footnote, .semibold)).foregroundStyle(Theme.gold)
                    }
                    .disabled(running)
                }
                .textCase(nil)
            } footer: {
                Text("اسحب من المقبض لتغيير الترتيب. يُدمج من الأعلى إلى الأسفل.")
                    .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(running ? .inactive : .active))
    }

    private func row(_ i: Int, _ u: URL) -> some View {
        let inf = info[u]
        return HStack(spacing: 12) {
            Text(ar(i + 1)).font(Theme.f(.footnote, .bold).monospacedDigit()).foregroundStyle(Theme.gold).frame(minWidth: 22)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06))
                if let t = inf?.thumb {
                    Image(uiImage: t).resizable().scaledToFill()
                } else {
                    Image(systemName: isVideo ? "film" : "music.note").foregroundStyle(Theme.sub)
                }
            }
            .frame(width: 64, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: u.lastPathComponent).font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                if let inf {
                    Text(verbatim: sizeText(inf.size) + " · " + durationText(inf.duration))
                        .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LF("%@، رقم %@", u.deletingPathExtension().lastPathComponent, ar(i + 1)))
    }

    // MARK: الأسفل: الدمج والتقدم

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 10) {
            if running {
                ProgressView(value: progress).tint(Theme.gold)
                HStack {
                    Text(LF("جارٍ الدمج… %@٪", ar(Int(progress * 100)))).font(Theme.f(.subheadline)).foregroundStyle(.white)
                    Spacer()
                    Button { job?.cancel() } label: {
                        Label("إلغاء", systemImage: "xmark").font(Theme.f(.subheadline, .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.cardHi))
                    }
                    .buttonStyle(PressStyle()).foregroundStyle(.white)
                }
                Text("الشاشة تبقى مضاءة حتى ينتهي. أبقِ التطبيق مفتوحًا.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            } else {
                if let fast {
                    Label(fast ? L("سريع وبنفس الجودة: الملفات من نفس النوع والمقاس، فتُدمج بدون إعادة ضغط.")
                               : L("الملفات مختلفة في النوع أو المقاس، فيُعاد ترميزها. قد يستغرق ذلك وقتًا ويسخن الجوال قليلًا."),
                          systemImage: fast ? "bolt.fill" : "hourglass")
                        .font(Theme.f(.footnote)).foregroundStyle(fast ? Theme.gold : Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(Theme.f(.footnote)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { go() } label: {
                    Text("دمج").font(Theme.title(17)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gold))
                }
                .buttonStyle(PressStyle())
                .disabled(urls.count < 2 || fast == nil)
                .opacity(urls.count < 2 || fast == nil ? 0.5 : 1)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }

    private func resultCard(_ out: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("تم الدمج", systemImage: "checkmark.seal.fill").font(Theme.f(.headline)).foregroundStyle(Color(red: 0.45, green: 0.80, blue: 0.62))
            Text(verbatim: out.lastPathComponent).font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white).lineLimit(2)
            if let sz = try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                Text(verbatim: sizeText(Int64(sz)) + (totalDuration > 0 ? " · " + durationText(totalDuration) : ""))
                    .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
            HStack(spacing: 10) {
                action("تشغيل", "play.fill") {
                    dismiss()
                    Task { try? await Task.sleep(nanoseconds: 400_000_000); FileOpener.open(out) }
                }
                action("مشاركة", "square.and.arrow.up") { FileOpener.share([out]) }
                action("تم", "checkmark") { dismiss() }
            }
            Text("حُفظ الملف المدموج بجانب أول ملف في الترتيب.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(L(title), systemImage: icon).font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Theme.cardHi))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: العمل

    private func load() async {
        let list = urls
        let video = isVideo
        // تحقق الدمج السريع مع تحميل الصور والمدد
        async let fastCheck = MediaTools.canMergeFast(list)
        for u in list {
            let a = AVURLAsset(url: u)
            let d = (try? await a.load(.duration).seconds) ?? 0
            let size = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            var thumb: UIImage?
            if video {
                let g = AVAssetImageGenerator(asset: a)
                g.appliesPreferredTrackTransform = true
                g.maximumSize = CGSize(width: 200, height: 200)
                if let cg = try? await g.image(at: CMTime(seconds: min(3, max(0, d / 2)), preferredTimescale: 600)).image {
                    thumb = UIImage(cgImage: cg)
                }
            }
            info[u] = Info(thumb: thumb, duration: d.isFinite ? d : 0, size: size)
        }
        fast = await fastCheck
    }

    private func go() {
        guard !running, urls.count >= 2 else { return }
        running = true; progress = 0; error = ""
        KeepAwake.begin()
        let bg = KeepAwake.Background("merge")
        let list = urls, isFast = fast ?? false
        job = Task {
            do {
                let out = try await MediaTools.merge(list, fast: isFast, progress: { v in Task { @MainActor in progress = v } })
                FileStore.shared.touch()
                withAnimation { result = out }
                done(LF("أُنشئ «%@»", out.lastPathComponent))
            } catch is CancellationError {
                error = L("أُلغي الدمج.")
            } catch {
                self.error = error.localizedDescription
            }
            running = false
            KeepAwake.end()
            bg.finish()
        }
    }
}
