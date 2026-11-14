import SwiftUI
import WidgetKit

/// قائمة الويدجتات: الاسم والوصف والأحجام وطريقة الرسم.
/// يستخدمها امتداد الويدجتات ومعرض الويدجتات داخل التطبيق.
struct WInfo: Identifiable {
    let id: String
    let group: String
    let name: String
    let desc: String
    let families: [WidgetFamily]
    let sched: Sched
    let hasCalendar: Bool
    let render: (HEntry) -> AnyView
}

enum Catalog {
    static let groups = ["التاريخ", "الصلاة", "الساعة", "الطقس", "القرآن", "الوسائط", "القنوات", "المباريات", "شاشة القفل"]

    private static func w<V: View>(_ id: String, _ group: String, _ name: String, _ desc: String,
                                   _ families: [WidgetFamily], _ sched: Sched, cal: Bool = false,
                                   @ViewBuilder _ v: @escaping (HEntry) -> V) -> WInfo {
        WInfo(id: id, group: group, name: L(name), desc: L(desc), families: families, sched: sched, hasCalendar: cal,
              render: { AnyView(v($0)) })
    }

    static let all: [WInfo] = [
        // ── التاريخ ──
        w("hilal.date", "التاريخ", "التاريخ الهجري", "اليوم والشهر وتحتهما السنة، ويمكن تحويله إلى الميلادي من «تعديل الأداة»", [.systemMedium], .day, cal: true) { DateLineView(entry: $0) },
        w("hilal.both", "التاريخ", "التاريخ الهجري والميلادي", "التاريخان مع السنة: الهجري في الأعلى والميلادي في الأسفل", [.systemMedium], .day) { BothDatesView(entry: $0) },
        w("hilal.day", "التاريخ", "اسم اليوم", "اسم اليوم بخط الثلث بحجم كبير", [.systemSmall], .day) { DayNameView(entry: $0) },
        w("hilal.dnum", "التاريخ", "اليوم ورقم التاريخ", "اسم اليوم، ورقم اليوم بخط كبير، واسم الشهر", [.systemSmall], .day, cal: true) { DayNumberView(entry: $0) },
        w("hilal.month", "التاريخ", "الشهر ورقم اليوم", "اسم الشهر، ورقم اليوم بلون خافت خلفه", [.systemSmall], .day, cal: true) { MonthGhostView(entry: $0) },
        w("hilal.calendar", "التاريخ", "تقويم الشهر", "أيام الشهر كاملة مع تمييز اليوم الحالي", [.systemSmall], .day, cal: true) { MonthCalendarView(entry: $0) },
        w("hilal.mprog", "التاريخ", "تقدّم الشهر", "ما مضى من الشهر بالنقاط والنسبة المئوية", [.systemSmall], .day, cal: true) { MonthProgressView(entry: $0) },
        w("hilal.triple", "التاريخ", "التقويم الثلاثي", "الميلادي يسارًا، واسم اليوم في الوسط، والهجري يمينًا", [.systemMedium], .day) { TripleDateView(entry: $0) },
        w("hilal.daytwo", "التاريخ", "اليوم والتاريخان", "اسم اليوم بخط كبير، وتحته التاريخ الهجري ثم الميلادي", [.systemSmall], .day) { DayTwoDatesView(entry: $0) },
        w("hilal.daytwoy", "التاريخ", "اليوم والتاريخان مع السنة", "اسم اليوم، وتحته التاريخ الهجري ثم الميلادي كاملين بالسنة", [.systemSmall], .day) { DayTwoDatesYearView(entry: $0) },
        w("hilal.calm", "التاريخ", "تقويم الشهر الكبير", "رقم اليوم والشهر والسنة، مع أيام الشهر كاملة وتمييز الجمعة", [.systemMedium], .day, cal: true) { MonthCalendarMediumView(entry: $0) },
        w("hilal.hmonths", "التاريخ", "الأشهر الهجرية", "الأشهر الهجرية الاثنا عشر مع تمييز الشهر الحالي وتقدّمه", [.systemMedium], .day) { HijriMonthsView(entry: $0) },
        w("hilal.ramadan", "التاريخ", "رمضان", "الأيام الباقية على رمضان، وفي رمضان: رقم اليوم والعدّ للإفطار", [.systemSmall], .prayer) { RamadanView(entry: $0) },
        w("hilal.daym", "التاريخ", "اسم اليوم الكبير", "اسم اليوم بخط كبير يملأ الويدجت، وتحته التاريخان", [.systemMedium], .day) { DayNameMView(entry: $0) },
        w("hilal.triplenames", "التاريخ", "التقويم الثلاثي بالأسماء", "الشهر الهجري، واسم اليوم، والشهر الميلادي في سطر واحد", [.systemMedium], .day) { TripleNamesView(entry: $0) },
        w("hilal.dual", "التاريخ", "التقويم المزدوج", "الشهر الميلادي ورقمه، والرقم الهجري وشهره في سطر واحد", [.systemMedium], .day) { DualDateView(entry: $0) },
        w("hilal.monthdate", "التاريخ", "اسم الشهر والتاريخ", "اسم الشهر بخط كبير، وتحته التاريخ بالأرقام", [.systemSmall], .day, cal: true) { MonthDateView(entry: $0) },
        w("hilal.monthm", "التاريخ", "الشهر ورقم اليوم الكبير", "اسم الشهر فوق رقم اليوم الكبير الباهت، وتحتهما التاريخان", [.systemMedium], .day, cal: true) { MonthGhostMView(entry: $0) },
        w("hilal.yprog", "التاريخ", "تقدّم السنة", "ما مضى من السنة بالنقاط والنسبة المئوية", [.systemSmall], .day, cal: true) { YearProgressView(entry: $0) },
        // ── الصلاة ──
        w("hilal.prevnext", "الصلاة", "الصلاة السابقة والقادمة", "الوقت المنقضي منذ الصلاة السابقة، والمتبقي على القادمة، مع الشروق ومنتصف الليل", [.systemSmall, .systemMedium], .prayer) { PrevNextView(entry: $0) },
        w("hilal.prayer", "الصلاة", "عدّاد الصلاة القادمة", "اسم الصلاة ووقتها داخل حلقة، مع العدّاد التنازلي", [.systemSmall], .prayer) { PrayerRingView(entry: $0) },
        w("hilal.next", "الصلاة", "الصلاة القادمة وجدول الصلوات", "اسم الصلاة القادمة بخط كبير مع العدّاد، وأوقات صلوات اليوم", [.systemMedium], .prayer) { NextPrayerView(entry: $0) },
        w("hilal.agenda", "الصلاة", "التاريخ وجدول الصلوات", "اسم اليوم والتاريخان، والصلاة القادمة، وأوقات صلوات اليوم", [.systemMedium], .prayer) { AgendaView(entry: $0) },
        w("hilal.combo", "الصلاة", "التاريخان وعدّاد الصلاة", "الهجري يمينًا والميلادي يسارًا، مع العدّاد وأوقات صلوات اليوم", [.systemMedium], .prayer) { ComboView(entry: $0) },
        w("hilal.pdots", "الصلاة", "قائمة الصلوات", "أوقات اليوم في قائمة، مع تمييز الصلاة القادمة", [.systemSmall], .prayer) { PrayerDotsView(entry: $0) },
        w("hilal.prings", "الصلاة", "حلقات الصلوات", "حلقة لكل صلاة تمتلئ مع مرور وقتها، وبطاقة الصلاة القادمة والمتبقي", [.systemMedium], .prayer) { PrayerRingsView(entry: $0) },
        w("hilal.prings2", "الصلاة", "حلقات الصلوات (سطر واحد)", "حلقات الصلوات الخمس بأيقوناتها في سطر واحد", [.systemMedium], .prayer) { PrayerRingsView(entry: $0, compact: true) },
        w("hilal.pcaps", "الصلاة", "أعمدة الصلوات", "الصلاة القادمة مع العدّاد، وأعمدة تمتلئ مع أوقات الصلوات", [.systemMedium], .prayer) { PrayerCapsView(entry: $0) },
        w("hilal.iftar", "الصلاة", "حلقة المغرب والفجر", "حلقة تمتلئ حتى المغرب نهارًا وحتى الفجر ليلًا؛ وفي رمضان: الإفطار والإمساك", [.systemSmall], .prayer) { IftarRingView(entry: $0) },
        w("hilal.lastthird", "الصلاة", "الثلث الأخير من الليل", "وقت بداية الثلث الأخير مع العدّ له، وقوس الليل من المغرب إلى الفجر", [.systemSmall], .prayer) { LastThirdView(entry: $0) },
        w("hilal.dayprayers", "الصلاة", "اليوم والصلاة", "التاريخان، واسم اليوم بخط كبير، وأوقات الصلوات، والمتبقي على الصلاة القادمة", [.systemMedium], .prayer) { DayPrayersMView(entry: $0) },
        w("hilal.daydots", "الصلاة", "اليوم والصلوات بالنقاط", "اسم اليوم والوقت خلفه، والصلوات في عمودين بالنقاط", [.systemMedium], .minute) { DayDotsView(entry: $0) },
        w("hilal.tripleprayer", "الصلاة", "التقويم الثلاثي والصلاة", "الشهر الهجري واليوم والشهر الميلادي، وتحتها أوقات الصلوات", [.systemMedium], .prayer) { TriplePrayerView(entry: $0) },
        w("hilal.pcaps2", "الصلاة", "كبسولات الصلاة بالأيقونات", "كبسولة لكل وقت بأيقونته، والقادمة مضيئة", [.systemMedium], .prayer) { PrayerIconCapsView(entry: $0) },
        // ── الساعة ──
        w("hilal.aclock", "الساعة", "ساعة عقارب مع اسم اليوم", "عقارب متحركة، واسم اليوم بخط الثلث خلفها", [.systemSmall], .minute) { AnalogClockView(entry: $0, numerals: false) },
        w("hilal.aclock2", "الساعة", "ساعة عقارب بالأرقام", "عقارب متحركة، وأرقام عربية، والتاريخ الهجري", [.systemSmall], .minute) { AnalogClockView(entry: $0, numerals: true) },
        w("hilal.digital", "الساعة", "الساعة الرقمية", "الوقت، واسم اليوم، والتاريخ الهجري", [.systemSmall], .minute) { DigitalClockView(entry: $0) },
        w("hilal.cdate", "الساعة", "الساعة والتاريخان", "عقارب متحركة، واسم اليوم، والتاريخان الهجري والميلادي", [.systemMedium], .minute) { ClockDatesView(entry: $0) },
        w("hilal.tick", "الساعة", "ساعة الدقائق", "حلقة من ستين علامة تمتلئ مع الدقائق، والوقت واسم اليوم في الوسط", [.systemSmall], .minute) { MinuteRingClockView(entry: $0) },
        w("hilal.tall", "الساعة", "الساعة الطويلة", "الساعات فوق الدقائق بأرقام كبيرة، مع اليوم والتاريخ الهجري", [.systemSmall], .minute) { TallClockView(entry: $0) },
        w("hilal.dial", "الساعة", "الساعة المزخرفة", "عقارب متحركة فوق نجمة ثمانية وأرقام عربية", [.systemSmall], .minute) { DecoDialView(entry: $0) },
        w("hilal.dayclock", "الساعة", "اليوم والساعة", "اسم اليوم بخط كبير والتاريخان، مع الوقت والعدّ للصلاة القادمة", [.systemMedium], .minute) { DayClockView(entry: $0) },
        w("hilal.dayclockp", "الساعة", "اليوم والساعة والصلاة", "الوقت كبيرًا خلف اسم اليوم، مع أوقات الصلوات والمتبقي على الصلاة القادمة", [.systemMedium], .minute) { DayPrayersMView(entry: $0, clock: true) },
        w("hilal.tickbox", "الساعة", "ساعة الإطار", "علامات حول الإطار تمتلئ مع الدقائق، والوقت والتاريخ والطقس", [.systemSmall], .minute) { TickBoxView(entry: $0) },
        w("hilal.tickm", "الساعة", "ساعة الإطار والطقس", "الساعات والدقائق بأرقام كبيرة داخل إطار العلامات، مع اليوم والطقس", [.systemMedium], .minute) { TickClockMView(entry: $0) },
        w("hilal.tickstack", "الساعة", "ساعة الإطار المتدرّجة", "الساعة كبيرة والدقائق باهتة تحتها داخل إطار العلامات", [.systemSmall], .minute) { TickStackView(entry: $0) },
        w("hilal.tall2", "الساعة", "الساعة الممدّدة", "الوقت بأرقام طويلة ضيّقة، وتحته اليوم والتاريخ", [.systemSmall], .minute) { TallLineClockView(entry: $0) },
        w("hilal.rosette", "الساعة", "ساعة الزخرفة الدائرية", "عقارب متحركة فوق زخرفة دائرية من اسم اليوم بخط الثلث", [.systemSmall], .minute) { RosetteClockView(entry: $0) },
        // ── الطقس ──
        w("hilal.wx", "الطقس", "الطقس", "درجة الحرارة الحالية وحالة الطقس", [.systemSmall], .weather) { WeatherSimpleView(entry: $0) },
        w("hilal.wx2", "الطقس", "الطقس مع العظمى والصغرى", "اسم المدينة، ودرجة الحرارة، والعظمى والصغرى", [.systemSmall], .weather) { WeatherCompactView(entry: $0) },
        w("hilal.wxd", "الطقس", "الطقس والتاريخ الهجري", "درجة الحرارة وحالة الطقس، مع التاريخ الهجري", [.systemMedium], .weather) { WeatherDetailView(entry: $0) },
        w("hilal.wxt", "الطقس", "الطقس مع اسم اليوم", "اسم اليوم بخط الثلث بحجم كبير، مع الطقس", [.systemMedium], .weather) { WeatherThuluthView(entry: $0) },
        w("hilal.wxweek", "الطقس", "توقعات الأيام", "الحرارة الحالية، والعظمى والصغرى وحالة الطقس لستة أيام", [.systemMedium], .weather) { WeatherWeekView(entry: $0) },
        w("hilal.wxfull", "الطقس", "الطقس المفصّل", "الحرارة والحالة، مع الرطوبة والرياح ووقتي الشروق والغروب", [.systemMedium], .weather) { WeatherFullView(entry: $0) },
        w("hilal.wxdays", "الطقس", "طقس الأيام", "الحرارة الحالية، وتوقعات أربعة أيام في صفوف", [.systemMedium], .weather) { WeatherDaysView(entry: $0) },
        w("hilal.wxdayname", "الطقس", "طقس الأيام واليوم", "اسم اليوم بخط كبير، وتوقعات أربعة أيام في صفوف", [.systemMedium], .weather) { WeatherDaysView(entry: $0, dayName: true) },
        w("hilal.dayweather", "الطقس", "اليوم والطقس", "حالة الطقس، واسم اليوم، وتوقعات خمسة أيام، والمتبقي على الصلاة القادمة", [.systemMedium], .weather) { DayWeatherView(entry: $0) },
        // ── الوسائط (القرآن والإذاعات و Apple Music) ──
        w("hilal.m.ctrl", "الوسائط", "تحكّم", "العنوان وأزرار السابق والتشغيل والتالي", [.systemSmall], .media) { MediaCtrlView(entry: $0) },
        w("hilal.m.cassette", "الوسائط", "كاسيت", "شريط كاسيت باسم المقطع، مع أزرار التحكم", [.systemSmall], .media) { MediaCassetteView(entry: $0) },
        w("hilal.m.bigbtn", "الوسائط", "زر كبير", "زر تشغيل كبير بين السابق والتالي", [.systemSmall], .media) { MediaBigButtonView(entry: $0) },
        w("hilal.m.card", "الوسائط", "بطاقة", "غلاف عريض، والعنوان، وأزرار التحكم", [.systemSmall], .media) { MediaCardView(entry: $0) },
        w("hilal.m.ring", "الوسائط", "حلقة", "الغلاف خلفيةً، وحلقة التقدّم حول زر التشغيل", [.systemSmall], .media) { MediaRingView(entry: $0) },
        w("hilal.m.cover", "الوسائط", "غلاف", "الغلاف كاملًا مع زر التشغيل والعنوان", [.systemSmall], .media) { MediaCoverView(entry: $0) },
        w("hilal.m.vinyl", "الوسائط", "أسطوانة", "أسطوانة في الوسط عليها زر التشغيل", [.systemSmall], .media) { MediaVinylView(entry: $0) },
        w("hilal.m.glow", "الوسائط", "وهج", "نصف أسطوانة في الأعلى، والتشغيل والعنوان أسفلها", [.systemSmall], .media) { MediaGlowView(entry: $0) },
        w("hilal.m.pad", "الوسائط", "لوحة", "أربعة أزرار كبيرة: التكرار والتشغيل والسابق والتالي", [.systemSmall], .media) { MediaPadView(entry: $0) },
        w("hilal.m.orbit", "الوسائط", "دائري", "حلقة التقدّم حول أزرار التحكم", [.systemSmall], .media) { MediaOrbitView(entry: $0) },
        w("hilal.m.dots", "الوسائط", "نقاط", "العنوان والأزرار، وتقدّم المقطع بالنقاط", [.systemSmall], .media) { MediaDotsView(entry: $0) },
        w("hilal.m.bar", "الوسائط", "شريط التقدّم", "العنوان والأزرار، وشريط التقدّم", [.systemSmall], .media) { MediaBarView(entry: $0) },
        w("hilal.m.wave", "الوسائط", "موجة", "الغلاف والعنوان، وموجة صوتية، وأزرار كاملة مع التكرار والعشوائي", [.systemMedium], .media) { MediaWaveView(entry: $0) },
        w("hilal.m.player", "الوسائط", "مشغّل", "غلاف كبير، والعنوان، وشريط التقدّم، وأزرار كاملة", [.systemMedium], .media) { MediaPlayerView(entry: $0) },
        w("hilal.m.stage", "الوسائط", "منصة", "الغلاف يملأ الجانب، مع العنوان وأزرار كبيرة", [.systemMedium], .media) { MediaStageView(entry: $0) },
        w("hilal.m.console", "الوسائط", "وحدة تحكم", "أربعة أزرار كبيرة، والعنوان وشريط التقدّم", [.systemMedium], .media) { MediaConsoleView(entry: $0) },
        w("hilal.m.orbitm", "الوسائط", "مدار", "غلاف دائري بحلقة التقدّم، والعنوان والوقت والأزرار", [.systemMedium], .media) { MediaOrbitMView(entry: $0) },
        w("hilal.m.turntable", "الوسائط", "جرامافون", "أسطوانة على جرامافون بإبرة، مع التقدّم والأزرار", [.systemMedium], .media) { MediaTurntableView(entry: $0) },
        w("hilal.m.book", "الوسائط", "كتاب", "غلاف كبير، والعنوان، والوقت المنقضي وزر التشغيل", [.systemMedium], .media) { MediaBookView(entry: $0) },
        w("hilal.m.tuner", "الوسائط", "بكرة الإذاعات", "الإذاعة الحالية وأزرارها، وبجانبها إذاعاتك تقلّبها بالأسهم وتشغّل أيًّا منها بضغطة", [.systemMedium], .media) { RadioTunerView(entry: $0) },
        w("hilal.m.tuners", "الوسائط", "بكرة الإذاعات الصغيرة", "الإذاعة الحالية، وإذاعتان من قائمتك تقلّبهما بالأسهم وتشغّل أيًّا منهما بضغطة، مع أزرار التحكم", [.systemSmall], .media) { RadioTunerSmallView(entry: $0) },
        w("hilal.m.dial", "الوسائط", "قرص الإذاعات", "قرص موالفة دائري: الإذاعة في وسطه، والسابقة والتالية على حافته؛ اضغط الجانبية فيدور القرص، وزر الوسط للتشغيل", [.systemSmall], .media) { RadioDialView(entry: $0) },
        w("hilal.tv.reel", "القنوات", "بكرة القنوات", "أربع قنوات عربية بشعاراتها تقلّبها بالأسهم، واضغط القناة لتفتح بثها", [.systemMedium], .day) { TVReelView(entry: $0) },
        w("hilal.tv.one", "القنوات", "قناة", "قناة واحدة بشعارها وتصنيفها، تقلّب بين القنوات وتفتح البث بضغطة", [.systemSmall], .day) { TVOneView(entry: $0) },
        w("hilal.m.wheel", "الوسائط", "عجلة", "عجلة تحكم دائرية، وبطاقة المقطع", [.systemMedium], .media) { MediaWheelView(entry: $0) },
        w("hilal.m.simple", "الوسائط", "الوسائط", "العنوان كبيرًا والأزرار، مع الغلاف", [.systemMedium], .media) { MediaSimpleView(entry: $0) },
        w("hilal.m.slim", "الوسائط", "وسائط موجة", "غلاف دائري، والعنوان والأزرار، وموجة صوتية بالتقدّم", [.systemMedium], .media) { MediaSlimView(entry: $0) },
        // ── المباريات ──
        w("hilal.s.team", "المباريات", "فريقي", "شعار فريقك وترتيبه ونقاطه، وثلاث مباريات قادمة", [.systemSmall], .sports) { SportsTeamSmallView(entry: $0) },
        w("hilal.s.match", "المباريات", "مباراة", "البطولة والجولة، والفريقان مع الموعد أو النتيجة", [.systemSmall], .sports) { SportsMatchSmallView(entry: $0) },
        w("hilal.s.matches", "المباريات", "مباريات", "ثلاث مباريات بالشعارات والمواعيد أو النتائج", [.systemSmall], .sports) { SportsMatchesSmallView(entry: $0) },
        w("hilal.s.scorers", "المباريات", "الهدافون", "أول ثلاثة هدافين في البطولة بصورهم وأهدافهم", [.systemSmall], .sports) { SportsScorersSmallView(entry: $0) },
        w("hilal.s.form", "المباريات", "مباريات فريقي", "آخر نتائج فريقك بالنقاط الملوّنة، ومبارياته القادمة", [.systemSmall], .sports) { SportsFormSmallView(entry: $0) },
        w("hilal.s.card", "المباريات", "بطاقة المباراة", "حالة المباراة والدقيقة، والفريقان بالنتيجة", [.systemSmall], .sports) { SportsCardSmallView(entry: $0) },
        w("hilal.s.events", "المباريات", "أحداث المباراة", "النتيجة، وأهداف المباراة بأسماء اللاعبين ودقائقها", [.systemSmall], .sports) { SportsEventsSmallView(entry: $0) },
        w("hilal.s.score", "المباريات", "النتيجة", "شعارا الفريقين والنتيجة الكبيرة، مع زر المتابعة المباشرة", [.systemSmall], .sports) { SportsScoreSmallView(entry: $0) },
        w("hilal.s.matchm", "المباريات", "المباراة", "شعاران كبيران والنتيجة أو الموعد، والمباراة التالية تحتها، مع زر المتابعة المباشرة", [.systemMedium], .sports) { SportsMatchMediumView(entry: $0) },
        w("hilal.s.vs", "المباريات", "مواجهة اليوم", "مباراة واحدة كبيرة، وتتنقّل بين مباريات اليوم بالأسهم", [.systemMedium], .sports) { SportsVsMediumView(entry: $0) },
        w("hilal.s.goals", "المباريات", "الأهداف", "النتيجة، وأهداف المباراة بصور اللاعبين ودقائقها", [.systemMedium], .sports) { SportsGoalsMediumView(entry: $0) },
        w("hilal.s.table", "المباريات", "الترتيب", "أول أربعة فرق في البطولة بنقاطها، مع فريقك دائمًا", [.systemMedium], .sports) { SportsTableMediumView(entry: $0) },
        w("hilal.s.teamm", "المباريات", "فريقي", "فريقك وترتيبه وآخر خمس نتائج، وثلاث مباريات قادمة بأرضها وموعدها", [.systemMedium], .sports) { SportsTeamMediumView(entry: $0) },
        w("hilal.s.list", "المباريات", "مباريات اليوم", "ثلاث مباريات بأسماء الفرق وشعاراتها، والمواعيد أو النتائج", [.systemMedium], .sports) { SportsListMediumView(entry: $0) },
        w("hilal.s.teaml", "المباريات", "فريقي الكامل", "فريقك وآخر نتائجه، وثلاث مباريات قادمة وثلاث نتائج", [.systemLarge], .sports) { SportsTeamLargeView(entry: $0) },
        w("hilal.s.log", "المباريات", "سجل المباراة", "النتيجة الكبيرة، والأهداف والبطاقات لكل فريق في عمود", [.systemLarge], .sports) { SportsLogLargeView(entry: $0) },
        w("hilal.s.matcht", "المباريات", "المباراة والترتيب", "النتيجة الكبيرة، وترتيب البطولة تحتها", [.systemLarge], .sports) { SportsMatchTableLargeView(entry: $0) },
        w("hilal.s.schedule", "المباريات", "جدول المباريات", "ست مباريات بالأسماء والشعارات، والمواعيد أو النتائج", [.systemLarge], .sports) { SportsScheduleLargeView(entry: $0) },
        w("hilal.s.scorersl", "المباريات", "الهدافون", "قائمة الهدافين بالصور والأهداف وصناعة الأهداف", [.systemLarge], .sports) { SportsScorersLargeView(entry: $0) },
        w("hilal.s.goalsl", "المباريات", "المباراة والأهداف", "النتيجة الكبيرة، وأهداف المباراة بصور اللاعبين", [.systemLarge], .sports) { SportsGoalsLargeView(entry: $0) },
        // ── القرآن ──
        w("hilal.wird", "القرآن", "ورد القرآن", "الجزء الذي تقرؤه وتقدّم الختمة، مع زرّين للتقدّم والرجوع من الويدجت نفسها", [.systemSmall], .day) { WirdView(entry: $0) },
        w("hilal.verse", "القرآن", "آية وأوقات الصلاة", "آية قصيرة تتجدّد كل يوم، وتحتها أوقات صلوات اليوم", [.systemMedium], .prayer) { VersePrayersView(entry: $0) },
    ]

