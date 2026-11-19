import SwiftUI

// MARK: - جدول مواقيت الشهر، وإمساكية رمضان (مع تصدير PDF للطباعة أو المشاركة)

struct MonthlyTimetableView: View {
    @State private var hijri = true
    @State private var anchor = Date()
    @State private var pdf: URL?

    private struct Row: Identifiable {
        let id: Date
        let date: Date
        let h: DateComponents
        let g: DateComponents
        let times: [Date]   // الفجر، الشروق، الظهر، العصر، المغرب، العشاء
    }

    private var month: (first: Date, len: Int) { UQ.month(of: anchor, hijriMode: hijri) }
    private var isRamadan: Bool { hijri && UQ.h(month.first.addingTimeInterval(86400 * 2)).month == 9 }

    private var rows: [Row] {
        let (first, len) = month
        return (0..<len).compactMap { k in
            guard let d = Cal.gregCal.date(byAdding: .day, value: k, to: first) else { return nil }
            return Row(id: d, date: d, h: UQ.h(d), g: Cal.gregCal.dateComponents([.year, .month, .day], from: d), times: Prayer.times(for: d))
        }
    }

    private var title: String {
        let (first, _) = month
        if isRamadan { return L("إمساكية رمضان") + " " + ar(UQ.h(first).year ?? 0) }
        if hijri {
            let h = UQ.h(first.addingTimeInterval(86400 * 2))
            return UQ.monthName(h.month ?? 1, hijri: true) + " " + ar(h.year ?? 0)
        }
        let g = Cal.gregCal.dateComponents([.year, .month], from: first)
        return UQ.monthName(g.month ?? 1, hijri: false) + " " + ar(g.year ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                BackRow()
                PageHeader(title: "جدول المواقيت", subtitle: Settings.placeName + " · " + Settings.method.short) {
                    if let pdf {
                        ShareLink(item: pdf) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 40, height: 40).background(Circle().fill(Theme.cardHi))
                        }
                        .accessibilityLabel(L("مشاركة PDF"))
                    }
                }
                HStack(spacing: 8) {
                    Chip(title: "هجري", on: hijri) { withAnimation(.snappy) { hijri = true } }
                    Chip(title: "ميلادي", on: !hijri) { withAnimation(.snappy) { hijri = false } }
                    Spacer()
                    Chip(title: "رمضان", icon: "moon.stars", on: isRamadan) { withAnimation(.snappy) { jumpToRamadan() } }
                }
                HStack {
                    CircleButton(icon: Lang.isEN ? "chevron.left" : "chevron.right", size: 36) { shift(-1) }
                    Spacer()
                    Text(verbatim: title).font(Theme.title(20)).foregroundStyle(.white)
                    Spacer()
                    CircleButton(icon: Lang.isEN ? "chevron.right" : "chevron.left", size: 36) { shift(1) }
                }
                table(print: false)
                    .glassCard(padding: 8)
                if isRamadan {
                    Text("الإمساك قبل الفجر بعشر دقائق احتياطًا، والصيام يبدأ من أذان الفجر.")
                        .font(Theme.f(.caption)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .barSpace()
        .background(AppBackground())
        .hiddenNavBar()
        .task(id: "\(hijri)\(month.first.timeIntervalSince1970)") { pdf = makePDF() }
    }

    // ── الجدول (للشاشة وللطباعة) ──
    @ViewBuilder private func table(print: Bool) -> some View {
        let fg: Color = print ? .black : .white
        let sub: Color = print ? Color(white: 0.35) : Theme.sub
        let accent: Color = print ? Color(red: 0.55, green: 0.42, blue: 0.12) : Theme.gold
        let heads = (isRamadan ? ["الإمساك"] : []) + ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("اليوم").frame(width: print ? 120 : 76, alignment: .leading)
                ForEach(heads, id: \.self) { Text(L($0)).frame(maxWidth: .infinity) }
            }
            .font(Theme.font(print ? 12 : 11, .bold)).foregroundStyle(accent)
            .padding(.vertical, 8)
            ForEach(rows) { r in
                let today = Cal.gregCal.isDateInToday(r.date)
                let friday = Cal.weekday(r.date) == 5
                let t = isRamadan ? [r.times[0].addingTimeInterval(-600)] + r.times : r.times
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: (Lang.isEN ? Words.wdEN : Words.wd)[Cal.weekday(r.date)]).font(Theme.font(print ? 11 : 10, .bold))
                        Text(verbatim: hijri ? "\(ar(r.h.day ?? 1)) · \(ar(r.g.day ?? 1))/\(ar(r.g.month ?? 1))"
                                             : "\(ar(r.g.day ?? 1)) · \(ar(r.h.day ?? 1)) \(UQ.monthName(r.h.month ?? 1, hijri: true))")
                            .font(Theme.font(print ? 10 : 9, .medium)).foregroundStyle(sub).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: print ? 120 : 76, alignment: .leading)
                    ForEach(Array(t.enumerated()), id: \.offset) { _, d in
                        Text(verbatim: hm12(d)).font(Theme.font(print ? 12 : 11.5, .medium).monospacedDigit()).frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(friday ? accent : fg)
                .padding(.vertical, 6).padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(today ? accent.opacity(print ? 0.15 : 0.18) : (print ? Color.clear : Color.clear)))
                .overlay(alignment: .bottom) { Rectangle().fill(print ? Color(white: 0.85) : Theme.stroke).frame(height: 0.5) }
            }
        }
        .environment(\.layoutDirection, Lang.dir)
    }

    private func shift(_ n: Int) {
        let (first, _) = month
        let mid = first.addingTimeInterval(14 * 86400)
        let c = hijri ? UQ.hijri : UQ.greg
        let base = hijri ? UQ.shift(mid, Settings.hijriOffset) : mid
        let moved = c.date(byAdding: .month, value: n, to: base) ?? base
        withAnimation(.snappy) { anchor = hijri ? UQ.shift(moved, -Settings.hijriOffset) : moved }
    }

    /// رمضان القادم (أو الحالي)
    private func jumpToRamadan() {
        hijri = true
        let h = UQ.h(Date())
        let y = (h.month ?? 1) <= 9 ? (h.year ?? 1448) : (h.year ?? 1448) + 1
        if let d = UQ.hijri.date(from: DateComponents(year: y, month: 9, day: 10)) { anchor = UQ.shift(d, -Settings.hijriOffset) }
    }

    /// ملف PDF بمقاس A4 للطباعة أو المشاركة
    @MainActor private func makePDF() -> URL? {
        let page = CGSize(width: 595, height: 842)
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(Theme.title(20)).foregroundStyle(.black)
                    Text(verbatim: Settings.placeName + " · " + Settings.method.name).font(Theme.font(11)).foregroundStyle(Color(white: 0.35))
                }
                Spacer()
                Text("رفيقي").font(Theme.title(14)).foregroundStyle(Color(red: 0.55, green: 0.42, blue: 0.12))
            }
            table(print: true)
        }
        .padding(28)
        .frame(width: page.width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: content)
        r.proposedSize = ProposedViewSize(width: page.width, height: nil)
        let name = title.replacingOccurrences(of: "/", with: "-") + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var box = CGRect(origin: .zero, size: page)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        r.render { size, draw in
            // يُصغَّر ليتسع في صفحة A4 واحدة
            let k = min(1, page.height / max(1, size.height))
            ctx.beginPDFPage(nil)
            ctx.translateBy(x: (page.width - size.width * k) / 2, y: page.height - size.height * k)
            ctx.scaleBy(x: k, y: k)
            draw(ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }
}
