import SwiftUI
import WidgetKit

// MARK: - محرّر تصميم الويدجت (الخلفية، الخط، الزخرفة، اللون)

/// اختيار ملوّن بحلقة حمراء حول المختار (القاعدة المعتمدة في التطبيق)
struct Swatch<Fill: ShapeStyle>: View {
    let fill: Fill
    let on: Bool
    var size: CGFloat = 32
    var body: some View {
        Circle().fill(fill).frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .overlay(Circle().stroke(Color.red, lineWidth: 2.5).padding(-5).opacity(on ? 1 : 0))
            .padding(5)
    }
}

/// بلاطة اختيار بأيقونة ونص
struct ChoiceTile<Icon: View>: View {
    let title: String
    let on: Bool
    @ViewBuilder let icon: () -> Icon
    var body: some View {
        VStack(spacing: 6) {
            icon()
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Theme.gold.opacity(0.18) : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(on ? Theme.gold : Theme.stroke, lineWidth: on ? 1.5 : 1))
            Text(title).font(Theme.f(.caption2, on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.gold : .white.opacity(0.8)).lineLimit(1)
        }
    }
}

struct StyleEditor: View {
    @Binding var style: WStyle
    @Binding var tint: Color
    @State private var tab = 0

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("القسم", selection: $tab) {
                Text("الخلفية").tag(0)
                Text("الخط").tag(1)
                Text("الزخرفة").tag(2)
                Text("اللون").tag(3)
            }
            .pickerStyle(.segmented)

