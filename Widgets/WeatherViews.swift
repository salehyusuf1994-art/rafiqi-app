import SwiftUI
import WidgetKit

struct HiLo: View {
    let w: WeatherData?
    let size: CGFloat
    var body: some View {
        let lh = size * 1.1
        HStack(spacing: 4) {
            Fit("hi_t", lh, lh, 0.9)
            Digits(text: Weather.deg(w?.hi), size: size, color: TXT)
            Color.clear.frame(width: 8, height: 1)
            Fit("lo_t", lh, lh, 0.9)
            Digits(text: Weather.deg(w?.lo), size: size, color: TXT)
        }
    }
}

struct WxIcon: View {
    let w: WeatherData?
    let size: CGFloat
    var body: some View {
        if let u = Calli.ui(Weather.icon(w)) {
            SImage(img: u).frame(width: size, height: size)
        }
    }
}

// MARK: - الطقس — صغير: الرمز ثم الحرارة ثم الحالة، في النص

struct WeatherSimpleView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        Root(entry: entry) {
            VStack(spacing: 10) {
                WxIcon(w: w, size: 52)
                Digits(text: Weather.deg(w?.temp), size: 54, color: .white, tight: true)
                Fit(Weather.word(w), 110, 32)
            }
        }
    }
}

// MARK: - الطقس مع العظمى والصغرى — صغير: كل شي على اليمين

struct WeatherCompactView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        Root(entry: entry) {
            VStack(alignment: .leading, spacing: 0) {
                CityLabel(maxW: 140, maxH: 32)
                Digits(text: Weather.deg(w?.temp), size: 52, color: .white, tight: true)
                    .padding(.top, 10)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    WxIcon(w: w, size: 24)
                    Fit(Weather.word(w), 80, 26)
                }
                HiLo(w: w, size: 15).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
        }
    }
}

// MARK: - الطقس والتاريخ الهجري — متوسط: الطقس يمين، الرمز والحالة يسار

struct WeatherDetailView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        let h = Cal.dmy(entry.date, greg: false)
        let r1 = ["pn\(h.d)", "hm\(h.m)"]
        Root(entry: entry) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    CityLabel(maxW: 180, maxH: 40)
                    Digits(text: Weather.deg(w?.temp), size: 60, color: .white, tight: true)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                    CLine(names: r1, s: min(0.45, 190 / lineWidth(r1, GAP_PX, 1)))
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    WxIcon(w: w, size: 70)
                    Fit(Weather.word(w), 110, 30)
                    HiLo(w: w, size: 15)
                }
                .frame(width: 130)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - طقس مع اسم اليوم بالثلث — متوسط

struct WeatherThuluthView: View {
    let entry: HEntry
    var body: some View {
        let w = entry.weather
        let h = Cal.dmy(entry.date, greg: false)
        let r1 = ["pn\(h.d)", "hm\(h.m)", "hyl\(clampY(h.y, 1440, 1470))"]
        Root(entry: entry) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Fit("wd\(Cal.weekday(entry.date))_t", 190, 76)
                    CLine(names: r1, s: min(0.5, 196 / lineWidth(r1, GAP_PX, 1)))
                }
                .frame(width: 196, alignment: .leading)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    CityLabel(maxW: 140, maxH: 38)
                    HStack(spacing: 6) {
                        Digits(text: Weather.deg(w?.temp), size: 46, color: .white, tight: true)
                        WxIcon(w: w, size: 34)
                    }
                    HiLo(w: w, size: 15)
                }
                .frame(width: 140, alignment: .trailing)
            }
            .padding(16)
        }
    }
}
