import SwiftUI
import WidgetKit

// MARK: - معرض الويدجتات داخل التطبيق

/// أي قسم من المعرض مفتوح (الرئيسية تفتح قسم القفل مباشرة)
final class GalleryNav: ObservableObject {
    static let shared = GalleryNav()
    @Published var lock = SHOT_FILTER == LOCK_GROUP
    /// ويدجت مطلوب فتح صفحتها (من الضغط على الويدجت في الشاشة الرئيسية)
    @Published var open: String? = nil
}
let LOCK_GROUP = "شاشة القفل"
let FAV_GROUP = "المفضّلة"


struct GalleryView: View {
    @ObservedObject private var nav = GalleryNav.shared
    @State private var filter = SHOT_FILTER == LOCK_GROUP ? "الكل" : SHOT_FILTER
    @State private var selected: WInfo?
    @State private var weather: WeatherData? = Weather.cached()
    @State private var tint = Tint.appColor
    @State private var rev = 0
    @State private var stamp = 0
    @State private var favs = Styles.favorites
    private let homeGroups = Catalog.groups.filter { $0 != LOCK_GROUP }
    private var filters: [String] { ["الكل"] + (favs.isEmpty ? [] : [FAV_GROUP]) + homeGroups }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(title: "معرض الويدجت",
                               subtitle: LF("%@ ويدجت للشاشة الرئيسية و%@ لشاشة القفل", ar(Catalog.all.count), ar(Catalog.lock.count)))
                        .padding(.horizontal, 16)
                    HStack(spacing: 8) {
                        Chip(title: "الشاشة الرئيسية", icon: "iphone", on: !nav.lock) { withAnimation(.snappy) { nav.lock = false } }
                        Chip(title: "شاشة القفل", icon: "lock.fill", on: nav.lock) { withAnimation(.snappy) { nav.lock = true } }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)