            switch tab {
            case 0: background
            case 1: fonts
            case 2: decoration
            default: colors
            }
        }
        .animation(.snappy, value: tab)
    }

    // ── الخلفية ──
    var background: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(BgKind.allCases) { k in
                    Button { withAnimation(.snappy) { style.bg = k } } label: {
                        ChoiceTile(title: k.title, on: style.bg == k) {
                            Image(systemName: k.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if style.bg == .color {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Palette.solids.indices, id: \.self) { i in
                            let p = Palette.solids[i]
                            Button { style.color = p.1 } label: { Swatch(fill: Palette.color(p.1), on: Palette.same(p.1, style.color)) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                ColorPicker(selection: Binding(get: { Palette.color(style.color) }, set: { style.color = Palette.rgb($0) }),
                            supportsOpacity: false) {
                    Label("لون مخصّص", systemImage: "eyedropper.halffull").font(Theme.f(.subheadline)).foregroundStyle(.white)
                }
            }
            if style.bg == .gradient {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Palette.gradients.indices, id: \.self) { i in
                            Button { style.grad = i } label: {
                                Swatch(fill: LinearGradient(colors: Palette.gradient(i), startPoint: .topLeading, endPoint: .bottomTrailing),
                                       on: style.grad == i)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if style.bg != .clear {
                VStack(alignment: .leading, spacing: 4) {
                    Text(style.bg == .glass ? "قوة التمويه" : "درجة التعتيم").font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                    Slider(value: $style.strength, in: 0...1).tint(Theme.gold)
                }
            }
            Text(L(bgNote)).font(Theme.f(.caption)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
        }
    }

    var bgNote: String {
        switch style.bg {
        case .clear: return "تندمج الويدجت مع خلفية الشاشة، وتحتاج إلى ضبط «الخلفية الشفافة» من الإعدادات."
        case .glass: return "زجاج مموّه من خلفية شاشتك نفسها، فيبقى منسجمًا مع أي خلفية."
        case .dark: return "تعتيم فوق الخلفية يُبرز الخط على الخلفيات الفاتحة."
        case .color: return "لون ثابت فوق الخلفية، وكلما قلّ التعتيم ظهرت الخلفية من خلفه."
        case .gradient: return "تدرّج لوني فوق الخلفية."
        }
    }

    // ── الخط ──
    var fonts: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(WFont.allCases) { f in
                let on = style.font == f
                Button { style.font = f } label: {
                    VStack(spacing: 4) {
                        Group {
                            if f == .thuluth {
                                Fit("wd5_t", 110, 38)
                            } else {
                                Text("الجمعة").font(.custom(f.ps, size: 26)).foregroundStyle(TXT)
                                    .lineLimit(1).minimumScaleFactor(0.5)
                            }
                        }
                        .frame(height: 46)
                        Text(f.title).font(Theme.f(.caption, on ? .semibold : .regular))
                            .foregroundStyle(on ? Theme.gold : Theme.sub)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Theme.gold.opacity(0.14) : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(on ? Theme.gold : Theme.stroke, lineWidth: on ? 1.5 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── الزخرفة ──
    var decoration: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(DecoKind.allCases) { k in
                    Button { withAnimation(.snappy) { style.deco = k } } label: {
                        ChoiceTile(title: k.title, on: style.deco == k) {
                            ZStack {
                                if k == .off {
                                    Image(systemName: "nosign").foregroundStyle(Theme.sub)
                                } else {
                                    DecoView(kind: k, opacity: 0.9)
                                        .frame(width: 64, height: 40)
                                        .containerShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .scaleEffect(0.9)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if style.deco != .off {
                VStack(alignment: .leading, spacing: 4) {
                    Text("وضوح الزخرفة").font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                    Slider(value: $style.decoOpacity, in: 0.15...1).tint(Theme.gold)
                }
            }
            Text("تأخذ الزخرفة لون الخط نفسه.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
        }
    }

    // ── لون الخط ──
    var colors: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Tint.presets, id: \.0) { p in
                        Button { tint = p.2 } label: {
                            VStack(spacing: 2) {
                                Swatch(fill: p.2, on: UIColor(p.2) == UIColor(tint) || Palette.same(Palette.rgb(p.2), Palette.rgb(tint)))
                                Text(L(p.1)).font(Theme.f(.caption2)).foregroundStyle(Theme.sub)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ColorPicker(selection: $tint, supportsOpacity: false) {
                Label("لون مخصّص", systemImage: "eyedropper.halffull").font(Theme.f(.subheadline)).foregroundStyle(.white)
            }
        }
    }
}

// MARK: - صفحة «التصميم العام» من الإعدادات

struct GlobalStyleView: View {
    @State private var style = Styles.global
    @State private var tint = Tint.appColor
    @State private var msg = ""
    @State private var customCount = (Catalog.all).filter { Styles.hasCustom($0.id) }.count

    private let sampleS = Catalog.all.first { $0.id == "hilal.dnum" }
    private let sampleM = Catalog.all.first { $0.id == "hilal.both" }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 60)) { tl in
                    VStack(spacing: 14) {
                        if let m = sampleM {
                            WidgetPreview(info: m, family: .systemMedium, date: tl.date, weather: nil, tint: tint, style: style)
                        }
                    }
                }
                .padding(.top, 8)

                StyleEditor(style: $style, tint: $tint).glassCard()

                VStack(spacing: 10) {
                    Button {
                        var s = style; s.tint = nil
                        Styles.global = s
                        Tint.appColor = tint
                        reloadWidgets()
                        msg = "تم الحفظ، وطُبّق على كل ويدجت ليس لها تصميم خاص."
                    } label: {
                        Text("حفظ التصميم العام").font(Theme.title(17)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(Theme.gold))
                    }
                    if customCount > 0 {
                        Button(role: .destructive) {
                            for w in Catalog.all { Styles.set(w.id, nil) }
                            customCount = 0
                            reloadWidgets()
                            msg = "أُلغيت التصاميم الخاصة، وأصبحت كل الويدجت على التصميم العام."
                        } label: {
                            Text("إلغاء التصاميم الخاصة (\(ar(customCount)))").font(Theme.f(.subheadline))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                    }
                    if !msg.isEmpty {
                        Label(L(msg), systemImage: "checkmark.circle.fill").font(Theme.f(.footnote)).foregroundStyle(.green)
                    }
                    Text("يُطبَّق على جميع الويدجت، ويمكنك تخصيص أي ويدجت بمفردها من صفحتها في «الويدجت».")
                        .font(Theme.f(.caption)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle("التصميم العام")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - الخطوط وتراخيصها

struct FontsAbout: View {
    private func credit(_ f: WFont) -> String {
        switch f {
        case .thuluth: return "خط الثلث الأساسي لتطبيق رفيقي"
        case .naskh: return "أميري — مشروع أليف تايب"
        case .ruqaa: return "عارف رقعة — مشروع أليف تايب"
        case .ruwudu: return "رُوُدو — SIL International"
        case .kufi: return "ريم كوفي — مشروع أليف تايب"
        case .nastaliq: return "النستعليق (جلزار) — مشروع Gulzar"
        case .katibeh: return "كاتبة — KB-Studio"
        case .blaka: return "بلاكا — مشروع بلاكا"
        case .tajawal: return "تجوّل — بطرس للخطوط"
        case .readex: return "ريدكس برو — مشروع ريدكس برو"
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(WFont.allCases) { f in
                    HStack(spacing: 12) {
                        Group {
                            if f == .thuluth { Fit("wd5_t", 90, 34) } else {
                                Text("الجمعة").font(.custom(f.ps, size: 22)).foregroundStyle(TXT).lineLimit(1).minimumScaleFactor(0.5)
                            }
                        }
                        .frame(width: 96, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).foregroundStyle(.white)
                            Text(L(credit(f))).font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                        }
                    }
                }
            } footer: {
                Text("جميع الخطوط الإضافية مجانية ومرخّصة برخصة SIL Open Font License 1.1، وتُستخدم دون تعديل في أسمائها المحجوزة.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .navigationTitle("الخطوط")
        .navigationBarTitleDisplayMode(.inline)
    }
}
