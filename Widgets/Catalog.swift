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
    /// الرقم في القسم («الصلاة ٤») — نفس الاسم في «تعديل الأداة»
    var number: String { Catalog.number(id) }
}

enum Catalog {
    static let groups = ["التاريخ", "الصلاة", "الساعة", "الطقس", "القرآن والأذكار", "الوسائط", "القنوات", "الأدوات", "شاشة القفل"]

    private static func w<V: View>(_ id: String, _ group: String, _ name: String, _ desc: String,
                                   _ families: [WidgetFamily], _ sched: Sched, cal: Bool = false,
                                   @ViewBuilder _ v: @escaping (HEntry) -> V) -> WInfo {
        WInfo(id: id, group: group, name: L(name), desc: L(desc), families: families, sched: sched, hasCalendar: cal,
              render: { AnyView(v($0)) })
    }

    static let all: [WInfo] = [
        // ── التاريخ ──
        w("r2.hijri", "التاريخ", "التاريخ الهجري", "تصميمك المعتمد: «(اليوم) الشهر» سطر واحد وتحته السنة", [.systemSmall], .day, cal: true) { R2HijriView(entry: $0) },
        w("r2.day", "التاريخ", "اسم اليوم", "اسم اليوم بخط الثلث كبيرًا، وتحته التاريخ الهجري والميلادي", [.systemSmall, .systemMedium], .day) { R2DayView(entry: $0) },
        w("r2.both", "التاريخ", "الهجري والميلادي", "السطر المعتمد للتاريخين جنبًا إلى جنب، وتحت كل واحد سنته", [.systemMedium], .day) { R2BothView(entry: $0) },
        w("r2.triple", "التاريخ", "التقويم الثلاثي", "رقم اليوم الهجري والميلادي كبيرين، واسم اليوم في الوسط", [.systemMedium], .day) { R2TripleView(entry: $0) },
        w("r2.cal", "التاريخ", "تقويم الشهر", "أيام الشهر مع تمييز اليوم والجمعة؛ والكبير فيه التاريخ الآخر والمناسبة القادمة", [.systemSmall, .systemLarge], .day, cal: true) { R2CalendarView(entry: $0) },
        w("r2.prog", "التاريخ", "تقدّم الشهر", "نقطة لكل يوم من الشهر، وكم باقي على نهايته", [.systemSmall], .day, cal: true) { R2ProgressView(entry: $0) },
        w("r2.occ", "التاريخ", "المناسبة القادمة", "أقرب مناسبة (رمضان، العيدان، عرفة، اليوم الوطني…) والأيام الباقية لها", [.systemSmall], .day) { R2OccasionView(entry: $0) },
        w("r3.dayclock", "التاريخ", "اليوم والساعة", "اسم اليوم بالثلث فوق الساعة الرقمية الخافتة، ومواقيت اليوم والمتبقي على القادمة", [.systemMedium], .minute) { R3DayClockView(entry: $0) },
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
        w("r2.today", "الصلاة", "اليوم والصلاة", "اسم اليوم كبيرًا، وأوقات الصلوات، والمتبقي على القادمة بالثواني", [.systemMedium], .prayer) { R2TodayView(entry: $0) },
        w("r2.next", "الصلاة", "الصلاة القادمة", "اسم الصلاة والعدّاد، والشرطات حول الحافة تضيء كلما قرب الوقت", [.systemSmall], .prayer) { R2NextView(entry: $0) },
        w("r2.prevnext", "الصلاة", "السابقة والقادمة", "ما مضى من الصلاة السابقة باهتًا، والمتبقي على القادمة واضحًا", [.systemSmall, .systemMedium], .prayer) { R2PrevNextView(entry: $0) },
        w("r2.list", "الصلاة", "مواقيت اليوم", "أوقات اليوم بأسماء تنقرأ، والقادمة داخل كبسولة", [.systemSmall], .prayer) { R2ListView(entry: $0) },
        w("r2.rings", "الصلاة", "حلقات الصلوات", "الوقت داخل كل حلقة، والحالية تمتلئ مع مرور الوقت", [.systemMedium], .prayer) { R2RingsView(entry: $0) },
        w("r2.third", "الصلاة", "الثلث الأخير", "قوس الليل من المغرب إلى الفجر، والعدّ لبداية الثلث الأخير", [.systemSmall], .prayer) { R2ThirdView(entry: $0) },
        w("r2.week", "الصلاة", "جدول الأسبوع", "مواقيت سبعة أيام، واليوم مميّز، والمتبقي على القادمة", [.systemLarge], .prayer) { R2WeekView(entry: $0) },
        w("r3.caps", "الصلاة", "كبسولات الصلاة", "ست كبسولات بأيقونة لكل وقت، والقادمة دائرة بيضاء مضيئة", [.systemMedium], .prayer) { R3CapsulesView(entry: $0) },
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
        w("r2.clockm", "الساعة", "الساعة الكبيرة", "أرقام كبيرة داخل إطار من الشرطات، مع التاريخين", [.systemMedium], .minute) { R2ClockMView(entry: $0) },
        w("r2.clocks", "الساعة", "ساعة الإطار", "الشرطات حول الحافة تمتلئ مع الدقائق، واسم اليوم فوق الوقت", [.systemSmall], .minute) { R2ClockSView(entry: $0) },
        w("r2.analog", "الساعة", "ساعة العقارب", "عقارب متحركة وأرقام عربية، واسم اليوم باهتًا خلفها", [.systemSmall], .minute) { R2AnalogView(entry: $0) },
        w("r3.naqsh", "الساعة", "ساعة النقش", "عقارب فوق حلقة مخطوطة بخط الثلث، والعبارة تتغيّر كل يوم", [.systemSmall], .minute) { R3NaqshView(entry: $0) },
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
        w("r2.wx", "الطقس", "الطقس", "الحرارة كبيرة، والحالة بخط الثلث، والعظمى والصغرى", [.systemSmall], .weather) { R2WeatherView(entry: $0) },
        w("r2.wxdays", "الطقس", "الطقس والأيام", "الحرارة الآن مع الرطوبة والرياح، وتوقعات خمسة أيام", [.systemMedium], .weather) { R2WeatherDaysView(entry: $0) },
        w("r2.daywx", "الطقس", "اليوم والطقس", "اسم اليوم والتاريخ والمتبقي على الصلاة، والطقس بجانبها", [.systemMedium], .weather) { R2DayWeatherView(entry: $0) },
        w("r3.wxbig", "الطقس", "الطقس الكامل", "الحرارة والحالة والشروق والغروب وطول النهار، والمطر والرطوبة والرياح، وسبعة أيام", [.systemLarge], .weather) { R3WeatherBigView(entry: $0) },
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
        w("r2.player", "الوسائط", "المشغّل", "ما يُشغَّل الآن (إذاعة أو قرآن أو Apple Music) وأزراره", [.systemSmall], .media) { R2PlayerView(entry: $0) },
        w("r2.playerm", "الوسائط", "المشغّل الكبير", "ما يُشغَّل الآن، أو «تابع الاستماع» للقرآن، مع التقدّم والأزرار", [.systemMedium], .media) { R2PlayerMView(entry: $0) },
        w("r2.tuner", "الوسائط", "بكرة الإذاعات", "الإذاعة الحالية وأزرارها، وبجانبها إذاعاتك تشغّلها بضغطة", [.systemMedium], .media) { R2TunerView(entry: $0) },
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
        w("r2.tv", "القنوات", "قناة", "آخر قناة شاهدتها بشعارها، تقلّب بالأسهم وتفتح البث بضغطة", [.systemSmall], .day) { R2ChannelView(entry: $0) },
        w("r2.tvreel", "القنوات", "بكرة القنوات", "«شاهدت مؤخرًا» أولًا، أربع قنوات تقلّبها وتفتحها بضغطة", [.systemMedium], .day) { R2ChannelsView(entry: $0) },
        w("hilal.tv.reel", "القنوات", "بكرة القنوات", "أربع قنوات عربية بشعاراتها تقلّبها بالأسهم، واضغط القناة لتفتح بثها", [.systemMedium], .day) { TVReelView(entry: $0) },
        w("hilal.tv.one", "القنوات", "قناة", "قناة واحدة بشعارها وتصنيفها، تقلّب بين القنوات وتفتح البث بضغطة", [.systemSmall], .day) { TVOneView(entry: $0) },
        w("hilal.m.wheel", "الوسائط", "عجلة", "عجلة تحكم دائرية، وبطاقة المقطع", [.systemMedium], .media) { MediaWheelView(entry: $0) },
        w("hilal.m.simple", "الوسائط", "الوسائط", "العنوان كبيرًا والأزرار، مع الغلاف", [.systemMedium], .media) { MediaSimpleView(entry: $0) },
        w("hilal.m.slim", "الوسائط", "وسائط موجة", "غلاف دائري، والعنوان والأزرار، وموجة صوتية بالتقدّم", [.systemMedium], .media) { MediaSlimView(entry: $0) },
        // ── القرآن والأذكار ──
        w("r2.wird", "القرآن والأذكار", "الورد", "ثلاثون نقطة للأجزاء، وزرّا التقدّم والرجوع من الويدجت نفسها", [.systemSmall], .day) { R2WirdView(entry: $0) },
        w("r2.verse", "القرآن والأذكار", "آية اليوم", "آية قصيرة تتجدّد كل يوم بخط واضح", [.systemMedium], .day) { R2VerseView(entry: $0) },
        w("r2.dhikr", "القرآن والأذكار", "الذكر", "ذكر الوقت (الصباح أو المساء)، والضغط على الحلقة يعدّ من الويدجت نفسها", [.systemSmall, .systemMedium], .prayer) { R2DhikrView(entry: $0) },
        w("r3.quote", "القرآن والأذكار", "اقتباسات", "آية أو حديث أو ذكر أو بيت شعر كل يوم؛ أزرار التصنيف تعمل من الويدجت، والضغط على النص ينقل للتالي", [.systemMedium, .systemLarge], .day) { R3QuoteView(entry: $0) },
        w("r3.tasbih", "القرآن والأذكار", "المسبحة", "عدّاد تسبيح يعدّ من الويدجت مباشرة؛ والكبير فيه إحصائيات الأسبوع", [.systemSmall, .systemLarge], .day) { R3TasbihView(entry: $0) },
        w("hilal.wird", "القرآن والأذكار", "ورد القرآن", "الجزء الذي تقرؤه وتقدّم الختمة، مع زرّين للتقدّم والرجوع من الويدجت نفسها", [.systemSmall], .day) { WirdView(entry: $0) },
        w("hilal.verse", "القرآن والأذكار", "آية وأوقات الصلاة", "آية قصيرة تتجدّد كل يوم، وتحتها أوقات صلوات اليوم", [.systemMedium], .prayer) { VersePrayersView(entry: $0) },
        // ── الأدوات ──
        w("r2.scan", "الأدوات", "الماسح", "مسح مستند بضغطة، ومعه رمز QR والهوية", [.systemSmall], .day) { R2ScanView(entry: $0) },
        w("r2.storage", "الأدوات", "المساحة", "المستخدم من مساحة الجوال، والمتاح، وحجم ملفات رفيقي", [.systemSmall], .day) { R2StorageView(entry: $0) },
        w("r2.files", "الأدوات", "آخر الملفات", "آخر أربعة ملفات تفتحها بضغطة (تختفي إذا قفلت الملفات)", [.systemMedium], .day) { R2FilesView(entry: $0) },
        w("r2.qibla", "الأدوات", "القبلة", "اتجاه القبلة بالدرجات من الشمال والمسافة لمكة؛ الضغطة تفتح البوصلة", [.systemSmall], .day) { R2QiblaView(entry: $0) },
    ]

