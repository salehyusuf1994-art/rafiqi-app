import SwiftUI
import MapKit

// MARK: - اختيار المدينة: كل مدن وقرى المملكة (بلا إنترنت)، وأي مدينة في العالم بالبحث في خرائط أبل

struct PickedPlace {
    let name: String
    let lat: Double
    let lng: Double
    /// المنطقة الزمنية للمكان
    let tz: String
}

struct CityPicker: View {
    var onPick: (PickedPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var world: [MKMapItem] = []
    @State private var searchingWorld = false

    private var results: [Places.City] {
        let k = Places.norm(q.trimmingCharacters(in: .whitespaces))
        guard !k.isEmpty else { return [] }
        let all = Places.cities.filter { Places.norm($0.name).contains(k) }
        // اللي يبدأ بالكلمة أول
        return all.sorted { a, b in
            let pa = Places.norm(a.name).hasPrefix(k), pb = Places.norm(b.name).hasPrefix(k)
            return pa != pb ? pa : a.name.count < b.name.count
        }
    }

    var body: some View {
        List {
            if q.isEmpty {
                Section("المدن الرئيسية") {
                    ForEach(Places.major) { row($0) }
                }
                ForEach(Array(Places.regions.enumerated()), id: \.offset) { i, r in
                    Section {
                        DisclosureGroup {
                            ForEach(Places.cities.filter { $0.region == i }.sorted { $0.name < $1.name }) { row($0, showRegion: false) }
                        } label: {
                            HStack {
                                Text(LF("منطقة %@", r)).foregroundStyle(.white)
                                Spacer()
                                Text(ar(Places.cities.filter { $0.region == i }.count)).font(.caption).foregroundStyle(Theme.sub)
                            }
                        }
                    }
                }
            } else {
                let res = results
                if !res.isEmpty {
                    Section("مدن المملكة") {
                        ForEach(res.prefix(300)) { row($0) }
                    }
                }
                Section {
                    if searchingWorld { ProgressView().frame(maxWidth: .infinity) }
                    ForEach(world, id: \.self) { worldRow($0) }
                    if res.isEmpty && world.isEmpty && !searchingWorld {
                        Text("لا توجد نتائج لـ«\(q)»").foregroundStyle(Theme.sub)
                    }
                } header: {
                    Text("مدن العالم")
                } footer: {
                    Text("البحث في مدن العالم من خرائط أبل، ويحتاج اتصالًا بالإنترنت.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .barSpace()
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "ابحث عن مدينة في المملكة أو العالم")
        .task(id: q) { await searchWorld() }
        .navigationTitle("اختيار المدينة")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// البحث في مدن العالم (بعد توقّف الكتابة لحظة)
    func searchWorld() async {
        let text = q.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { world = []; searchingWorld = false; return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }
        searchingWorld = true
        let r = MKLocalSearch.Request()
        r.naturalLanguageQuery = text
        r.resultTypes = .address
        let items = (try? await MKLocalSearch(request: r).start())?.mapItems ?? []
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        world = items.filter { it in
            let key = worldName(it)
            return !key.isEmpty && seen.insert(key).inserted
        }
        searchingWorld = false
    }

    func worldName(_ it: MKMapItem) -> String {
        let p = it.placemark
        let city = p.locality ?? p.administrativeArea ?? it.name ?? ""
        guard !city.isEmpty else { return "" }
        if let cc = p.isoCountryCode, cc != "SA", let country = p.country, country != city {
            return city + (Lang.isEN ? ", " : "، ") + country
        }
        return city
    }

    func worldRow(_ it: MKMapItem) -> some View {
        let p = it.placemark
        return Button {
            onPick(PickedPlace(name: worldName(it), lat: p.coordinate.latitude, lng: p.coordinate.longitude,
                               tz: it.timeZone?.identifier ?? TimeZone.current.identifier))
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(worldName(it)).foregroundStyle(.white)
                    if let area = p.administrativeArea, area != p.locality {
                        Text(area).font(.caption).foregroundStyle(Theme.sub)
                    }
                }
            }
        }
    }

    func row(_ c: Places.City, showRegion: Bool = true) -> some View {
        Button {
            onPick(PickedPlace(name: c.name, lat: c.lat, lng: c.lng, tz: "Asia/Riyadh"))
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).foregroundStyle(.white)
                    if showRegion, Places.regions.indices.contains(c.region) {
                        Text(LF("منطقة %@", Places.regions[c.region])).font(.caption).foregroundStyle(Theme.sub)
                    }
                }
                Spacer()
                if abs(c.lat - Settings.lat) < 0.0005 && abs(c.lng - Settings.lng) < 0.0005 && !Settings.isAuto {
                    Image(systemName: "checkmark").foregroundStyle(Theme.gold)
                }
            }
        }
    }
}