                    TimelineView(.everyMinute) { tl in
                        if nav.lock {
                            VStack(alignment: .leading, spacing: 22) {
                                LockShowcase(date: tl.date)
                                GalleryContent(date: tl.date, weather: weather, tint: .white,
                                               groups: [LOCK_GROUP], showHeaders: false) { selected = $0 }
                            }
                            .padding(.horizontal, 16)
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                chips
                                GalleryContent(date: tl.date, weather: weather, tint: tint,
                                               groups: filter == "الكل" ? homeGroups : [filter],
                                               showHeaders: filter == "الكل") { selected = $0 }
                                    .padding(.horizontal, 16)
                                    .id(rev)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .barSpace()
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected, onDismiss: {
                rev += 1; tint = Tint.appColor; favs = Styles.favorites
                if filter == FAV_GROUP && favs.isEmpty { filter = "الكل" }
            }) { info in
                WidgetDetail(info: info, weather: weather)
            }
            .task {
                weather = await Weather.load()
                if !SHOT_WIDGET.isEmpty { selected = (Catalog.all + Catalog.lock).first { $0.id == SHOT_WIDGET } }
            }
            // لا نعيد رسم ١٠٠ معاينة في كل مرة تفتح التبويب — فقط إذا تغيّر التصميم أو اللون فعلًا (سبب التعليق)
            .onAppear {
                let s = Styles.stamp
                if s != stamp { stamp = s; tint = Tint.appColor; favs = Styles.favorites; rev += 1 }
                openRequested()
            }
            .onChange(of: nav.open) { _, _ in openRequested() }
        }
    }

    func openRequested() {
        guard let id = nav.open else { return }
        nav.open = nil
        if let w = (Catalog.all + Catalog.lock).first(where: { $0.id == id }) {
            nav.lock = Catalog.isLock(w.families[0])
            selected = w
        }
    }

    var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { f in
                    Chip(title: f, icon: f == FAV_GROUP ? "heart.fill" : nil, on: f == filter) {
                        withAnimation(.snappy) { filter = f }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - عرض توضيحي لشاشة القفل

struct LockShowcase: View {
    let date: Date

    private func item(_ id: String) -> WInfo? { Catalog.lock.first { $0.id == id } }

    private func render(_ id: String, _ family: WidgetFamily) -> some View {
        let size = WidgetPreview.size(family)
        let entry = HEntry(date: date, slot: .mm, size: size, tint: .white, greg: false,
                           weather: nil, preview: true, inApp: true, family: family)
        return Group {
            if let w = item(id) {
                w.render(entry)
                    .frame(width: size.width, height: size.height)
                    .foregroundStyle(.white)
                    .background {
                        if family == .accessoryCircular { Circle().fill(Color.white.opacity(0.14)) }
                    }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconTile(name: "lock.fill", color: Theme.goldDeep, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ويدجت شاشة القفل").font(Theme.title(17)).foregroundStyle(.white)
                    Text("تظهر على شاشة القفل أعلى الساعة أو أسفلها، دون فتح الجوال.")
                        .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
            }

            // محاكاة شاشة القفل
            ZStack(alignment: .top) {
                Color.clear
                VStack(spacing: 6) {
                    render("lock.inlinehijri", .accessoryInline)
                        .font(.system(size: 15, weight: .semibold))
                    Text(hm12(date))
                        .font(.system(size: 80, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.bottom, 4)
                    HStack(spacing: 10) {
                        render("lock.next", .accessoryRectangular)
                        render("lock.daycircle", .accessoryCircular)
                    }
                    .environment(\.layoutDirection, Lang.dir)
                }
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 290)
            .background { GlassPanel(corner: 30) }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)

            Label("تأخذ ويدجت القفل لون ساعة القفل تلقائيًا، ويُعرض السطر أعلى الساعة نصًّا عاديًّا بحسب قيود النظام.",
                  systemImage: "info.circle")
                .font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// شبكة الويدجتات (بدون تمرير) — تُستخدم في الشاشة وفي تصوير الصور
struct GalleryContent: View {
    let date: Date
    let weather: WeatherData?
    var tint: Color = .white
    var groups: [String] = Catalog.groups
    var showHeaders = true
    var onTap: (WInfo) -> Void = { _ in }

    /// المتوسط لحاله في الصف، والصغار كل اثنين جنب بعض
    private func rows(_ group: String) -> [[(WInfo, WidgetFamily)]] {
        var out: [[(WInfo, WidgetFamily)]] = []
        var pending: [(WInfo, WidgetFamily)] = []
        for w in Catalog.items(group) {
            for f in w.families {
                if f == .systemMedium || f == .systemLarge || f == .accessoryRectangular || f == .accessoryInline {
                    if !pending.isEmpty { out.append(pending); pending = [] }
                    out.append([(w, f)])
                } else {
                    pending.append((w, f))
                    if pending.count == 2 { out.append(pending); pending = [] }
                }
            }
        }
        if !pending.isEmpty { out.append(pending) }
        return out
    }

    var body: some View {
        // كسول: تُرسم المعاينات الظاهرة فقط ثم ما يقترب منها أثناء التمرير
        LazyVStack(alignment: .leading, spacing: 26) {
            ForEach(groups, id: \.self) { g in
                LazyVStack(alignment: .leading, spacing: 16) {
                    if showHeaders {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(L(g)).font(Theme.title(24)).foregroundStyle(.white)
                            Text(LF("%@ ويدجت", ar(Catalog.items(g).count)))
                                .font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                        }
                    }
                    ForEach(Array(rows(g).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, it in
                                Button { onTap(it.0) } label: {
                                    WidgetCard(info: it.0, family: it.1, date: date, weather: weather, tint: tint)
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .environment(\.layoutDirection, Lang.dir)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// رسم الويدجت نفسه بمقاسه الحقيقي
struct WidgetPreview: View {
    let info: WInfo
    let family: WidgetFamily
    let date: Date
    let weather: WeatherData?
    let tint: Color
    var greg = false
    /// تصميم للمعاينة (من المحرّر)؛ وبدونه يُعرض التصميم المحفوظ
    var style: WStyle? = nil

    /// مدخل المعاينة بالتصميم المحفوظ (أو تصميم المحرّر)
    private func makeEntry(_ size: CGSize) -> HEntry {
        let saved = Styles.get(info.id)
        let st = style ?? saved
        let t = style != nil ? tint : (saved.tint.map { Palette.color($0) } ?? tint)
        let slot: Slot = family == .systemMedium ? .mm : family == .systemLarge ? .lt : .mr
        var entry = HEntry(date: date, slot: slot, size: size, tint: t, greg: greg,
                           weather: weather, preview: true, inApp: true, family: family)
        entry.style = Catalog.isLock(family) ? WStyle() : st
        entry.kind = info.id
        return entry
    }

    static func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .accessoryRectangular: return CGSize(width: 172, height: 76)
        case .accessoryCircular: return CGSize(width: 76, height: 76)
        case .accessoryInline: return CGSize(width: 250, height: 22)
        case .systemLarge:
            let def = Backdrop.largeFrames(from: Backdrop.defaultFrames).first { $0.slot == .lt }
            return CGSize(width: def?.pw ?? 378, height: def?.ph ?? 394)
        default:
            let medium = family == .systemMedium
            let def = Backdrop.defaultFrames.first { $0.slot == (medium ? .mm : .mr) }
            return CGSize(width: def?.pw ?? (medium ? 378 : 176), height: def?.ph ?? 176)
        }
    }

    /// مقاس البطاقة اللي تنعرض فيها (ويدجتات القفل تنعرض فوق خلفية مثل شاشة القفل)
    static func tile(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .accessoryRectangular: return CGSize(width: 378, height: 120)
        case .accessoryCircular: return CGSize(width: 176, height: 130)
        case .accessoryInline: return CGSize(width: 378, height: 70)
        default: return size(family)
        }
    }

    var body: some View {
        let size = Self.size(family)
        let entry = makeEntry(size)
        if Catalog.isLock(family) {
            let t = Self.tile(family)
            ZStack {
                GlassPanel(corner: 24)
                info.render(entry)
                    .frame(width: size.width, height: size.height)
                    .foregroundStyle(.white)
                    .opacity(0.92)
                    .background {
                        if family == .accessoryCircular { Circle().fill(Color.white.opacity(0.14)) }
                    }
            }
            .frame(width: t.width, height: t.height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        } else {
            info.render(entry)
                .frame(width: size.width, height: size.height)
                .containerShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        }
    }
}

struct WidgetCard: View {
    let info: WInfo
    let family: WidgetFamily
    let date: Date
    let weather: WeatherData?
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            WidgetPreview(info: info, family: family, date: date, weather: weather, tint: tint)
                .frame(maxWidth: WidgetPreview.tile(family).width)
            HStack(spacing: 6) {
                Text(info.name).font(Theme.title(15)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).lineLimit(2)
                SizeBadge(text: Catalog.gridName(family))
            }
        }
    }
}

// MARK: - صفحة الويدجت: معاينة + تصميم خاص + طريقة الإضافة

struct WidgetDetail: View {
    let info: WInfo
    let weather: WeatherData?
    @Environment(\.dismiss) private var dismiss
    @State private var greg = false
    @State private var style: WStyle
    @State private var tint: Color
    @State private var fav: Bool
    @State private var custom: Bool
    @State private var msg = ""
    @State private var showSteps: Bool

    init(info: WInfo, weather: WeatherData?) {
        self.info = info
        self.weather = weather
        let st = Styles.get(info.id)
        _style = State(initialValue: st)
        _tint = State(initialValue: st.tint.map { Palette.color($0) } ?? Tint.appColor)
        _fav = State(initialValue: Styles.isFavorite(info.id))
        _custom = State(initialValue: Styles.hasCustom(info.id))
        _showSteps = State(initialValue: Catalog.isLock(info.families[0]))
    }

    private var isLock: Bool { Catalog.isLock(info.families[0]) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    TimelineView(.everyMinute) { tl in
                        VStack(spacing: 18) {
                            ForEach(info.families, id: \.self) { f in
                                WidgetPreview(info: info, family: f, date: tl.date, weather: weather, tint: tint, greg: greg,
                                              style: isLock ? nil : style)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .animation(.snappy, value: style)

                    VStack(spacing: 6) {
                        Text(info.name).font(Theme.title(24)).foregroundStyle(.white)
                        Text(info.desc).font(Theme.f(.subheadline)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                        HStack(spacing: 6) {
                            ForEach(info.families, id: \.self) { f in
                                Text(Catalog.gridName(f))
                                    .font(Theme.f(.caption)).foregroundStyle(Theme.gold)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().stroke(Theme.gold.opacity(0.5), lineWidth: 1))
                            }
                            if custom && !isLock {
                                Text("تصميم خاص")
                                    .font(Theme.f(.caption)).foregroundStyle(.black)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Theme.gold))
                            }
                        }
                        .padding(.top, 4)
                    }

                    if isLock {
                        Label("تأخذ ويدجت شاشة القفل لون ساعة القفل تلقائيًا، ويمكنك تغييره من «تخصيص» ثم الضغط على الساعة.",
                              systemImage: "paintpalette")
                            .font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(padding: 14)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("التصميم").font(Theme.title(17)).foregroundStyle(.white)
                                Spacer()
                                if info.hasCalendar {
                                    Picker("التقويم", selection: $greg) {
                                        Text("هجري").tag(false)
                                        Text("ميلادي").tag(true)
                                    }
                                    .pickerStyle(.segmented).frame(width: 150)
                                }
                            }
                            StyleEditor(style: $style, tint: $tint)
                        }
                        .glassCard()

                        VStack(spacing: 10) {
                            Button(action: save) {
                                Text("حفظ لهذه الويدجت").font(Theme.title(17)).foregroundStyle(.black)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(Capsule().fill(Theme.gold))
                            }
                            HStack(spacing: 10) {
                                Button(action: applyAll) {
                                    Text("تطبيق على الكل").font(Theme.f(.subheadline, .semibold)).foregroundStyle(.white)
                                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                                        .background(Capsule().fill(Theme.card))
                                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                                }
                                if custom {
                                    Button(action: reset) {
                                        Text("الرجوع للتصميم العام").font(Theme.f(.subheadline)).foregroundStyle(.red.opacity(0.9))
                                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                                            .background(Capsule().fill(Theme.card))
                                    }
                                }
                            }
                            if !msg.isEmpty {
                                Label(L(msg), systemImage: "checkmark.circle.fill").font(Theme.f(.footnote)).foregroundStyle(.green)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Button { withAnimation(.snappy) { showSteps.toggle() } } label: {
                            HStack {
                                Text("طريقة الإضافة").font(Theme.title(17)).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.down").rotationEffect(.degrees(showSteps ? 180 : 0))
                                    .foregroundStyle(Theme.sub)
                            }
                        }
                        .buttonStyle(.plain)
                        if showSteps { steps }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        Styles.toggleFavorite(info.id); fav.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: fav ? "heart.fill" : "heart").foregroundStyle(fav ? Color.red : Color.white)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, Lang.dir)
        .preferredColorScheme(.dark)
    }

    /// ويدجت الشاشة الرئيسية كلها داخل «رفيقي» بالمقاس؛ وويدجت القفل بنوعها
    private func reloadKind(_ info: WInfo) {
        if Catalog.isLock(info.families[0]) { WidgetCenter.shared.reloadTimelines(ofKind: info.id) } else { RafiqiKinds.reload() }
    }

    // ── الحفظ ──
    func save() {
        var s = style
        s.tint = Palette.same(Palette.rgb(tint), Palette.rgb(Tint.appColor)) ? nil : Palette.rgb(tint)
        Styles.set(info.id, s)
        custom = true
        reloadKind(info)
        msg = "تم الحفظ. إن اخترت خلفية أو خطًّا من «تعديل الأداة» فاختيارك هناك مقدَّم على هذا التصميم."
    }

    func applyAll() {
        var s = style; s.tint = nil
        Styles.global = s
        Tint.appColor = tint
        for w in Catalog.all { Styles.set(w.id, nil) }
        custom = false
        reloadWidgets()
        msg = "طُبّق هذا التصميم على جميع ويدجت الشاشة الرئيسية."
    }

    func reset() {
        Styles.set(info.id, nil)
        custom = false
        style = Styles.global
        tint = Tint.appColor
        reloadKind(info)
        msg = "عادت الويدجت إلى التصميم العام."
    }

    @ViewBuilder var steps: some View {
        if isLock {
            step(1, "افتح شاشة القفل، ثم اضغط مطوّلًا على أي مكان فيها حتى يظهر زر «تخصيص».")
            step(2, "اضغط «تخصيص»، ثم اختر «شاشة القفل».")
            step(3, info.families[0] == .accessoryInline
                 ? "اضغط على سطر التاريخ الظاهر أعلى الساعة."
                 : "اضغط على مربع الأدوات الظاهر أسفل الساعة.")
            step(4, "مرّر في قائمة التطبيقات حتى تجد «رفيقي»، ثم اضغط عليه.")
            step(5, LF("اضغط على «%@» لإضافتها", info.name) + (info.families[0] == .accessoryCircular
                 ? L("؛ ويتّسع الصف لأربع ويدجت دائرية أو اثنتين مستطيلتين.")
                 : info.families[0] == .accessoryRectangular ? L("؛ ويتّسع الصف لاثنتين مستطيلتين.") : "."))
            step(6, "اضغط «تم» للحفظ. تتّخذ الويدجت لون الساعة تلقائيًا.")
        } else {
            step(1, "اضغط مطوّلًا على مساحة فارغة في الشاشة الرئيسية حتى تهتز الأيقونات.")
            step(2, "اضغط «تعديل» أعلى الشاشة، ثم اختر «إضافة أداة».")
            step(3, "اكتب «رفيقي» في خانة البحث، ثم اضغط على التطبيق.")
            step(4, LF("اختر مقاس «%@»", Catalog.sizeName(info.families[0])) + (info.families.count > 1 ? L(" (أو أي مقاس متاح لها)") : "") + L("، ثم اضغط «إضافة أداة»، واسحبها إلى مكانها واضغط «تم»."))
            step(5, "اضغط مطوّلًا على الويدجت، ثم «تعديل الأداة».")
            step(6, LF("من «الويدجت» اختر «%@»", info.name) + (info.hasCalendar ? L("، ومن «التقويم» اختر الهجري أو الميلادي.") : "."))
            step(7, "لمطابقة الخلفية الشفافة حدّد «المكان» وفق موضع الويدجت، واضبط الخلفية من «الإعدادات» ← «الخلفية الشفافة» إن لم تُضبط بعد.")
        }
    }

    func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(ar(n)).font(Theme.f(.subheadline, .bold)).foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.gold))
            Text(L(text)).font(Theme.f(.subheadline)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - تصوير المعرض كصور طويلة (للمراجعة)

enum GalleryShots {
    @MainActor
    static func render(weather: WeatherData?) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for (i, g) in Catalog.groups.enumerated() {
            let view = GalleryContent(date: Date(), weather: weather, tint: Tint.appColor, groups: [g])
                .padding(16)
                .frame(width: Backdrop.screenPt.width)
                .background(AppBackground())
                .environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: view)
            // الصور الطويلة قد تتجاوز حد المقاس: نجرّب مقياسًا أقل حتى تنجح
            for sc in [3.0, 2.0, 1.5, 1.0] {
                r.scale = sc
                if let png = r.uiImage?.pngData() {
                    try? png.write(to: docs.appendingPathComponent("gallery_\(i).png"))
                    break
                }
            }
        }
        // معاينة الخطوط والخلفيات الأخرى (للمراجعة)
        let saved = Styles.global
        let looks: [(String, WFont, BgKind, DecoKind)] = [("naskh_glass", .naskh, .glass, .line),
                                                          ("ruqaa_grad", .ruqaa, .gradient, .stars),
                                                          ("kufi_dark", .kufi, .dark, .corners)]
        for (name, f, bg, deco) in looks {
            var st = WStyle(); st.font = f; st.bg = bg; st.deco = deco
            Styles.global = st
            for (i, g) in Catalog.groups.enumerated() where i < 3 {
                let view = GalleryContent(date: Date(), weather: weather, tint: Tint.appColor, groups: [g])
                    .padding(16)
                    .frame(width: Backdrop.screenPt.width)
                    .background(AppBackground())
                    .environment(\.colorScheme, .dark)
                let r = ImageRenderer(content: view)
                r.scale = 2
                if let png = r.uiImage?.pngData() {
                    try? png.write(to: docs.appendingPathComponent("gallery_\(name)_\(i).png"))
                }
            }
        }
        Styles.global = saved
    }

    /// مصفوفة المراجعة: كل ويدجت × كل مقاس × كل خط (أبيض)، ثم الألوان والتاريخ الميلادي — بلا خلفية
    @MainActor
    static func matrix(weather: WeatherData?) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("matrix")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        RenderDebug.bare = true
        defer { RenderDebug.bare = false }
        let tints: [(String, Color)] = [("white", .white), ("gold", Tint.color("gold")), ("glass", Tint.glassColor)]
        func fam(_ f: WidgetFamily) -> String {
            switch f {
            case .systemSmall: return "s"
            case .systemMedium: return "m"
            case .systemLarge: return "l"
            case .accessoryRectangular: return "ar"
            case .accessoryCircular: return "ac"
            case .accessoryInline: return "ai"
            default: return "x"
            }
        }
        func shot(_ info: WInfo, _ f: WidgetFamily, font: WFont, tint: (String, Color), greg: Bool) {
            let size = WidgetPreview.size(f)
            let slot: Slot = f == .systemMedium ? .mm : f == .systemLarge ? .lt : .mr
            var e = HEntry(date: Date(), slot: slot, size: size, tint: tint.1, greg: greg,
                           weather: weather, preview: true, inApp: false, family: f)
            var st = WStyle(); st.font = font
            e.style = st
            e.kind = info.id
            let lock = Catalog.isLock(f)
            let view = info.render(e)
                .frame(width: size.width, height: size.height)
                .foregroundStyle(lock ? Color.white : Color.primary)
                .environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: view)
            r.scale = 2
            r.isOpaque = false
            let name = "\(info.id)__\(fam(f))__\(font.rawValue)__\(tint.0)\(greg ? "__greg" : "").png"
            if let png = r.uiImage?.pngData() { try? png.write(to: dir.appendingPathComponent(name)) }
        }
        for info in Catalog.all {
            for f in info.families {
                if Catalog.isLock(f) {
                    shot(info, f, font: .thuluth, tint: tints[0], greg: false)
                    continue
                }
                for font in WFont.allCases { shot(info, f, font: font, tint: tints[0], greg: false) }
                for t in tints.dropFirst() { shot(info, f, font: .thuluth, tint: t, greg: false) }
                if info.hasCalendar { shot(info, f, font: .thuluth, tint: tints[0], greg: true) }
            }
        }
        try? "done".write(to: dir.appendingPathComponent("_done.txt"), atomically: true, encoding: .utf8)
    }
}
