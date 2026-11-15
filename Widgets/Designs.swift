import SwiftUI
import WidgetKit
import AppIntents

// MARK: - ويدجت رفيقي بالمقاس: صغير / متوسط / كبير، وتُختار الويدجت باسمها من «تعديل الأداة»
// (مولّد من Catalog.swift — أي ويدجت جديدة تُضاف إلى القائمة المناسبة هنا)

enum DesignSmall: String, AppEnum {
    case day = "hilal.day"
    case dnum = "hilal.dnum"
    case month = "hilal.month"
    case calendar = "hilal.calendar"
    case mprog = "hilal.mprog"
    case daytwo = "hilal.daytwo"
    case daytwoy = "hilal.daytwoy"
    case ramadan = "hilal.ramadan"
    case monthdate = "hilal.monthdate"
    case yprog = "hilal.yprog"
    case prevnext = "hilal.prevnext"
    case prayer = "hilal.prayer"
    case pdots = "hilal.pdots"
    case iftar = "hilal.iftar"
    case lastthird = "hilal.lastthird"
    case aclock = "hilal.aclock"
    case aclock2 = "hilal.aclock2"
    case digital = "hilal.digital"
    case tick = "hilal.tick"
    case tall = "hilal.tall"
    case dial = "hilal.dial"
    case tickbox = "hilal.tickbox"
    case tickstack = "hilal.tickstack"
    case tall2 = "hilal.tall2"
    case rosette = "hilal.rosette"
    case wx = "hilal.wx"
    case wx2 = "hilal.wx2"
    case m_ctrl = "hilal.m.ctrl"
    case m_cassette = "hilal.m.cassette"
    case m_bigbtn = "hilal.m.bigbtn"
    case m_card = "hilal.m.card"
    case m_ring = "hilal.m.ring"
    case m_cover = "hilal.m.cover"
    case m_dial = "hilal.m.dial"
    case m_tuners = "hilal.m.tuners"
    case tv_one = "hilal.tv.one"
    case m_vinyl = "hilal.m.vinyl"
    case m_glow = "hilal.m.glow"
    case m_pad = "hilal.m.pad"
    case m_orbit = "hilal.m.orbit"
    case m_dots = "hilal.m.dots"
    case m_bar = "hilal.m.bar"
    case wird = "hilal.wird"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"
    static let caseDisplayRepresentations: [DesignSmall: DisplayRepresentation] = [
        .day: DisplayRepresentation(title: "اسم اليوم", subtitle: "التاريخ"),
        .dnum: DisplayRepresentation(title: "اليوم ورقم التاريخ", subtitle: "التاريخ"),
        .month: DisplayRepresentation(title: "الشهر ورقم اليوم", subtitle: "التاريخ"),
        .calendar: DisplayRepresentation(title: "تقويم الشهر", subtitle: "التاريخ"),
        .mprog: DisplayRepresentation(title: "تقدّم الشهر", subtitle: "التاريخ"),
        .daytwo: DisplayRepresentation(title: "اليوم والتاريخان", subtitle: "التاريخ"),
        .daytwoy: DisplayRepresentation(title: "اليوم والتاريخان مع السنة", subtitle: "التاريخ"),
        .ramadan: DisplayRepresentation(title: "رمضان", subtitle: "التاريخ"),
        .monthdate: DisplayRepresentation(title: "اسم الشهر والتاريخ", subtitle: "التاريخ"),
        .yprog: DisplayRepresentation(title: "تقدّم السنة", subtitle: "التاريخ"),
        .prevnext: DisplayRepresentation(title: "الصلاة السابقة والقادمة", subtitle: "الصلاة"),
        .prayer: DisplayRepresentation(title: "عدّاد الصلاة القادمة", subtitle: "الصلاة"),
        .pdots: DisplayRepresentation(title: "قائمة الصلوات", subtitle: "الصلاة"),
        .iftar: DisplayRepresentation(title: "حلقة المغرب والفجر", subtitle: "الصلاة"),
        .lastthird: DisplayRepresentation(title: "الثلث الأخير من الليل", subtitle: "الصلاة"),
        .aclock: DisplayRepresentation(title: "ساعة عقارب مع اسم اليوم", subtitle: "الساعة"),
        .aclock2: DisplayRepresentation(title: "ساعة عقارب بالأرقام", subtitle: "الساعة"),
        .digital: DisplayRepresentation(title: "الساعة الرقمية", subtitle: "الساعة"),
        .tick: DisplayRepresentation(title: "ساعة الدقائق", subtitle: "الساعة"),
        .tall: DisplayRepresentation(title: "الساعة الطويلة", subtitle: "الساعة"),
        .dial: DisplayRepresentation(title: "الساعة المزخرفة", subtitle: "الساعة"),
        .tickbox: DisplayRepresentation(title: "ساعة الإطار", subtitle: "الساعة"),
        .tickstack: DisplayRepresentation(title: "ساعة الإطار المتدرّجة", subtitle: "الساعة"),
        .tall2: DisplayRepresentation(title: "الساعة الممدّدة", subtitle: "الساعة"),
        .rosette: DisplayRepresentation(title: "ساعة الزخرفة الدائرية", subtitle: "الساعة"),
        .wx: DisplayRepresentation(title: "الطقس", subtitle: "الطقس"),
        .wx2: DisplayRepresentation(title: "الطقس مع العظمى والصغرى", subtitle: "الطقس"),
        .m_ctrl: DisplayRepresentation(title: "تحكّم", subtitle: "الوسائط"),
        .m_cassette: DisplayRepresentation(title: "كاسيت", subtitle: "الوسائط"),
        .m_bigbtn: DisplayRepresentation(title: "زر كبير", subtitle: "الوسائط"),
        .m_card: DisplayRepresentation(title: "بطاقة", subtitle: "الوسائط"),
        .m_ring: DisplayRepresentation(title: "حلقة", subtitle: "الوسائط"),
        .m_cover: DisplayRepresentation(title: "غلاف", subtitle: "الوسائط"),
        .m_dial: DisplayRepresentation(title: "قرص الإذاعات", subtitle: "الوسائط"),
        .m_tuners: DisplayRepresentation(title: "بكرة الإذاعات الصغيرة", subtitle: "الوسائط"),
        .tv_one: DisplayRepresentation(title: "قناة", subtitle: "القنوات"),
        .m_vinyl: DisplayRepresentation(title: "أسطوانة", subtitle: "الوسائط"),
        .m_glow: DisplayRepresentation(title: "وهج", subtitle: "الوسائط"),
        .m_pad: DisplayRepresentation(title: "لوحة", subtitle: "الوسائط"),
        .m_orbit: DisplayRepresentation(title: "دائري", subtitle: "الوسائط"),
        .m_dots: DisplayRepresentation(title: "نقاط", subtitle: "الوسائط"),
        .m_bar: DisplayRepresentation(title: "شريط التقدّم", subtitle: "الوسائط"),
        .wird: DisplayRepresentation(title: "ورد القرآن", subtitle: "القرآن"),
    ]
}

