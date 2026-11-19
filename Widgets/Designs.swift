import SwiftUI
import WidgetKit
import AppIntents

// MARK: - ويدجت رفيقي بالمقاس: صغير / متوسط / كبير، وتُختار الويدجت باسمها من «تعديل الأداة»
// (مولّد من Catalog.swift — أي ويدجت جديدة تُضاف إلى القائمة المناسبة هنا)

enum DesignSmall: String, AppEnum {
    case r2_hijri = "r2.hijri"
    case r2_day = "r2.day"
    case r2_cal = "r2.cal"
    case r2_prog = "r2.prog"
    case r2_occ = "r2.occ"
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
    case r2_next = "r2.next"
    case r2_prevnext = "r2.prevnext"
    case r2_list = "r2.list"
    case r2_third = "r2.third"
    case prevnext = "hilal.prevnext"
    case prayer = "hilal.prayer"
    case pdots = "hilal.pdots"
    case iftar = "hilal.iftar"
    case lastthird = "hilal.lastthird"
    case r2_clocks = "r2.clocks"
    case r2_analog = "r2.analog"
    case r3_naqsh = "r3.naqsh"
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
    case r2_wx = "r2.wx"
    case wx = "hilal.wx"
    case wx2 = "hilal.wx2"
    case r2_player = "r2.player"
    case m_ctrl = "hilal.m.ctrl"
    case m_cassette = "hilal.m.cassette"
    case m_bigbtn = "hilal.m.bigbtn"
    case m_card = "hilal.m.card"
    case m_ring = "hilal.m.ring"
    case m_cover = "hilal.m.cover"
    case m_vinyl = "hilal.m.vinyl"
    case m_glow = "hilal.m.glow"
    case m_pad = "hilal.m.pad"
    case m_orbit = "hilal.m.orbit"
    case m_dots = "hilal.m.dots"
    case m_bar = "hilal.m.bar"
    case m_tuners = "hilal.m.tuners"
    case m_dial = "hilal.m.dial"
    case r2_tv = "r2.tv"
    case tv_one = "hilal.tv.one"
    case r2_wird = "r2.wird"
    case r2_dhikr = "r2.dhikr"
    case r3_tasbih = "r3.tasbih"
    case wird = "hilal.wird"
    case r2_scan = "r2.scan"
    case r2_storage = "r2.storage"
    case r2_qibla = "r2.qibla"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"
    static let caseDisplayRepresentations: [DesignSmall: DisplayRepresentation] = [
        .r2_hijri: DisplayRepresentation(title: "التاريخ ١", subtitle: "التاريخ الهجري"),
        .r2_day: DisplayRepresentation(title: "التاريخ ٢", subtitle: "اسم اليوم"),
        .r2_cal: DisplayRepresentation(title: "التاريخ ٥", subtitle: "تقويم الشهر"),
        .r2_prog: DisplayRepresentation(title: "التاريخ ٦", subtitle: "تقدّم الشهر"),
        .r2_occ: DisplayRepresentation(title: "التاريخ ٧", subtitle: "المناسبة القادمة"),
        .day: DisplayRepresentation(title: "التاريخ ١١", subtitle: "اسم اليوم"),
        .dnum: DisplayRepresentation(title: "التاريخ ١٢", subtitle: "اليوم ورقم التاريخ"),
        .month: DisplayRepresentation(title: "التاريخ ١٣", subtitle: "الشهر ورقم اليوم"),
        .calendar: DisplayRepresentation(title: "التاريخ ١٤", subtitle: "تقويم الشهر"),
        .mprog: DisplayRepresentation(title: "التاريخ ١٥", subtitle: "تقدّم الشهر"),
        .daytwo: DisplayRepresentation(title: "التاريخ ١٧", subtitle: "اليوم والتاريخان"),
        .daytwoy: DisplayRepresentation(title: "التاريخ ١٨", subtitle: "اليوم والتاريخان مع السنة"),
        .ramadan: DisplayRepresentation(title: "التاريخ ٢١", subtitle: "رمضان"),
        .monthdate: DisplayRepresentation(title: "التاريخ ٢٥", subtitle: "اسم الشهر والتاريخ"),
        .yprog: DisplayRepresentation(title: "التاريخ ٢٧", subtitle: "تقدّم السنة"),
        .r2_next: DisplayRepresentation(title: "الصلاة ٢", subtitle: "الصلاة القادمة"),
        .r2_prevnext: DisplayRepresentation(title: "الصلاة ٣", subtitle: "السابقة والقادمة"),
        .r2_list: DisplayRepresentation(title: "الصلاة ٤", subtitle: "مواقيت اليوم"),
        .r2_third: DisplayRepresentation(title: "الصلاة ٦", subtitle: "الثلث الأخير"),
        .prevnext: DisplayRepresentation(title: "الصلاة ٩", subtitle: "الصلاة السابقة والقادمة"),
        .prayer: DisplayRepresentation(title: "الصلاة ١٠", subtitle: "عدّاد الصلاة القادمة"),
        .pdots: DisplayRepresentation(title: "الصلاة ١٤", subtitle: "قائمة الصلوات"),
        .iftar: DisplayRepresentation(title: "الصلاة ١٨", subtitle: "حلقة المغرب والفجر"),
        .lastthird: DisplayRepresentation(title: "الصلاة ١٩", subtitle: "الثلث الأخير من الليل"),
        .r2_clocks: DisplayRepresentation(title: "الساعة ٢", subtitle: "ساعة الإطار"),
        .r2_analog: DisplayRepresentation(title: "الساعة ٣", subtitle: "ساعة العقارب"),
        .r3_naqsh: DisplayRepresentation(title: "الساعة ٤", subtitle: "ساعة النقش"),
        .aclock: DisplayRepresentation(title: "الساعة ٥", subtitle: "ساعة عقارب مع اسم اليوم"),
        .aclock2: DisplayRepresentation(title: "الساعة ٦", subtitle: "ساعة عقارب بالأرقام"),
        .digital: DisplayRepresentation(title: "الساعة ٧", subtitle: "الساعة الرقمية"),
        .tick: DisplayRepresentation(title: "الساعة ٩", subtitle: "ساعة الدقائق"),
        .tall: DisplayRepresentation(title: "الساعة ١٠", subtitle: "الساعة الطويلة"),
        .dial: DisplayRepresentation(title: "الساعة ١١", subtitle: "الساعة المزخرفة"),
        .tickbox: DisplayRepresentation(title: "الساعة ١٤", subtitle: "ساعة الإطار"),
        .tickstack: DisplayRepresentation(title: "الساعة ١٦", subtitle: "ساعة الإطار المتدرّجة"),
        .tall2: DisplayRepresentation(title: "الساعة ١٧", subtitle: "الساعة الممدّدة"),
        .rosette: DisplayRepresentation(title: "الساعة ١٨", subtitle: "ساعة الزخرفة الدائرية"),
        .r2_wx: DisplayRepresentation(title: "الطقس ١", subtitle: "الطقس"),
        .wx: DisplayRepresentation(title: "الطقس ٥", subtitle: "الطقس"),
        .wx2: DisplayRepresentation(title: "الطقس ٦", subtitle: "الطقس مع العظمى والصغرى"),
        .r2_player: DisplayRepresentation(title: "الوسائط ١", subtitle: "المشغّل"),
        .m_ctrl: DisplayRepresentation(title: "الوسائط ٤", subtitle: "تحكّم"),
        .m_cassette: DisplayRepresentation(title: "الوسائط ٥", subtitle: "كاسيت"),
        .m_bigbtn: DisplayRepresentation(title: "الوسائط ٦", subtitle: "زر كبير"),
        .m_card: DisplayRepresentation(title: "الوسائط ٧", subtitle: "بطاقة"),
        .m_ring: DisplayRepresentation(title: "الوسائط ٨", subtitle: "حلقة"),
        .m_cover: DisplayRepresentation(title: "الوسائط ٩", subtitle: "غلاف"),
        .m_vinyl: DisplayRepresentation(title: "الوسائط ١٠", subtitle: "أسطوانة"),
        .m_glow: DisplayRepresentation(title: "الوسائط ١١", subtitle: "وهج"),
        .m_pad: DisplayRepresentation(title: "الوسائط ١٢", subtitle: "لوحة"),
        .m_orbit: DisplayRepresentation(title: "الوسائط ١٣", subtitle: "دائري"),
        .m_dots: DisplayRepresentation(title: "الوسائط ١٤", subtitle: "نقاط"),
        .m_bar: DisplayRepresentation(title: "الوسائط ١٥", subtitle: "شريط التقدّم"),
        .m_tuners: DisplayRepresentation(title: "الوسائط ٢٤", subtitle: "بكرة الإذاعات الصغيرة"),
        .m_dial: DisplayRepresentation(title: "الوسائط ٢٥", subtitle: "قرص الإذاعات"),
        .r2_tv: DisplayRepresentation(title: "القنوات ١", subtitle: "قناة"),
        .tv_one: DisplayRepresentation(title: "القنوات ٤", subtitle: "قناة"),
        .r2_wird: DisplayRepresentation(title: "القرآن ١", subtitle: "الورد"),
        .r2_dhikr: DisplayRepresentation(title: "القرآن ٣", subtitle: "الذكر"),
        .r3_tasbih: DisplayRepresentation(title: "القرآن ٥", subtitle: "المسبحة"),
        .wird: DisplayRepresentation(title: "القرآن ٦", subtitle: "ورد القرآن"),
        .r2_scan: DisplayRepresentation(title: "الأدوات ١", subtitle: "الماسح"),
        .r2_storage: DisplayRepresentation(title: "الأدوات ٢", subtitle: "المساحة"),
        .r2_qibla: DisplayRepresentation(title: "الأدوات ٤", subtitle: "القبلة"),
    ]
}

