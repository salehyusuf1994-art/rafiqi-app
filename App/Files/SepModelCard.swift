import SwiftUI

/// بطاقة النموذج عالي الدقة في أداتي «إزالة الموسيقى» و«إزالة الصوت البشري»
struct SepModelCard: View {
    @ObservedObject private var store = SepModelStore.shared
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch store.state {
            case .ready:
                Label("النموذج عالي الدقة جاهز", systemImage: "checkmark.seal.fill")
                    .font(Theme.f(.subheadline, .semibold)).foregroundStyle(Color(red: 0.45, green: 0.80, blue: 0.62))
                Text("يُستخدم تلقائيًا: أدق نموذج مفتوح متاح لعزل الصوت البشري (BS-RoFormer). يعمل على جوالك بدون إنترنت.")
                    .font(Theme.f(.caption)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
                if let plan = store.planSummary {
                    Label(LF("يعمل على: %@", plan), systemImage: "cpu").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(LF("حذف النموذج (%@)", sizeText(SepModelFiles.totalSize)), systemImage: "trash").font(Theme.f(.caption, .semibold))
                }
                .foregroundStyle(.red.opacity(0.9))
            case .missing, .failed:
                Label("لأعلى دقة: نزّل النموذج المتقدم", systemImage: "sparkles")
                    .font(Theme.f(.subheadline, .semibold)).foregroundStyle(Theme.gold)
                Text(LF("ينزل مرة واحدة (%@ تقريبًا) ويبقى في جوالك، وبعدها يعمل بدون إنترنت. يبقي الصوت البشري كاملًا ولا يترك موسيقى بدقة أعلى بكثير من النموذج المضمّن.", sizeText(SepModelFiles.totalSize)))
                    .font(Theme.f(.caption)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
                if case .failed(let m) = store.state {
                    Label(m, systemImage: "exclamationmark.triangle.fill").font(Theme.f(.caption)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { store.download() } label: {
                    Label("تنزيل النموذج", systemImage: "arrow.down.circle.fill").font(Theme.f(.subheadline, .semibold))
                        .foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.gold))
                }
                .buttonStyle(PressStyle())
                Text("بدون تنزيل: يُستخدم النموذج المضمّن (أقل دقة).").font(Theme.f(.caption2)).foregroundStyle(Theme.sub)
            case .downloading(let v):
                ProgressView(value: v).tint(Theme.gold)
                HStack {
                    Text(LF("جارٍ تنزيل النموذج… %@٪", ar(Int(v * 100)))).font(Theme.f(.subheadline)).foregroundStyle(.white)
                    Spacer()
                    Button("إلغاء") { store.cancel() }.font(Theme.f(.subheadline, .semibold)).foregroundStyle(Theme.gold)
                }
                Text("أبقِ التطبيق مفتوحًا حتى ينتهي.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            case .preparing:
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.gold)
                    Text("جارٍ تجهيز النموذج لأول مرة…").font(Theme.f(.subheadline)).foregroundStyle(.white)
                }
                Text("لحظات، ومرة واحدة فقط. أبقِ التطبيق مفتوحًا.").font(Theme.f(.caption)).foregroundStyle(Theme.sub)
            }
        }
        .confirmationDialog("حذف النموذج عالي الدقة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { store.delete() }
        } message: {
            Text("يمكنك تنزيله مرة أخرى في أي وقت. حتى ذلك يُستخدم النموذج المضمّن.")
        }
    }
}