    /// ويدجتات شاشة القفل (للمعرض داخل التطبيق)
    static let lock: [WInfo] = [
        w("lock.next", "شاشة القفل", "الصلاة القادمة", "اسم الصلاة بخط الثلث ووقتها، مع العدّاد", [.accessoryRectangular], .prayer) { LockNextView(entry: $0) },
        w("lock.dayprayers", "شاشة القفل", "مواقيت اليوم", "الصلاة القادمة مع العدّاد، وتحتها أوقات الصلوات الخمس بخط الثلث", [.accessoryRectangular], .prayer) { LockDayPrayersView(entry: $0) },
        w("lock.prevnext", "شاشة القفل", "الصلاة السابقة والقادمة", "الوقت المنقضي منذ الصلاة السابقة، والمتبقي على القادمة", [.accessoryRectangular], .prayer) { LockPrevNextView(entry: $0) },
        w("lock.hijri", "شاشة القفل", "التاريخ الهجري", "اليوم والشهر وتحتهما السنة", [.accessoryRectangular], .day) { LockHijriView(entry: $0) },
        w("lock.greg", "شاشة القفل", "التاريخ الميلادي", "اليوم والشهر وتحتهما السنة الميلادية", [.accessoryRectangular], .day) { LockHijriView(entry: $0, greg: true) },
        w("lock.daydate", "شاشة القفل", "اسم اليوم والتاريخ", "اسم اليوم بخط الثلث، وتحته التاريخ الهجري", [.accessoryRectangular], .day) { LockDayDateView(entry: $0) },
        w("lock.daydategreg", "شاشة القفل", "اسم اليوم والتاريخ الميلادي", "اسم اليوم بخط الثلث، وتحته التاريخ الميلادي", [.accessoryRectangular], .day) { LockDayDateView(entry: $0, greg: true) },
        w("lock.daycircle", "شاشة القفل", "رقم اليوم الهجري", "رقم اليوم الهجري واسم الشهر", [.accessoryCircular], .day) { LockDayCircle(entry: $0) },
        w("lock.daycirclegreg", "شاشة القفل", "رقم اليوم الميلادي", "رقم اليوم الميلادي واسم الشهر", [.accessoryCircular], .day) { LockDayCircle(entry: $0, greg: true) },
        w("lock.prayercircle", "شاشة القفل", "حلقة الصلاة القادمة", "اسم الصلاة القادمة ووقتها داخل حلقة تُظهر التقدّم", [.accessoryCircular], .prayer) { LockPrayerCircle(entry: $0) },
        w("lock.weekday", "شاشة القفل", "اسم اليوم", "اسم اليوم بخط الثلث", [.accessoryCircular], .day) { LockWeekdayCircle(entry: $0) },
        w("lock.inlinehijri", "شاشة القفل", "التاريخ الهجري (أعلى الساعة)", "الشهر والسنة الهجرية بخط الثلث، بجانب اليوم الذي يعرضه النظام", [.accessoryInline], .day) { LockInlineDate(entry: $0) },
        w("lock.inlinegreg", "شاشة القفل", "التاريخ الميلادي (أعلى الساعة)", "الشهر والسنة الميلادية بخط الثلث، بجانب اليوم الذي يعرضه النظام", [.accessoryInline], .day) { LockInlineDate(entry: $0, greg: true) },
        w("lock.inlineprayer", "شاشة القفل", "الصلاة القادمة (أعلى الساعة)", "اسم الصلاة القادمة ووقتها", [.accessoryInline], .prayer) { LockInlinePrayer(entry: $0) },
        w("lock.s.rect", "المباريات", "مباراة فريقي", "النتيجة والدقيقة أثناء المباراة، والموعد قبلها", [.accessoryRectangular], .sports) {
            SportsLockRect(entry: SportsLockEntry(date: $0.date, data: $0.sports ?? SportsStore.current())) },
        w("lock.s.circle", "المباريات", "خصم فريقي", "شعار الخصم مع الموعد أو النتيجة", [.accessoryCircular], .sports) {
            SportsLockCircle(entry: SportsLockEntry(date: $0.date, data: $0.sports ?? SportsStore.current())) },
        w("lock.s.inline", "المباريات", "مباراة فريقي (أعلى الساعة)", "الفريقان والنتيجة أو الموعد", [.accessoryInline], .sports) {
            SportsLockInline(entry: SportsLockEntry(date: $0.date, data: $0.sports ?? SportsStore.current())) },
    ]