enum DesignMedium: String, AppEnum {
    case date = "hilal.date"
    case both = "hilal.both"
    case triple = "hilal.triple"
    case calm = "hilal.calm"
    case hmonths = "hilal.hmonths"
    case daym = "hilal.daym"
    case triplenames = "hilal.triplenames"
    case dual = "hilal.dual"
    case monthm = "hilal.monthm"
    case prevnext = "hilal.prevnext"
    case next = "hilal.next"
    case agenda = "hilal.agenda"
    case combo = "hilal.combo"
    case prings = "hilal.prings"
    case prings2 = "hilal.prings2"
    case pcaps = "hilal.pcaps"
    case dayprayers = "hilal.dayprayers"
    case daydots = "hilal.daydots"
    case tripleprayer = "hilal.tripleprayer"
    case pcaps2 = "hilal.pcaps2"
    case cdate = "hilal.cdate"
    case dayclock = "hilal.dayclock"
    case dayclockp = "hilal.dayclockp"
    case tickm = "hilal.tickm"
    case wxd = "hilal.wxd"
    case wxt = "hilal.wxt"
    case wxweek = "hilal.wxweek"
    case wxfull = "hilal.wxfull"
    case wxdays = "hilal.wxdays"
    case wxdayname = "hilal.wxdayname"
    case dayweather = "hilal.dayweather"
    case m_wave = "hilal.m.wave"
    case m_player = "hilal.m.player"
    case m_stage = "hilal.m.stage"
    case m_console = "hilal.m.console"
    case m_orbitm = "hilal.m.orbitm"
    case m_turntable = "hilal.m.turntable"
    case m_book = "hilal.m.book"
    case m_wheel = "hilal.m.wheel"
    case m_simple = "hilal.m.simple"
    case m_slim = "hilal.m.slim"
    case m_tuner = "hilal.m.tuner"
    case tv_reel = "hilal.tv.reel"
    case verse = "hilal.verse"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"
    static let caseDisplayRepresentations: [DesignMedium: DisplayRepresentation] = [
        .date: DisplayRepresentation(title: "التاريخ الهجري", subtitle: "التاريخ"),
        .both: DisplayRepresentation(title: "التاريخ الهجري والميلادي", subtitle: "التاريخ"),
        .triple: DisplayRepresentation(title: "التقويم الثلاثي", subtitle: "التاريخ"),
        .calm: DisplayRepresentation(title: "تقويم الشهر الكبير", subtitle: "التاريخ"),
        .hmonths: DisplayRepresentation(title: "الأشهر الهجرية", subtitle: "التاريخ"),
        .daym: DisplayRepresentation(title: "اسم اليوم الكبير", subtitle: "التاريخ"),
        .triplenames: DisplayRepresentation(title: "التقويم الثلاثي بالأسماء", subtitle: "التاريخ"),
        .dual: DisplayRepresentation(title: "التقويم المزدوج", subtitle: "التاريخ"),
        .monthm: DisplayRepresentation(title: "الشهر ورقم اليوم الكبير", subtitle: "التاريخ"),
        .prevnext: DisplayRepresentation(title: "الصلاة السابقة والقادمة", subtitle: "الصلاة"),
        .next: DisplayRepresentation(title: "الصلاة القادمة وجدول الصلوات", subtitle: "الصلاة"),
        .agenda: DisplayRepresentation(title: "التاريخ وجدول الصلوات", subtitle: "الصلاة"),
        .combo: DisplayRepresentation(title: "التاريخان وعدّاد الصلاة", subtitle: "الصلاة"),
        .prings: DisplayRepresentation(title: "حلقات الصلوات", subtitle: "الصلاة"),
        .prings2: DisplayRepresentation(title: "حلقات الصلوات (سطر واحد)", subtitle: "الصلاة"),
        .pcaps: DisplayRepresentation(title: "أعمدة الصلوات", subtitle: "الصلاة"),
        .dayprayers: DisplayRepresentation(title: "اليوم والصلاة", subtitle: "الصلاة"),
        .daydots: DisplayRepresentation(title: "اليوم والصلوات بالنقاط", subtitle: "الصلاة"),
        .tripleprayer: DisplayRepresentation(title: "التقويم الثلاثي والصلاة", subtitle: "الصلاة"),
        .pcaps2: DisplayRepresentation(title: "كبسولات الصلاة بالأيقونات", subtitle: "الصلاة"),
        .cdate: DisplayRepresentation(title: "الساعة والتاريخان", subtitle: "الساعة"),
        .dayclock: DisplayRepresentation(title: "اليوم والساعة", subtitle: "الساعة"),
        .dayclockp: DisplayRepresentation(title: "اليوم والساعة والصلاة", subtitle: "الساعة"),
        .tickm: DisplayRepresentation(title: "ساعة الإطار والطقس", subtitle: "الساعة"),
        .wxd: DisplayRepresentation(title: "الطقس والتاريخ الهجري", subtitle: "الطقس"),
        .wxt: DisplayRepresentation(title: "الطقس مع اسم اليوم", subtitle: "الطقس"),
        .wxweek: DisplayRepresentation(title: "توقعات الأيام", subtitle: "الطقس"),
        .wxfull: DisplayRepresentation(title: "الطقس المفصّل", subtitle: "الطقس"),
        .wxdays: DisplayRepresentation(title: "طقس الأيام", subtitle: "الطقس"),
        .wxdayname: DisplayRepresentation(title: "طقس الأيام واليوم", subtitle: "الطقس"),
        .dayweather: DisplayRepresentation(title: "اليوم والطقس", subtitle: "الطقس"),
        .m_wave: DisplayRepresentation(title: "موجة", subtitle: "الوسائط"),
        .m_player: DisplayRepresentation(title: "مشغّل", subtitle: "الوسائط"),
        .m_stage: DisplayRepresentation(title: "منصة", subtitle: "الوسائط"),
        .m_console: DisplayRepresentation(title: "وحدة تحكم", subtitle: "الوسائط"),
        .m_orbitm: DisplayRepresentation(title: "مدار", subtitle: "الوسائط"),
        .m_turntable: DisplayRepresentation(title: "جرامافون", subtitle: "الوسائط"),
        .m_book: DisplayRepresentation(title: "كتاب", subtitle: "الوسائط"),
        .m_wheel: DisplayRepresentation(title: "عجلة", subtitle: "الوسائط"),
        .m_simple: DisplayRepresentation(title: "الوسائط", subtitle: "الوسائط"),
        .m_slim: DisplayRepresentation(title: "وسائط موجة", subtitle: "الوسائط"),
        .m_tuner: DisplayRepresentation(title: "بكرة الإذاعات", subtitle: "الوسائط"),
        .tv_reel: DisplayRepresentation(title: "بكرة القنوات", subtitle: "القنوات"),
        .verse: DisplayRepresentation(title: "آية وأوقات الصلاة", subtitle: "القرآن"),
    ]
}