    /// ويدجتات شاشة القفل (للمعرض داخل التطبيق)
    static let lock: [WInfo] = [
        w("r2.lock.next", "شاشة القفل", "الصلاة القادمة", "اسم الصلاة بالثلث والعدّاد بالثواني", [.accessoryRectangular], .prayer) { R2LockNextView(entry: $0) },
        w("r2.lock.day", "شاشة القفل", "مواقيت اليوم", "القادمة مع العدّاد، وتحتها أوقات الصلوات الخمس", [.accessoryRectangular], .prayer) { R2LockDayView(entry: $0) },
        w("r2.lock.prevnext", "شاشة القفل", "السابقة والقادمة", "ما مضى من السابقة والمتبقي على القادمة", [.accessoryRectangular], .prayer) { R2LockPrevNextView(entry: $0) },
        w("r2.lock.date", "شاشة القفل", "التاريخ", "«(اليوم) الشهر» وتحته السنة — هجري أو ميلادي", [.accessoryRectangular], .day, cal: true) { R2LockDateView(entry: $0) },
        w("r2.lock.daydate", "شاشة القفل", "اليوم والتاريخ", "اسم اليوم بالثلث وتحته التاريخ — هجري أو ميلادي", [.accessoryRectangular], .day, cal: true) { R2LockDayDateView(entry: $0) },
        w("r2.lock.daynum", "شاشة القفل", "رقم اليوم", "رقم اليوم واسم الشهر — هجري أو ميلادي", [.accessoryCircular], .day, cal: true) { R2LockDayNumView(entry: $0) },
        w("r2.lock.ring", "شاشة القفل", "حلقة الصلاة", "اسم الصلاة القادمة داخل حلقة تمتلئ", [.accessoryCircular], .prayer) { R2LockRingView(entry: $0) },
        w("r2.lock.weekday", "شاشة القفل", "اسم اليوم", "اسم اليوم بخط الثلث", [.accessoryCircular], .day) { R2LockWeekdayView(entry: $0) },
        w("r2.lock.tasbih", "شاشة القفل", "التسبيح", "عدّاد ذكر الوقت؛ الضغطة تعدّ من شاشة القفل", [.accessoryCircular], .prayer) { R2LockTasbihView(entry: $0) },
        w("r2.lock.occasion", "شاشة القفل", "المناسبة القادمة", "الأيام الباقية على أقرب مناسبة", [.accessoryCircular], .day) { R2LockOccasionView(entry: $0) },
        w("r2.lock.idate", "شاشة القفل", "التاريخ أعلى الساعة", "التاريخ في سطر أعلى الساعة — هجري أو ميلادي", [.accessoryInline], .day, cal: true) { R2LockInlineDateView(entry: $0) },
        w("r2.lock.iprayer", "شاشة القفل", "الصلاة أعلى الساعة", "الصلاة القادمة ووقتها في سطر أعلى الساعة", [.accessoryInline], .prayer) { R2LockInlinePrayerView(entry: $0) },
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
    ]

