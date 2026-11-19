import SwiftUI
import UIKit

/// أيقونات التطبيق البديلة (الأصلية تبقى الافتراضية)
enum AppIcons {
    struct Choice: Identifiable {
        let id: String          // اسم مجموعة الأيقونة في الأصول، فارغ = الأصلية
        let title: String
        let preview: String
    }
    static let all: [Choice] = [
        Choice(id: "", title: "الأصلية", preview: "AppIconPreview"),
        Choice(id: "AppIcon-Gold", title: "كحلي ذهبي", preview: "IconPreview-Gold"),
        Choice(id: "AppIcon-GoldBlack", title: "أسود ذهبي", preview: "IconPreview-GoldBlack"),
        Choice(id: "AppIcon-Navy", title: "ليلي ذهبي", preview: "IconPreview-Navy"),
        Choice(id: "AppIcon-Glass", title: "أزرق ليلي", preview: "IconPreview-Glass"),
        Choice(id: "AppIcon-Light", title: "أزرق فاتح", preview: "IconPreview-Light"),
        Choice(id: "AppIcon-Silver", title: "أسود فضي", preview: "IconPreview-Silver"),
    ]
    /// الأيقونة المستخدمة الآن (تُحفظ عند تغييرها وتُطابق مع النظام عند فتح الصفحة)
    static var currentID: String {
        get { UserDefaults.standard.string(forKey: "appIconName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "appIconName") }
    }
    /// صورة معاينة الأيقونة الحالية (لرأس الإعدادات ومعاينة الإشعار)
    static var currentPreview: String {
        all.first { $0.id == currentID }?.preview ?? "AppIconPreview"
    }
}

struct AppIconPicker: View {
    @State private var current = SHOT == "appicon" ? "AppIcon-Gold" : AppIcons.currentID
    @State private var error = ""
    /// طلب تغيير جارٍ: لا يُقبل غيره حتى ينتهي (تتداخل المحاولات فتختلف العلامة عن الأيقونة الفعلية)
    @State private var busy = false
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BackRow()
                PageHeader(title: "أيقونة التطبيق", subtitle: L("اختر شكل رفيقي على الشاشة الرئيسية"))
                LazyVGrid(columns: cols, spacing: 18) {
                    ForEach(AppIcons.all) { c in
                        Button { choose(c) } label: { cell(c) }
                            .disabled(busy)
                            .buttonStyle(PressStyle())
                            .accessibilityLabel(L(c.title))
                            .accessibilityAddTraits(c.id == current ? .isSelected : [])
                    }
                }
                if !error.isEmpty {
                    Text(error).font(Theme.f(.footnote)).foregroundStyle(.orange)
                }
                Text("يظهر تنبيه من النظام بعد التغيير، وهذا طبيعي. الأيقونة الجديدة تظهر فورًا على الشاشة الرئيسية وفي الإشعارات.")
                    .font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 120)
        }
        .background(AppBackground())
        .hiddenNavBar()
        .onAppear {
            guard SHOT != "appicon" else { return }
            let sys = UIApplication.shared.alternateIconName ?? ""
            if sys != AppIcons.currentID { AppIcons.currentID = sys }
            current = sys
        }
    }

    private func cell(_ c: AppIcons.Choice) -> some View {
        let on = c.id == current
        return VStack(spacing: 8) {
            Image(c.preview).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(on ? Theme.gold : Color.white.opacity(0.08), lineWidth: on ? 3 : 1))
                .overlay(alignment: .topTrailing) {
                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, Theme.gold)
                            .offset(x: 6, y: -6)
                    }
                }
            Text(L(c.title)).font(Theme.font(13, .semibold))
                .foregroundStyle(on ? Theme.gold : .white)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func choose(_ c: AppIcons.Choice) {
        guard c.id != current else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            error = L("هذا الجوال لا يدعم تغيير الأيقونة."); return
        }
        let prev = current
        current = c.id; error = ""; busy = true
        apply(c.id, attempt: 1) { ok in
            busy = false
            if ok { AppIcons.currentID = c.id }
            else { current = prev; error = L("تعذّر تغيير الأيقونة، حاول مرة أخرى.") }
        }
    }

    /// النظام يرفض الطلب أحيانًا إن جاء أثناء انتقال الشاشة أو قبل إغلاق تنبيه التغيير السابق، فيُعاد بمهلة متزايدة (حتى ٦ مرات)
    private func apply(_ id: String, attempt: Int, done: @escaping (Bool) -> Void) {
        UIApplication.shared.setAlternateIconName(id.isEmpty ? nil : id) { err in
            DispatchQueue.main.async {
                guard let err else { done(true); return }
                NSLog("RFDBG icon %@ attempt %d failed: %@", id, attempt, String(describing: err))
                if attempt < 6 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(attempt)) { apply(id, attempt: attempt + 1, done: done) }
                } else { done(false) }
            }
        }
    }
}