struct RafiqiSmallIntent: WidgetConfigurationIntent, Positioned {
    static let title: LocalizedStringResource = "إعداد الويدجت"
    static let description = IntentDescription("اختر الويدجت باسمها، ثم التقويم والمكان والخلفية والخط.")
    @Parameter(title: "الويدجت", default: .day) var design: DesignSmall
    @Parameter(title: "التقويم", default: .hijri) var calendar: CalOpt
    @Parameter(title: "المكان", default: .mr) var place: PlaceOpt
    @Parameter(title: "لون الخط", default: .app) var tint: TintOpt
    @Parameter(title: "الخلفية", default: .app) var bg: BgOpt
    @Parameter(title: "الخط", default: .app) var font: FontOpt
    @Parameter(title: "المصدر (لويدجت الوسائط)", default: .current) var source: MediaSourceOpt
    var designID: String? { design.rawValue }
    var isGregorian: Bool { calendar == .gregorian && Catalog.info(design.rawValue).hasCalendar }
    var bgOpt: BgOpt { bg }
    var fontOpt: FontOpt { font }
    var mediaOpt: String { source == .current ? "" : source.rawValue }
    init() {}
}

struct RafiqiMediumIntent: WidgetConfigurationIntent, Positioned {
    static let title: LocalizedStringResource = "إعداد الويدجت"
    static let description = IntentDescription("اختر الويدجت باسمها، ثم التقويم والمكان والخلفية والخط.")
    @Parameter(title: "الويدجت", default: .date) var design: DesignMedium
    @Parameter(title: "التقويم", default: .hijri) var calendar: CalOpt
    @Parameter(title: "المكان", default: .mr) var place: PlaceOpt
    @Parameter(title: "لون الخط", default: .app) var tint: TintOpt
    @Parameter(title: "الخلفية", default: .app) var bg: BgOpt
    @Parameter(title: "الخط", default: .app) var font: FontOpt
    @Parameter(title: "المصدر (لويدجت الوسائط)", default: .current) var source: MediaSourceOpt
    var designID: String? { design.rawValue }
    var isGregorian: Bool { calendar == .gregorian && Catalog.info(design.rawValue).hasCalendar }
    var bgOpt: BgOpt { bg }
    var fontOpt: FontOpt { font }
    var mediaOpt: String { source == .current ? "" : source.rawValue }
    init() {}
}