enum DesignMedium: String, AppEnum {
    case r2_day = "r2.day"
    case r2_both = "r2.both"
    case r2_triple = "r2.triple"
    case r3_dayclock = "r3.dayclock"
    case date = "hilal.date"
    case both = "hilal.both"
    case triple = "hilal.triple"
    case calm = "hilal.calm"
    case hmonths = "hilal.hmonths"
    case daym = "hilal.daym"
    case triplenames = "hilal.triplenames"
    case dual = "hilal.dual"
    case monthm = "hilal.monthm"
    case r2_today = "r2.today"
    case r2_prevnext = "r2.prevnext"
    case r2_rings = "r2.rings"
    case r3_caps = "r3.caps"
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
    case r2_clockm = "r2.clockm"
    case cdate = "hilal.cdate"
    case dayclock = "hilal.dayclock"
    case dayclockp = "hilal.dayclockp"
    case tickm = "hilal.tickm"
    case r2_wxdays = "r2.wxdays"
    case r2_daywx = "r2.daywx"
    case wxd = "hilal.wxd"
    case wxt = "hilal.wxt"
    case wxweek = "hilal.wxweek"
    case wxfull = "hilal.wxfull"
    case wxdays = "hilal.wxdays"
    case wxdayname = "hilal.wxdayname"
    case dayweather = "hilal.dayweather"
    case r2_playerm = "r2.playerm"
    case r2_tuner = "r2.tuner"
    case m_wave = "hilal.m.wave"
    case m_player = "hilal.m.player"
    case m_stage = "hilal.m.stage"
    case m_console = "hilal.m.console"
    case m_orbitm = "hilal.m.orbitm"
    case m_turntable = "hilal.m.turntable"
    case m_book = "hilal.m.book"
    case m_tuner = "hilal.m.tuner"
    case r2_tvreel = "r2.tvreel"
    case tv_reel = "hilal.tv.reel"
    case m_wheel = "hilal.m.wheel"
    case m_simple = "hilal.m.simple"
    case m_slim = "hilal.m.slim"
    case r2_verse = "r2.verse"
    case r2_dhikr = "r2.dhikr"
    case r3_quote = "r3.quote"
    case verse = "hilal.verse"
    case r2_files = "r2.files"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"
    static let caseDisplayRepresentations: [DesignMedium: DisplayRepresentation] = [
        .r2_day: DisplayRepresentation(title: "التاريخ ٢", subtitle: "اسم اليوم"),
        .r2_both: DisplayRepresentation(title: "التاريخ ٣", subtitle: "الهجري والميلادي"),
        .r2_triple: DisplayRepresentation(title: "التاريخ ٤", subtitle: "التقويم الثلاثي"),
        .r3_dayclock: DisplayRepresentation(title: "التاريخ ٨", subtitle: "اليوم والساعة"),
        .date: DisplayRepresentation(title: "التاريخ ٩", subtitle: "التاريخ الهجري"),
        .both: DisplayRepresentation(title: "التاريخ ١٠", subtitle: "التاريخ الهجري والميلادي"),
        .triple: DisplayRepresentation(title: "التاريخ ١٦", subtitle: "التقويم الثلاثي"),
        .calm: DisplayRepresentation(title: "التاريخ ١٩", subtitle: "تقويم الشهر الكبير"),
        .hmonths: DisplayRepresentation(title: "التاريخ ٢٠", subtitle: "الأشهر الهجرية"),
        .daym: DisplayRepresentation(title: "التاريخ ٢٢", subtitle: "اسم اليوم الكبير"),
        .triplenames: DisplayRepresentation(title: "التاريخ ٢٣", subtitle: "التقويم الثلاثي بالأسماء"),
        .dual: DisplayRepresentation(title: "التاريخ ٢٤", subtitle: "التقويم المزدوج"),
        .monthm: DisplayRepresentation(title: "التاريخ ٢٦", subtitle: "الشهر ورقم اليوم الكبير"),
        .r2_today: DisplayRepresentation(title: "الصلاة ١", subtitle: "اليوم والصلاة"),
        .r2_prevnext: DisplayRepresentation(title: "الصلاة ٣", subtitle: "السابقة والقادمة"),
        .r2_rings: DisplayRepresentation(title: "الصلاة ٥", subtitle: "حلقات الصلوات"),
        .r3_caps: DisplayRepresentation(title: "الصلاة ٨", subtitle: "كبسولات الصلاة"),
        .prevnext: DisplayRepresentation(title: "الصلاة ٩", subtitle: "الصلاة السابقة والقادمة"),
        .next: DisplayRepresentation(title: "الصلاة ١١", subtitle: "الصلاة القادمة وجدول الصلوات"),
        .agenda: DisplayRepresentation(title: "الصلاة ١٢", subtitle: "التاريخ وجدول الصلوات"),
        .combo: DisplayRepresentation(title: "الصلاة ١٣", subtitle: "التاريخان وعدّاد الصلاة"),
        .prings: DisplayRepresentation(title: "الصلاة ١٥", subtitle: "حلقات الصلوات"),
        .prings2: DisplayRepresentation(title: "الصلاة ١٦", subtitle: "حلقات الصلوات (سطر واحد)"),
        .pcaps: DisplayRepresentation(title: "الصلاة ١٧", subtitle: "أعمدة الصلوات"),
        .dayprayers: DisplayRepresentation(title: "الصلاة ٢٠", subtitle: "اليوم والصلاة"),
        .daydots: DisplayRepresentation(title: "الصلاة ٢١", subtitle: "اليوم والصلوات بالنقاط"),
        .tripleprayer: DisplayRepresentation(title: "الصلاة ٢٢", subtitle: "التقويم الثلاثي والصلاة"),
        .pcaps2: DisplayRepresentation(title: "الصلاة ٢٣", subtitle: "كبسولات الصلاة بالأيقونات"),
        .r2_clockm: DisplayRepresentation(title: "الساعة ١", subtitle: "الساعة الكبيرة"),
        .cdate: DisplayRepresentation(title: "الساعة ٨", subtitle: "الساعة والتاريخان"),
        .dayclock: DisplayRepresentation(title: "الساعة ١٢", subtitle: "اليوم والساعة"),
        .dayclockp: DisplayRepresentation(title: "الساعة ١٣", subtitle: "اليوم والساعة والصلاة"),
        .tickm: DisplayRepresentation(title: "الساعة ١٥", subtitle: "ساعة الإطار والطقس"),
        .r2_wxdays: DisplayRepresentation(title: "الطقس ٢", subtitle: "الطقس والأيام"),
        .r2_daywx: DisplayRepresentation(title: "الطقس ٣", subtitle: "اليوم والطقس"),
        .wxd: DisplayRepresentation(title: "الطقس ٧", subtitle: "الطقس والتاريخ الهجري"),
        .wxt: DisplayRepresentation(title: "الطقس ٨", subtitle: "الطقس مع اسم اليوم"),
        .wxweek: DisplayRepresentation(title: "الطقس ٩", subtitle: "توقعات الأيام"),
        .wxfull: DisplayRepresentation(title: "الطقس ١٠", subtitle: "الطقس المفصّل"),
        .wxdays: DisplayRepresentation(title: "الطقس ١١", subtitle: "طقس الأيام"),
        .wxdayname: DisplayRepresentation(title: "الطقس ١٢", subtitle: "طقس الأيام واليوم"),
        .dayweather: DisplayRepresentation(title: "الطقس ١٣", subtitle: "اليوم والطقس"),
        .r2_playerm: DisplayRepresentation(title: "الوسائط ٢", subtitle: "المشغّل الكبير"),
        .r2_tuner: DisplayRepresentation(title: "الوسائط ٣", subtitle: "بكرة الإذاعات"),
        .m_wave: DisplayRepresentation(title: "الوسائط ١٦", subtitle: "موجة"),
        .m_player: DisplayRepresentation(title: "الوسائط ١٧", subtitle: "مشغّل"),
        .m_stage: DisplayRepresentation(title: "الوسائط ١٨", subtitle: "منصة"),
        .m_console: DisplayRepresentation(title: "الوسائط ١٩", subtitle: "وحدة تحكم"),
        .m_orbitm: DisplayRepresentation(title: "الوسائط ٢٠", subtitle: "مدار"),
        .m_turntable: DisplayRepresentation(title: "الوسائط ٢١", subtitle: "جرامافون"),
        .m_book: DisplayRepresentation(title: "الوسائط ٢٢", subtitle: "كتاب"),
        .m_tuner: DisplayRepresentation(title: "الوسائط ٢٣", subtitle: "بكرة الإذاعات"),
        .r2_tvreel: DisplayRepresentation(title: "القنوات ٢", subtitle: "بكرة القنوات"),
        .tv_reel: DisplayRepresentation(title: "القنوات ٣", subtitle: "بكرة القنوات"),
        .m_wheel: DisplayRepresentation(title: "الوسائط ٢٦", subtitle: "عجلة"),
        .m_simple: DisplayRepresentation(title: "الوسائط ٢٧", subtitle: "الوسائط"),
        .m_slim: DisplayRepresentation(title: "الوسائط ٢٨", subtitle: "وسائط موجة"),
        .r2_verse: DisplayRepresentation(title: "القرآن ٢", subtitle: "آية اليوم"),
        .r2_dhikr: DisplayRepresentation(title: "القرآن ٣", subtitle: "الذكر"),
        .r3_quote: DisplayRepresentation(title: "القرآن ٤", subtitle: "اقتباسات"),
        .verse: DisplayRepresentation(title: "القرآن ٧", subtitle: "آية وأوقات الصلاة"),
        .r2_files: DisplayRepresentation(title: "الأدوات ٣", subtitle: "آخر الملفات"),
    ]
}