    static func items(_ group: String) -> [WInfo] {
        if group == "المفضّلة" {
            let f = Styles.favorites
            return (all + lock).filter { f.contains($0.id) }
        }
        // قسم شاشة القفل يعرض كل ويدجت القفل
        if group == "شاشة القفل" { return lock }
        return (all + lock).filter { $0.group == group }
    }

    static func info(_ id: String) -> WInfo { all.first { $0.id == id } ?? lock.first { $0.id == id } ?? all[0] }

    /// اسم الويدجت المختصر في «تعديل الأداة» (القسم ورقمها فيه): الجديدة أولًا ثم الحالية
    static let prefixes: [String: String] = ["التاريخ": "التاريخ", "الصلاة": "الصلاة", "الساعة": "الساعة", "الطقس": "الطقس",
                                             "القرآن والأذكار": "القرآن", "الوسائط": "الوسائط", "القنوات": "القنوات",
                                             "الأدوات": "الأدوات", "شاشة القفل": "القفل"]
    private static let numbers: [String: String] = {
        var out: [String: String] = [:], counts: [String: Int] = [:]
        for w in all + lock {
            let c = (counts[w.group] ?? 0) + 1
            counts[w.group] = c
            out[w.id] = L(prefixes[w.group] ?? w.group) + " " + (Lang.isEN ? "\(c)" : ar(c))
        }
        return out
    }()
    static func number(_ id: String) -> String { numbers[id] ?? "" }

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