struct RafiqiSmall: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "rafiqi.small", intent: RafiqiSmallIntent.self,
                               provider: HProvider<RafiqiSmallIntent>(sched: Catalog.info("hilal.day").sched, kind: "hilal.day")) { entry in
            Catalog.info(entry.kind).render(entry)
        }
        .configurationDisplayName(L("رفيقي — صغير"))
        .description(L("اضغط مطوّلًا على الويدجت بعد إضافتها، ثم «تعديل الأداة»، واختر الويدجت التي تريدها باسمها."))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct RafiqiMedium: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "rafiqi.medium", intent: RafiqiMediumIntent.self,
                               provider: HProvider<RafiqiMediumIntent>(sched: Catalog.info("hilal.date").sched, kind: "hilal.date")) { entry in
            Catalog.info(entry.kind).render(entry)
        }
        .configurationDisplayName(L("رفيقي — متوسط"))
        .description(L("اضغط مطوّلًا على الويدجت بعد إضافتها، ثم «تعديل الأداة»، واختر الويدجت التي تريدها باسمها."))
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}


/// أنواع ويدجت الشاشة الرئيسية (لتحديثها)
enum RafiqiKinds {
    static let home = ["rafiqi.small", "rafiqi.medium", "rafiqi.large"]
    static func reload() { for k in home { WidgetCenter.shared.reloadTimelines(ofKind: k) } }
}