enum DesignLarge: String, AppEnum {
    case r2_cal = "r2.cal"
    case r2_week = "r2.week"
    case r3_wxbig = "r3.wxbig"
    case r3_quote = "r3.quote"
    case r3_tasbih = "r3.tasbih"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "الويدجت"
    static let caseDisplayRepresentations: [DesignLarge: DisplayRepresentation] = [
        .r2_cal: DisplayRepresentation(title: "التاريخ ٥", subtitle: "تقويم الشهر"),
        .r2_week: DisplayRepresentation(title: "الصلاة ٧", subtitle: "جدول الأسبوع"),
        .r3_wxbig: DisplayRepresentation(title: "الطقس ٤", subtitle: "الطقس الكامل"),
        .r3_quote: DisplayRepresentation(title: "القرآن ٤", subtitle: "اقتباسات"),
        .r3_tasbih: DisplayRepresentation(title: "القرآن ٥", subtitle: "المسبحة"),
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
    var isGregorian: Bool { calendar.isGregorian && Catalog.info(design.rawValue).hasCalendar }
    /// أسماء الأشهر الميلادية تتبع «التقويم» في كل ويدجت، حتى التي تعرض التاريخين معًا: «ميلادي شامي» شامية، «ميلادي» عادية، «هجري» حسب إعداد التطبيق
    var shamiChoice: Bool? { calendar.shami }
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
    var isGregorian: Bool { calendar.isGregorian && Catalog.info(design.rawValue).hasCalendar }
    /// أسماء الأشهر الميلادية تتبع «التقويم» في كل ويدجت، حتى التي تعرض التاريخين معًا: «ميلادي شامي» شامية، «ميلادي» عادية، «هجري» حسب إعداد التطبيق
    var shamiChoice: Bool? { calendar.shami }
    var bgOpt: BgOpt { bg }
    var fontOpt: FontOpt { font }
    var mediaOpt: String { source == .current ? "" : source.rawValue }
    init() {}
}

struct RafiqiLargeIntent: WidgetConfigurationIntent, Positioned {
    static let title: LocalizedStringResource = "إعداد الويدجت"
    static let description = IntentDescription("اختر الويدجت باسمها، ثم التقويم والمكان والخلفية والخط.")
    @Parameter(title: "الويدجت", default: .r2_cal) var design: DesignLarge
    @Parameter(title: "التقويم", default: .hijri) var calendar: CalOpt
    @Parameter(title: "المكان", default: .mr) var place: PlaceOpt
    @Parameter(title: "لون الخط", default: .app) var tint: TintOpt
    @Parameter(title: "الخلفية", default: .app) var bg: BgOpt
    @Parameter(title: "الخط", default: .app) var font: FontOpt
    var designID: String? { design.rawValue }
    var isGregorian: Bool { calendar.isGregorian && Catalog.info(design.rawValue).hasCalendar }
    /// أسماء الأشهر الميلادية تتبع «التقويم» في كل ويدجت، حتى التي تعرض التاريخين معًا: «ميلادي شامي» شامية، «ميلادي» عادية، «هجري» حسب إعداد التطبيق
    var shamiChoice: Bool? { calendar.shami }
    var bgOpt: BgOpt { bg }
    var fontOpt: FontOpt { font }
    var mediaOpt: String { "" }
    init() {}
}

struct RafiqiSmall: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "rafiqi.small", intent: RafiqiSmallIntent.self,
                               provider: HProvider<RafiqiSmallIntent>(sched: Catalog.info("hilal.day").sched, kind: "hilal.day")) { entry in
            ShamiScope(shami: entry.shami) { Catalog.info(entry.kind).render(entry) }
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
            ShamiScope(shami: entry.shami) { Catalog.info(entry.kind).render(entry) }
        }
        .configurationDisplayName(L("رفيقي — متوسط"))
        .description(L("اضغط مطوّلًا على الويدجت بعد إضافتها، ثم «تعديل الأداة»، واختر الويدجت التي تريدها باسمها."))
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

struct RafiqiLarge: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "rafiqi.large", intent: RafiqiLargeIntent.self,
                               provider: HProvider<RafiqiLargeIntent>(sched: Catalog.info("r2.cal").sched, kind: "r2.cal")) { entry in
            ShamiScope(shami: entry.shami) { Catalog.info(entry.kind).render(entry) }
        }
        .configurationDisplayName(L("رفيقي — كبير"))
        .description(L("اضغط مطوّلًا على الويدجت بعد إضافتها، ثم «تعديل الأداة»، واختر الويدجت التي تريدها باسمها."))
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}


/// أنواع ويدجت الشاشة الرئيسية (لتحديثها)
enum RafiqiKinds {
    static let home = ["rafiqi.small", "rafiqi.medium", "rafiqi.large"]
    static func reload() { for k in home { WidgetCenter.shared.reloadTimelines(ofKind: k) } }
}
