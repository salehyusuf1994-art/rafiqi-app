import SwiftUI

// MARK: - إعدادات إدارة الملفات

struct FilesSettingsView: View {
    @ObservedObject private var store = FileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var autoPhotos = FilePrefs.autoPhotos
    @State private var folderMode = FilePrefs.folderMode
    @State private var lockTab = FilePrefs.lockTab
    @State private var skip = FilePrefs.skip
    @State private var autoNext = FilePrefs.autoNext
    @State private var usage: (files: Int64, trash: Int64, temp: Int64, free: Int64) = (0, 0, 0, 0)
    @State private var cleared = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    stat(L("ملفاتي"), usage.files)
                    stat(L("سلة المحذوفات"), usage.trash)
                    stat(L("المساحة المتاحة في الجوال"), usage.free)
                } header: { Text("التخزين") }

                Section {
                    Picker(selection: $folderMode) {
                        Text("بدون").tag(0)
                        Text("حسب النوع").tag(1)
                        Text("حسب الموقع").tag(2)
                    } label: { TileRow(title: "ترتيب التنزيلات في مجلدات", icon: "folder.badge.gearshape", subtitle: "داخل مجلد «التنزيلات»") }
                    Toggle(isOn: $autoPhotos) { TileRow(title: "حفظ في «الصور» بعد التنزيل", icon: "photo.on.rectangle", subtitle: "للصور ومقاطع الفيديو المنزّلة") }
                } header: { Text("التنزيلات") }

                Section {
                    Picker(selection: $skip) {
                        ForEach([5, 10, 15, 30], id: \.self) { Text(LF($0 <= 10 ? "%@ ثوانٍ" : "%@ ثانية", ar($0))).tag($0) }
                    } label: { TileRow(title: "التقديم والترجيع", icon: "goforward") }
                    Toggle(isOn: $autoNext) { TileRow(title: "تشغيل الملف التالي تلقائيًا", icon: "text.line.first.and.arrowtriangle.forward") }
                } header: { Text("المشغّل") } footer: {
                    Text("اضغط مرتين على يمين الفيديو أو يساره للتقديم أو الترجيع. ضع ملف ترجمة (SRT) بنفس اسم الفيديو في المجلد نفسه ليظهر تلقائيًا.")
                }

                Section {
                    Toggle(isOn: $lockTab) { TileRow(title: "قفل إدارة الملفات", icon: "faceid", subtitle: "يطلب بصمة الوجه أو رمز الجوال عند فتحها") }
                } header: { Text("الحماية") } footer: {
                    Text("يمكنك أيضًا قفل مجلد بعينه من قائمة «…» الخاصة به.")
                }

                Section {
                    Button {
                        store.clearTemp(); cleared = true; refresh()
                    } label: {
                        HStack {
                            TileRow(title: "حذف الملفات المؤقتة", icon: "trash", subtitle: "لا تتأثر ملفاتك ولا تنزيلاتك")
                            Text(verbatim: sizeText(usage.temp)).font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    if cleared { Text("حُذفت الملفات المؤقتة.") }
                }

                Section {
                    Text("ملفاتك محفوظة داخل جوالك فقط. تجدها أيضًا في تطبيق «الملفات» ← «على الـiPhone» ← «رفيقي»، ومنه تقدر تنقلها إلى iCloud Drive. ولإرسال ملف إلى رفيقي من أي تطبيق: «مشاركة» ← «رفيقي».")
                        .font(Theme.f(.footnote)).foregroundStyle(Theme.sub)
                }
            }
            .glassList()
            .tint(Theme.gold)
            .navigationTitle("إعدادات الملفات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .onAppear(perform: refresh)
            .onChange(of: autoPhotos) { _, v in FilePrefs.autoPhotos = v }
            .onChange(of: folderMode) { _, v in FilePrefs.folderMode = v }
            .onChange(of: skip) { _, v in FilePrefs.skip = v }
            .onChange(of: autoNext) { _, v in FilePrefs.autoNext = v }
            .onChange(of: lockTab) { _, v in
                Task {
                    if await FileStore.authenticate(v ? L("تفعيل قفل إدارة الملفات") : L("إلغاء قفل إدارة الملفات")) { FilePrefs.lockTab = v }
                    else { lockTab = FilePrefs.lockTab }
                }
            }
        }
    }

    private func stat(_ t: String, _ v: Int64) -> some View {
        HStack {
            Text(verbatim: t).foregroundStyle(.white)
            Spacer()
            Text(verbatim: sizeText(v)).foregroundStyle(Theme.sub)
        }
    }

    private func refresh() {
        Task.detached {
            let u = await FileStore.shared.usage()
            await MainActor.run { usage = u }
        }
    }
}