    static func items(_ group: String) -> [WInfo] {
        if group == "المفضّلة" {
            let f = Styles.favorites
            return (all + lock).filter { f.contains($0.id) }
        }
        // قسم شاشة القفل يعرض كل ويدجت القفل (ومنها ويدجت المباريات)
        if group == "شاشة القفل" { return lock }
        return (all + lock).filter { $0.group == group }
    }

    static func info(_ id: String) -> WInfo { all.first { $0.id == id } ?? all[0] }

    static func sizeName(_ f: WidgetFamily) -> String {
        switch f {
        case .systemMedium: return L("متوسط")
        case .systemLarge: return L("كبير")
        case .accessoryRectangular: return L("مستطيل")
        case .accessoryCircular: return L("دائري")
        case .accessoryInline: return L("سطر")
        default: return L("صغير")
        }
    }

    /// المقاس بالشبكة كما في المعارض: ٢×٢، ٤×٢، ٤×٤
    static func gridName(_ f: WidgetFamily) -> String {
        switch f {
        case .systemSmall: return ar(2) + "×" + ar(2)
        case .systemMedium: return ar(4) + "×" + ar(2)
        case .systemLarge: return ar(4) + "×" + ar(4)
        default: return sizeName(f)
        }
    }

    static func isLock(_ f: WidgetFamily) -> Bool {
        f == .accessoryRectangular || f == .accessoryCircular || f == .accessoryInline
    }
}
