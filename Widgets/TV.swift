import Foundation
import SwiftUI
import UIKit
import AppIntents

// MARK: - القنوات التلفزيونية العربية (مصدر مفتوح: iptv-org)
// قائمة مختارة بأسماء عربية وتصنيفات، وروابط البث تتجدّد يوميًا من قوائم iptv-org المفتوحة

enum TVCat: String, CaseIterable, Codable {
    case religious, news, general, sports, docs, kids
    var title: String {
        switch self {
        case .religious: return L("دينية")
        case .news: return L("إخبارية")
        case .general: return L("عامة")
        case .sports: return L("رياضية")
        case .docs: return L("وثائقية وثقافية")
        case .kids: return L("أطفال")
        }
    }
    var icon: String {
        switch self {
        case .religious: return "book.closed.fill"
        case .news: return "newspaper.fill"
        case .general: return "tv.fill"
        case .sports: return "sportscourt.fill"
        case .docs: return "globe.desk.fill"
        case .kids: return "balloon.2.fill"
        }
    }
    var color: Color {
        switch self {
        case .religious: return Color(red: 0.89, green: 0.76, blue: 0.50)
        case .news: return Color(red: 0.36, green: 0.62, blue: 0.98)
        case .general: return Color(red: 0.62, green: 0.52, blue: 0.95)
        case .sports: return Color(red: 0.32, green: 0.80, blue: 0.48)
        case .docs: return Color(red: 0.98, green: 0.62, blue: 0.30)
        case .kids: return Color(red: 0.98, green: 0.45, blue: 0.62)
        }
    }
}

struct TVChannel: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var cat: TVCat
    var urls: [String]
    var logo: String
    /// بعض القنوات لا تبث إلا بترويسة «المُحيل» من موقعها
    var referer: String? = nil
    /// ترويسات إضافية للبث (User-Agent، Authorization، Cookie…)
    var headers: [String: String]? = nil
    /// مصدر القناة المضافة (اسم قائمة M3U التي استُوردت منها)
    var source: String? = nil

    /// كل الترويسات التي تُرسل مع طلبات البث
    var httpHeaders: [String: String] {
        var h = headers ?? [:]
        if let r = referer?.trimmingCharacters(in: .whitespaces), !r.isEmpty {
            if h.keys.first(where: { $0.lowercased() == "referer" }) == nil { h["Referer"] = r }
            if h.keys.first(where: { $0.lowercased() == "origin" }) == nil, let u = URL(string: r), let sc = u.scheme, let host = u.host {
                h["Origin"] = sc + "://" + host + (u.port.map { ":\($0)" } ?? "")
            }
        }
        return h
    }
}

enum TVChannels {
    /// القائمة المختارة (روابط احتياطية؛ تُحدَّث من المصدر المفتوح)
    static let builtin: [TVChannel] = [
        TVChannel(id: "AlQuranAlKareemTV.sa", name: "قناة القرآن الكريم", cat: .religious, urls: ["http://m.live.net.sa:1935/live/quran/gmswf.m3u8", "http://m.live.net.sa:1935/live/quran/playlist.m3u8", "https://cdn-globecast.akamaized.net/live/eds/saudi_quran/hls_roku/index.m3u8"], logo: "https://aloula.faulio.com/storage/mediagallery/da/6c/fullhd_7eaf7e165c4cad5b3a45eff65d2011e18be5d670.png"),
        TVChannel(id: "AlSunnahAlNabawiyahTV.sa", name: "قناة السنة النبوية", cat: .religious, urls: ["https://cdn-globecast.akamaized.net/live/eds/saudi_sunnah/hls_roku/index.m3u8", "http://m.live.net.sa:1935/live/sunnah/gmswf.m3u8", "http://m.live.net.sa:1935/live/sunnah/playlist.m3u8"], logo: "https://aloula.faulio.com/storage/mediagallery/33/92/fullhd_879e557011826f507a045b4e0b4c3b57ba93edae.png"),
        TVChannel(id: "HolyQuranRadio.sa", name: "إذاعة القرآن الكريم مرئية", cat: .religious, urls: ["https://live.kwikmotion.com/sbrksaquranradiolive/srpksaquranradio/playlist.m3u8"], logo: "https://aloula.faulio.com/storage/mediagallery/14/da/fullhd_823bc2fe722ede75410492d57fd6c201208b4224.png"),
        TVChannel(id: "QatarTVTheHolyQuran.qa", name: "قطر للقرآن الكريم", cat: .religious, urls: ["https://qatartv.akamaized.net/hls/live/20000612/qtvquran/master.m3u8"], logo: "https://www.qmc.qa/img/LiveChannels/1ca67a44-9290-4b2a-8a16-d8c6e2260816.jpg"),
        TVChannel(id: "SharjahRadioQuran.ae", name: "الشارقة للقرآن الكريم", cat: .religious, urls: ["https://live.kwikmotion.com/smcquranlive/quranradiolive/playlist.m3u8"], logo: "https://i.imgur.com/MxZlOvc.png"),
        TVChannel(id: "IqraaQuran.sa", name: "اقرأ للقرآن", cat: .religious, urls: ["https://playlist.fasttvcdn.com/pl/dlkqw1ftuvuuzkcb4pxdcg/Iqraafasttv2/playlist.m3u8"], logo: "https://i.imgur.com/HPVsIa4.png"),
        TVChannel(id: "IqraaArabic.sa", name: "قناة اقرأ", cat: .religious, urls: ["https://playlist.fasttvcdn.com/pl/dlkqw1ftuvuuzkcb4pxdcg/Iqraafasttv3/playlist.m3u8"], logo: "https://i.imgur.com/HPVsIa4.png"),
        TVChannel(id: "MakkahTV.sa", name: "قناة مكة", cat: .religious, urls: ["https://media2.streambrothers.com:1936/8122/8122/playlist.m3u8"], logo: "https://i.ibb.co/r2k71w5N/download.png"),
        TVChannel(id: "BahrainQuran.bh", name: "البحرين للقرآن الكريم", cat: .religious, urls: ["https://5c7b683162943.streamlock.net/live/ngrp:bahrainquran_all/playlist.m3u8"], logo: "https://i.imgur.com/er5hOK4.png"),
        TVChannel(id: "KTVEthraa.kw", name: "الكويت إثراء", cat: .religious, urls: ["https://kwtethta.cdn.mangomolo.com/eth/smil:eth.stream.smil/chunklist.m3u8"], logo: "https://i.imgur.com/hqEbc49.png"),
        TVChannel(id: "AlistiqamaTV.om", name: "الاستقامة", cat: .religious, urls: ["https://jmc-live.ercdn.net/alistiqama/alistiqama.m3u8"], logo: "https://i.imgur.com/2FPtYZr.png"),
        TVChannel(id: "AlEkhbariya.sa", name: "الإخبارية السعودية", cat: .news, urls: ["https://shd-gcp-live.edgenextcdn.net/live/bitmovin-al-ekhbaria/297b3ef1cd0633ad9cfba7473a686a06/index.m3u8", "https://cdn-globecast.akamaized.net/live/eds/al_ekhbariya/hls_roku/index.m3u8"], logo: "https://i.imgur.com/WcRlHQm.png"),
        TVChannel(id: "Alarabiya.ae", name: "العربية", cat: .news, urls: ["https://live.alarabiya.net/alarabiapublish/alarabiya.smil/playlist.m3u8", "https://live.alarabiya.net/alarabiapublish/alarabiya.smil/alarabiapublish/alarabiya_1080p/chunks.m3u8", "https://shd-gcp-live.edgenextcdn.net/live/bitmovin-alarabiya/7f90de73d777d04f3dada92f90d35c44/index.m3u8"], logo: "https://shahid.mbc.net/mediaObject/a4c125db-ede8-4970-9eed-963948c78651?height=auto&width=512&croppingPoint=&version=1&type=png"),
        TVChannel(id: "AlHadath.sa", name: "الحدث", cat: .news, urls: ["https://shd-gcp-live.edgenextcdn.net/live/bitmovin-hadath/2ff87ec4c2f3ede35295a20637d9f8fd/index.m3u8", "https://av.alarabiya.net/alarabiapublish/alhadath.smil/playlist.m3u8", "https://live.alarabiya.net/alarabiapublish/alhadath.smil/playlist.m3u8"], logo: "https://i.imgur.com/De4SEWE.png"),
        TVChannel(id: "AsharqNews.sa", name: "الشرق للأخبار", cat: .news, urls: ["https://live-news.asharq.com/asharq.m3u8", "https://shd-gcp-live.edgenextcdn.net/live/bitmovin-asharq/10ae30c64e21402c8116a7fb1e5aa789/index.m3u8", "https://svs.itworkscdn.net/bloomberarlive/bloomberg.smil/playlist_dvr.m3u8"], logo: "https://i.imgur.com/bqRC3sl.png"),
        TVChannel(id: "SkyNewsArabia.ae", name: "سكاي نيوز عربية", cat: .news, urls: ["https://live-stream.skynewsarabia.com/c-horizontal-channel/horizontal-stream/index.m3u8", "https://stream.skynewsarabia.com/ott/ott.m3u8", "https://stream.skynewsarabia.com/hls/sna.m3u8"], logo: "https://i.imgur.com/SvjU4h6.png"),
        TVChannel(id: "DW.de@Arabic", name: "DW عربية", cat: .news, urls: ["https://dwamdstream103.akamaized.net/hls/live/2015526/dwstream103/master.m3u8"], logo: "https://i.imgur.com/8MRNFb9.png"),
        TVChannel(id: "France24.fr@Arabic", name: "فرانس 24 عربي", cat: .news, urls: ["https://live.france24.com/hls/live/2037222/F24_AR_HI_HLS/master_5000.m3u8", "https://live.france24.com/hls/live/2037222-b/F24_AR_HI_HLS/master_5000.m3u8", "https://live.france24.com/hls/live/2037222/F24_AR_HI_HLS/master_2300.m3u8"], logo: "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/France_24_logo_%282013%29.svg/960px-France_24_logo_%282013%29.svg.png"),
        TVChannel(id: "TRTArabi.tr", name: "TRT عربي", cat: .news, urls: ["https://tv-trtarabi.medya.trt.com.tr/master.m3u8"], logo: "https://i.imgur.com/dEfI2M9.png"),
        TVChannel(id: "AlJazeera.qa", name: "الجزيرة", cat: .news, urls: ["https://live-hls-apps-aja-fa.getaj.net/AJA/01.m3u8", "https://live-hls-apps-aja-fa.getaj.net/AJA/index.m3u8", "https://live-hls-apps-aja-v3-fa.getaj.net/AJA/index.m3u8"], logo: "https://dtil.tmsimg.com/assets/s159135_ld_h15_aa.png?lock=720x540"),
        TVChannel(id: "AlJazeeraMubasher.qa", name: "الجزيرة مباشر", cat: .news, urls: ["https://live-hls-apps-ajm-fa.getaj.net/AJM/index.m3u8", "https://live-hls-apps-ajm-v3-fa.getaj.net/AJM/index.m3u8", "https://live-hls-web-ajm-fa.thehlive.com/AJM/index.m3u8"], logo: "https://i.imgur.com/DfJI4t5.png"),
        TVChannel(id: "AlArabyTV.qa", name: "العربي", cat: .news, urls: ["https://live.kwikmotion.com/alaraby1live/alaraby_abr/playlist.m3u8", "https://stream.ads.ottera.tv/playlist.m3u8?network_id=5616"], logo: "https://i.imgur.com/YMqWEe4.png"),
        TVChannel(id: "AlGhadTV.eg", name: "الغد", cat: .news, urls: ["https://eazyvwqssi.erbvr.com/alghadtv/alghadtv.m3u8"], logo: "https://i.imgur.com/ga6NXb9.png"),
        TVChannel(id: "KTVNews.kw", name: "كويت الأخبار", cat: .news, urls: ["https://kwtkbta.cdn.mangomolo.com/kb/smil:kb.stream.smil/chunklist.m3u8", "https://kwtktvata.cdn.mangomolo.com/ktva/smil:ktva.stream.smil/chunklist.m3u8", "https://cdn-globecast.akamaized.net/live/eds/ktv_al_akhbar/hls_roku/ktv_al_akhbar.m3u8"], logo: "https://i.imgur.com/erZ0Ol1.png"),
        TVChannel(id: "OmanTVMubashir.om", name: "عُمان مباشر", cat: .news, urls: ["https://partwota.cdn.mgmlcdn.com/omlive/smil:omlive.stream.smil/chunklist.m3u8"], logo: "https://i.imgur.com/UkQTR5b.png"),
        TVChannel(id: "AlMashhad.ae", name: "المشهد", cat: .news, urls: ["https://amg30483-amg30483c23-amgplt0794.playout.now3.amagi.tv/ts-ap-s1-n1/playlist/amg30483-amg30483c23-amgplt0794/playlist.m3u8", "https://amg30483-amg30483c23-amgplt0794.playout.now3.amagi.tv/ts-ap-s1-n1/playlist/amg30483-amg30483c23-amgplt0794/playlist.m3u8?ads.appname=[APP_NAME]&ads.appstoreurl=[APP_STOREURL]&ads.appversion=[APP_VERSION]&ads.bundleid=[APP_BUNDLE]&ads.coppa=0&ads.country=[COUNTRY]&ads.deviceid=[DEVICE_ID]&ads.devicemake=[DEVICE_MAKE]&ads.devicemodel=[DEVICE_MODEL]&ads.devicetype=[DEVICE_TYPE]&ads.donotsell=[DNS]&ads.fck=[FCK]&ads.gdpr=[GDPR]&ads.gdprconsent=[GDPR_CONSENT]&ads.givn=[NONCE]&ads.ic=[IC]&ads.ifa=[IFA]&ads.ifatype=[IFA_TYPE]&ads.ip=[IP]&ads.lat=[LMT]&ads.network_name=[networkname]&ads.targetad=[TARGETAD_ALLOWED]&ads.ua=[UA]&ads.usprivacy=[US_PRIVACY]&ads.viewsize=[VIEWSIZE]"], logo: "https://i.imgur.com/6G6fxs5.png"),
        TVChannel(id: "Medi1TVArabic.ma", name: "ميدي 1 تي في", cat: .news, urls: ["https://cdn.live.easybroadcast.io/abr_corp/83_medi1tv-arabic_g90v4ec/playlist.m3u8", "https://cdn.live.easybroadcast.io/abr_corp/83_medi1tv-arabic_g90v4ec/playlist_dvr.m3u8"], logo: "https://i.imgur.com/3YsZPY6.jpeg"),
        TVChannel(id: "AlArabiyaBusiness.ae", name: "العربية أسواق", cat: .news, urls: ["https://live.alarabiya.net/alarabiapublish/aswaaq.smil/playlist.m3u8"], logo: "https://shahid.mbc.net/mediaObject/73142189-aeca-4f65-8977-d769c91e2573?height=auto&width=600&croppingPoint=&version=1&type=png"),
        TVChannel(id: "CNBCArabiya.ae", name: "CNBC عربية", cat: .news, urls: ["https://cnbc-live.akamaized.net/cnbc/master.m3u8"], logo: "https://upload.wikimedia.org/wikipedia/commons/thumb/e/ea/CNBC_Arabia_2025.svg/960px-CNBC_Arabia_2025.svg.png"),
        TVChannel(id: "AlSharqiyaNews.iq", name: "الشرقية نيوز", cat: .news, urls: ["https://indexforce.com/newshighres/mystream/playlist.m3u8"], logo: "https://i.imgur.com/PeAcXB9.png"),
        TVChannel(id: "AlSaudiya.sa", name: "السعودية", cat: .general, urls: ["https://shd-gcp-live.edgenextcdn.net/live/bitmovin-saudi-tv/2ad66056b51fd8c1b624854623112e43/index.m3u8", "https://cdn-globecast.akamaized.net/live/eds/saudi_tv/hls_roku/index.m3u8"], logo: "https://i.imgur.com/GRQTndk.png"),
        TVChannel(id: "SBC.sa", name: "SBC", cat: .general, urls: ["https://shd-gcp-live.edgenextcdn.net/live/bitmovin-sbc/90e09c0c28db26435799b4a14892a167/index.m3u8"], logo: "https://i.imgur.com/9JSQglj.png"),
        TVChannel(id: "AlSaudiyaAlaan.sa", name: "السعودية الآن", cat: .general, urls: ["https://shd-gcp-live.edgenextcdn.net/live/bitmovin-ksa-now/71ed3aa814c643306c0a8bc4fcc7d17f/index.m3u8"], logo: "https://i.imgur.com/sEOjApe.png"),
        TVChannel(id: "QatarTelevision.qa", name: "تلفزيون قطر", cat: .general, urls: ["https://live.kwikmotion.com/qtv1live/qtv1.smil/playlist.m3u8", "https://qatartv.akamaized.net/hls/live/20000609/qtv1/master.m3u8", "https://streamer1.qna.org.qa/148133273_live/148133273_63.sdp/playlist.m3u8"], logo: "https://i.imgur.com/N5RB4sp.png"),
        TVChannel(id: "OmanTV.om", name: "عُمان", cat: .general, urls: ["https://partneta.cdn.mgmlcdn.com/omantv/smil:omantv.stream.smil/chunklist.m3u8", "https://cdn-globecast.akamaized.net/live/eds/oman_tv/hls_roku/index.m3u8"], logo: "https://i.imgur.com/rBftT9x.png"),
        TVChannel(id: "KTV1.kw", name: "الكويت", cat: .general, urls: ["https://kwtktv1ta.cdn.mangomolo.com/ktv1/smil:ktv1.stream.smil/chunklist.m3u8", "https://cdn-globecast.akamaized.net/live/eds/kuwait_tv1/hls_roku/index.m3u8"], logo: "https://i.imgur.com/kG0d8Ay.png"),
        TVChannel(id: "SharjahTV.ae", name: "الشارقة", cat: .general, urls: ["https://live.kwikmotion.com/smc1live/smc1tv.smil/playlist.m3u8", "https://cdn-globecast.akamaized.net/live/eds/sharjah_tv/hls_roku/index.m3u8"], logo: "https://i.imgur.com/Oz2bPOt.png"),
        TVChannel(id: "AjmanTV.ae", name: "عجمان", cat: .general, urls: ["https://cdn1.logichost.in/ajmantv/live/playlist.m3u8"], logo: "https://i.imgur.com/hVNIwgE.png"),
        TVChannel(id: "AlRayyanTV.qa", name: "الريان", cat: .general, urls: ["https://streamer7.qna.org.qa/148136749_live/148136749_296.sdp/playlist.m3u8", "https://alrayyancdn.vidgyor.com/pub-noalrayy3pwz0l/liveabr/playlist_dvr.m3u8"], logo: "https://i.imgur.com/Ts3RjTV.png"),
        TVChannel(id: "BahrainTV.bh", name: "البحرين", cat: .general, urls: ["https://5c7b683162943.streamlock.net/live/ngrp:bahraintvmain_all/playlist.m3u8"], logo: "https://i.imgur.com/LTD0jIm.png"),
        TVChannel(id: "JordanTV.jo", name: "التلفزيون الأردني", cat: .general, urls: ["https://jrtv-live.ercdn.net/jordanhd/jordanhd.m3u8"], logo: "https://www.jrtv.gov.jo/static/media/jrtv-logo-3.c1d0dd22.png"),
        TVChannel(id: "RoyaTV.jo", name: "رؤيا", cat: .general, urls: ["https://live.kwikmotion.com/royatvpublic/royatv.smil/playlist.m3u8"], logo: "https://i.imgur.com/WX80rty.png"),
        TVChannel(id: "AmmanTV.jo", name: "عمّان", cat: .general, urls: ["https://ammantv-live.ercdn.net/ammantvhd/ammantvhd.m3u8", "https://htvnksdtmy.erbvr.com/ammantvhd/ammantvhd.m3u8"], logo: "https://i.imgur.com/5l7kw0b.png"),
        TVChannel(id: "AlIraqia.iq", name: "العراقية", cat: .general, urls: ["https://imn-live.esite-lab.com/hls/iraqia-general.m3u8"], logo: "https://i.imgur.com/8qQouTW.jpg"),
        TVChannel(id: "ElWatania1.tn", name: "الوطنية التونسية", cat: .general, urls: ["https://sw1.tanitweb.net/TunisiaTV/_definst_/watania1/playlist.m3u8?DVR", "https://sw1.tanitweb.net/TunisiaTV/_definst_/watania1/chunklist.m3u8", "https://sw1.tanitweb.net/TunisiaTV/_definst_/watania2/chunklist.m3u8"], logo: "https://i.imgur.com/gNr2V14.png"),
        TVChannel(id: "KTVSport.kw", name: "الكويت الرياضية", cat: .sports, urls: ["https://kwtspta.cdn.mangomolo.com/sp/smil:sp.stream.smil/chunklist.m3u8"], logo: "https://i.imgur.com/R1hGX1d.png"),
        TVChannel(id: "KTVSportPlus.kw", name: "الكويت الرياضية بلس", cat: .sports, urls: ["https://kwtsplta.cdn.mangomolo.com/spl/smil:spl.stream.smil/chunklist.m3u8"], logo: "https://i.imgur.com/l4oX0gf.png"),
        TVChannel(id: "AlIraqiaSport.iq", name: "العراقية الرياضية", cat: .sports, urls: ["https://imn-live.esite-lab.com/hls/iraqia-sports-1.m3u8"], logo: "https://i.imgur.com/DrrlxTO.png"),
        TVChannel(id: "BahrainSports1.bh", name: "البحرين الرياضية", cat: .sports, urls: ["https://5c7b683162943.streamlock.net/live/ngrp:sportsone_all/playlist.m3u8"], logo: "https://i.imgur.com/fBpLsbC.png"),
        TVChannel(id: "SharjahSports.ae", name: "الشارقة الرياضية", cat: .sports, urls: ["https://svs.itworkscdn.net/smc4sportslive/smc4tv.smil/playlist.m3u8"], logo: "https://i.imgur.com/CsEElsJ.png"),
        TVChannel(id: "OmanSportsTV.om", name: "عُمان الرياضية", cat: .sports, urls: ["https://partneta.cdn.mgmlcdn.com/omsport/smil:omsport.stream.smil/chunklist.m3u8"], logo: "https://i.imgur.com/1omi7p8.png"),
        TVChannel(id: "JordanSport.jo", name: "الأردن الرياضية", cat: .sports, urls: ["https://jrtv-live.ercdn.net/jordansporthd/jordansporthd.m3u8"], logo: "https://i.imgur.com/2EmrZPQ.png"),
        TVChannel(id: "BahrainSports2.bh", name: "البحرين الرياضية ٢", cat: .sports, urls: ["https://5c7b683162943.streamlock.net/live/ngrp:bahrainsportstwo_all/playlist.m3u8"], logo: "https://i.imgur.com/ZkuZmIo.png"),
        // ── قنوات رياضية عالمية رسمية مجانية (لغة غير عربية؛ مسموحة في الرياضية فقط) ──
        TVChannel(id: "FIFAPlus.uk@English", name: "FIFA+", cat: .sports, urls: ["https://a62dad94.wurl.com/master/f36d25e7e52f1ba8d7e56eb859c636563214f541/UmFrdXRlblRWLWV1X0ZJRkFQbHVzRW5nbGlzaF9ITFM/playlist.m3u8"], logo: "https://upload.wikimedia.org/wikipedia/commons/thumb/9/9c/FIFA%2B_(2025).svg/960px-FIFA%2B_(2025).svg.png"),
        TVChannel(id: "beINSPORTSXTRA.us", name: "beIN SPORTS XTRA", cat: .sports, urls: ["https://bein-xtra-bein.amagi.tv/playlist.m3u8"], logo: "https://i.ibb.co/HT49GPmB/XTRA-2.png"),
        TVChannel(id: "CBSSportsGolazoNetwork.us", name: "CBS Golazo", cat: .sports, urls: ["https://dai.google.com/linear/hls/event/7f3Wv6f7QEKfQna22jHqLQ/master.m3u8"], logo: "https://i.imgur.com/eMjutHS.png"),
        TVChannel(id: "RealMadridTV.es", name: "ريال مدريد TV", cat: .sports, urls: ["https://rmtv.akamaized.net/hls/live/2043153/rmtv-es-web/master.m3u8"], logo: "https://i.imgur.com/5pMo7dL.png"),
        TVChannel(id: "InterTV.it", name: "إنتر TV", cat: .sports, urls: ["https://d3k8wzt41aflvx.cloudfront.net/INTERTV/Live.m3u8"], logo: "https://i.imgur.com/FUTqh2L.png"),
        TVChannel(id: "RadioTVSerieA.it", name: "قناة الدوري الإيطالي", cat: .sports, urls: ["https://legaseriea-live-prd.cdn.netrw.it/out/v1/s-prd/ch-01-prd-s-v2/hls-ch-01-prd-s-hd/index.m3u8"], logo: ""),
        TVChannel(id: "SportitaliaSolocalcio.it", name: "سبورت إيطاليا كالتشو", cat: .sports, urls: ["https://distribution.sportitalialive.it/sportitalia/sisolocalcio_abr/playlist.m3u8", "https://edge-001.streamup.eu/sportitalia/sisolocalcio_abr/playlist.m3u8", "https://italiansport-solocalcio-samsung.amagi.tv/playlist.m3u8"], logo: "https://i.imgur.com/hu56Ya5.png"),
        TVChannel(id: "Teledeporte.es", name: "تيلي ديبورتي الإسبانية", cat: .sports, urls: ["https://rtve01p.origin.c21livecloud.com/live-origin/tdp-hls/bitrate_1.m3u8", "https://rtvelivestream.rtve.es/rtvesec/tdp/tdp_main.m3u8"], logo: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d1/TDP_2026.svg/960px-TDP_2026.svg.png"),
        TVChannel(id: "ASpor.tr", name: "A Spor التركية", cat: .sports, urls: ["https://rnttwmjcin.turknet.ercdn.net/lcpmvefbyo/aspor/aspor.m3u8"], logo: "https://i.imgur.com/ZhkZzLf.png"),
        TVChannel(id: "HTSporTV.tr", name: "HT Spor التركية", cat: .sports, urls: ["https://ciner.daioncdn.net/ht-spor/ht-spor.m3u8?app=web"], logo: "https://www.htspor.com/images/manifest/social-share-logo.png"),
        TVChannel(id: "Africa24Sport.fr", name: "أفريقيا 24 سبورت", cat: .sports, urls: ["https://africa24.vedge.infomaniak.com/livecast/ik:africa24sport/manifest.m3u8"], logo: "https://i0.wp.com/africa24tv.com/wp-content/uploads/2023/12/LOGO-AFRICASPORT-4-HD-sans-fond.png?fit=512%2C107&ssl=1"),
        TVChannel(id: "AsharqDocumentary.sa", name: "الشرق الوثائقية", cat: .docs, urls: ["https://svs.itworkscdn.net/asharqdocumentarylive/asharqdocumentary.smil/playlist_dvr.m3u8"], logo: "https://i.imgur.com/v6VsFEt.png"),
        TVChannel(id: "AlJazeeraDocumentary.qa", name: "الجزيرة الوثائقية", cat: .docs, urls: ["https://live-hls-apps-ajd-fa.getaj.net/AJD/index.m3u8", "https://live-hls-web-ajd.getaj.net/AJD/index.m3u8", "https://live-hls-apps-ajd-v3-fa.getaj.net/AJD/index.m3u8"], logo: "https://i.imgur.com/5dNJlLo.png"),
        TVChannel(id: "AsharqDiscovery.sa", name: "الشرق ديسكفري", cat: .docs, urls: ["https://svs.itworkscdn.net/asharqdiscoverylive/asharqd.smil/playlist_dvr.m3u8"], logo: "https://i.imgur.com/Czxi7yk.png"),
        TVChannel(id: "AlArabiyaPrograms.ae", name: "العربية برامج", cat: .docs, urls: ["https://live.alarabiya.net/alarabiapublish/aaprograms.smil/playlist.m3u8"], logo: "https://i.imgur.com/Hoc3cfO.png"),
        TVChannel(id: "SaudiThaqafiyaTV.sa", name: "الثقافية السعودية", cat: .docs, urls: ["https://shd-gcp-live.edgenextcdn.net/live/bitmovin-thaqafeyyah/28c0d2a20dbf1dc049ce15d3973f494b/index.m3u8"], logo: "https://shahid.mbc.net/mediaObject/55f69983-5b4b-47c7-9c25-06ed5ad860a4?height=auto&width=512&croppingPoint=&version=1&type=jpeg"),
        TVChannel(id: "OmanTVCultural.om", name: "عُمان الثقافية", cat: .docs, urls: ["https://partwota.cdn.mgmlcdn.com/omcultural/smil:omcultural.stream.smil/chunklist.m3u8"], logo: "https://i.imgur.com/b38wNPK.png"),
        TVChannel(id: "AtfalMawahebTV.sa", name: "أطفال ومواهب", cat: .kids, urls: ["https://5aafcc5de91f1.streamlock.net/atfal1.com/atfal2/playlist.m3u8", "https://5d658d7e9f562.streamlock.net/atfal1.com/atfal2/playlist.m3u8"], logo: "https://i.imgur.com/Y2BqP9m.png"),
        TVChannel(id: "SpacetoonArabic.ae", name: "سبيستون", cat: .kids, urls: ["https://live-uae-next.spacetoongo.com/ST_MENA_NEXT/hls/r9p2hjipmw2kl.m3u8"], logo: "https://upload.wikimedia.org/wikipedia/en/2/2b/Spacetoon_logo.png", referer: "https://spacetoon.com"),
        TVChannel(id: "AmouYazidTV.dz", name: "عمو يزيد", cat: .kids, urls: ["http://mkstream.servehttp.com:1940/AmouYazid/ay1/playlist.m3u8"], logo: "https://i.imgur.com/L8UPGPC.png"),
    ]

    private static var d: UserDefaults { AppGroup.defaults }

    /// القنوات بروابطها الأحدث (المحدّثة أولًا ثم الاحتياطية)
    static var all: [TVChannel] {
        let fresh = (d.dictionary(forKey: "tv_urls") as? [String: [String]]) ?? [:]
        return builtin.map { c in
            guard let f = fresh[c.id], !f.isEmpty else { return c }
            var n = c
            var seen = Set<String>()
            n.urls = (f + c.urls).filter { seen.insert($0).inserted }
            return n
        } + custom
    }

    // ── قنوات يضيفها المستخدم برابط بثها ──
    static var custom: [TVChannel] {
        get { d.data(forKey: "tv_custom").flatMap { try? JSONDecoder().decode([TVChannel].self, from: $0) } ?? [] }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "tv_custom") }
    }
    static func isCustom(_ id: String) -> Bool { id.hasPrefix("custom.") }
    static func addCustom(name: String, url: String, cat: TVCat, referer: String?,
                          headers: [String: String]? = nil, logo: String = "") {
        addCustom([TVChannel(id: "custom." + UUID().uuidString, name: name, cat: cat, urls: [url], logo: logo,
                             referer: (referer?.isEmpty ?? true) ? nil : referer,
                             headers: (headers?.isEmpty ?? true) ? nil : headers)])
    }
    /// إضافة عدة قنوات دفعة واحدة (من قائمة M3U)؛ يتجاهل الروابط المضافة مسبقًا
    @discardableResult
    static func addCustom(_ list: [TVChannel]) -> Int {
        var l = custom
        var have = Set(all.flatMap(\.urls))   // يتجاهل ما هو موجود أصلًا (الأساسية والمضافة)
        var n = 0
        for c in list where !c.urls.isEmpty && !have.contains(c.urls[0]) {
            l.append(c); have.insert(c.urls[0]); n += 1
        }
        custom = l
        return n
    }
    /// تعديل قناة مضافة (الاسم، الرابط، القسم، الترويسات)
    static func updateCustom(_ c: TVChannel) {
        custom = custom.map { $0.id == c.id ? c : $0 }
    }
    static func removeCustom(_ id: String) { removeCustom(Set([id])) }
    static func removeCustom(_ ids: Set<String>) {
        custom = custom.filter { !ids.contains($0.id) }
        favorites = favorites.filter { !ids.contains($0) }
    }

    static func channel(_ id: String) -> TVChannel? { all.first { $0.id == id } }
    static func list(_ cat: TVCat) -> [TVChannel] { all.filter { $0.cat == cat } }

    // ── المفضلة ──
    static var favorites: [String] {
        get { d.stringArray(forKey: "tv_favs") ?? [] }
        set { d.set(newValue, forKey: "tv_favs") }
    }
    static func toggle(_ id: String) {
        var f = favorites
        if let i = f.firstIndex(of: id) { f.remove(at: i) } else { f.append(id) }
        favorites = f
    }
    static var favChannels: [TVChannel] {
        let a = all
        return favorites.compactMap { id in a.first { $0.id == id } }
    }

    /// قائمة البكرة في الويدجت: المفضلة ثم الدينية والإخبارية ثم الباقي
    static var reel: [TVChannel] {
        var seen = Set<String>()
        let order: [TVCat] = [.religious, .news, .general, .sports, .docs, .kids]
        let rest = order.flatMap { list($0) }
        return (favChannels + rest).filter { seen.insert($0.id).inserted }
    }

    /// آخر قناة شوهدت
    static var last: String? {
        get { d.string(forKey: "tv_last") }
        set { d.set(newValue, forKey: "tv_last") }
    }

    // ── تحديث الروابط مرة يوميًا من قوائم iptv-org المفتوحة ──
    static func refreshIfNeeded() async {
        guard Date().timeIntervalSince1970 - d.double(forKey: "tv_urls_at") > 86400 else { return }
        let ids = Set(builtin.map(\.id))
        // الرمز بعد النقطة هو الدولة (DW.de@Arabic ← de)
        let countries = Set(builtin.compactMap { $0.id.split(separator: "@").first?.split(separator: ".").last.map(String.init) })
        var found: [String: [String]] = [:]
        await withTaskGroup(of: [String: [String]].self) { g in
            for cc in countries {
                g.addTask { await fetch(cc, ids: ids) }
            }
            for await r in g { for (k, v) in r { found[k, default: []] += v } }
        }
        guard !found.isEmpty else { return }
        d.set(found, forKey: "tv_urls")
        d.set(Date().timeIntervalSince1970, forKey: "tv_urls_at")
    }

    private static func fetch(_ cc: String, ids: Set<String>) async -> [String: [String]] {
        guard let u = URL(string: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/\(cc).m3u") else { return [:] }
        var req = URLRequest(url: u); req.timeoutInterval = 12
        guard let res = try? await URLSession.shared.data(for: req),
              (res.1 as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: res.0, encoding: .utf8) else { return [:] }
        var out: [String: [String]] = [:]
        var current: String?
        var skip = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                current = nil; skip = false
                if let r = line.range(of: "tvg-id=\""), let e = line[r.upperBound...].firstIndex(of: "\"") {
                    let full = String(line[r.upperBound..<e])
                    let base = full.split(separator: "@").first.map(String.init) ?? ""
                    let name = line.split(separator: ",", maxSplits: 1).last.map(String.init) ?? ""
                    // القناة بفرعها (مثل DW العربي) إن كان مسجّلًا هكذا، وإلا القناة نفسها
                    let key = ids.contains(full) ? full : (ids.contains(base) ? base : nil)
                    // البث الإنجليزي لا يفيدنا
                    if let key, !name.contains("English") { current = key }
                }
            } else if line.hasPrefix("#EXTVLCOPT") {
                skip = true   // يحتاج ترويسات خاصة لا يدعمها المشغّل
            } else if !line.hasPrefix("#"), !line.isEmpty, let id = current {
                if !skip, line.hasPrefix("http") { out[id, default: []].append(line) }
                current = nil
            }
        }
        return out
    }
}

// MARK: - شعارات الإذاعات والقنوات (محفوظة في مجلد التطبيق المشترك لتظهر في الويدجت)

enum LogoCache {
    private static func key(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }
    static func file(_ url: String) -> URL? {
        AppGroup.container?.appendingPathComponent("logos", isDirectory: true).appendingPathComponent(key(url) + ".png")
    }
    static func image(_ url: String?) -> UIImage? {
        guard let url, !url.isEmpty, let f = file(url) else { return nil }
        return UIImage(contentsOfFile: f.path)
    }
    /// لون بطاقة الشعار: الشعارات البيضاء/الفاتحة (مثل «الحدث») تختفي على بطاقة بيضاء، فتأخذ بطاقة داكنة
    private static var tileCache: [String: Bool] = [:]
    private static let tileLock = NSLock()
    static func tile(for url: String?, image img: UIImage) -> Color {
        let k = url ?? ""
        tileLock.lock(); let hit = tileCache[k]; tileLock.unlock()
        let light = hit ?? isLight(img)
        if hit == nil { tileLock.lock(); tileCache[k] = light; tileLock.unlock() }
        return light ? Color(red: 0.13, green: 0.14, blue: 0.16) : .white
    }
    /// متوسط سطوع الأجزاء المرئية من الشعار (بعد تصغيره إلى ٢٤×٢٤)
    private static func isLight(_ img: UIImage) -> Bool {
        let n = 24
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let cg = img.cgImage else { return false }
        // الذاكرة تبقى صالحة طوال الرسم (كان المؤشر يُمرَّر لحظة الإنشاء فقط)
        let drawn = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return false }
        var sum = 0.0, cnt = 0.0, white = 0.0
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 128 {
            let a = Double(px[i + 3]) / 255
            let l = (0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])) / 255 / a
            sum += l; cnt += 1
            if l > 0.86 { white += 1 }
        }
        // صورة بلا شفافية (مربع كامل) لها خلفيتها الخاصة: لا نغيّر شيئًا
        guard cnt > 0, cnt < Double(n * n) * 0.97 else { return false }
        // شعار أغلبه أبيض (مثل «الحدث»: كتابة بيضاء وزوايا حمراء) يحتاج بطاقة داكنة
        return sum / cnt > 0.82 || white / cnt > 0.45
    }

    /// ينزّل الشعارات الناقصة (مصغّرة إلى ١٢٠ نقطة) — من التطبيق فقط
    static func fetch(_ urls: [String]) async {
        let fm = FileManager.default
        guard let dir = AppGroup.container?.appendingPathComponent("logos", isDirectory: true) else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for u in Set(urls) where !u.isEmpty {
            guard let f = file(u), !fm.fileExists(atPath: f.path), let url = URL(string: u) else { continue }
            var req = URLRequest(url: url); req.timeoutInterval = 10
            guard let res = try? await URLSession.shared.data(for: req), let img = UIImage(data: res.0) else { continue }
            let side: CGFloat = 120
            let s = min(side / max(1, img.size.width), side / max(1, img.size.height))
            let size = CGSize(width: max(1, img.size.width * s), height: max(1, img.size.height * s))
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
            try? small.pngData()?.write(to: f, options: .atomic)
        }
    }
}

// MARK: - بكرة الويدجت: تقليب الإذاعات أو القنوات

enum Reel {
    static func page(_ kind: String) -> Int { AppGroup.defaults.integer(forKey: "reel_" + kind) }
    static func move(_ kind: String, by d: Int) {
        AppGroup.defaults.set(page(kind) + d, forKey: "reel_" + kind)
    }
    /// العناصر الظاهرة من القائمة في الصفحة الحالية (تدور البكرة بلا نهاية)
    static func window<T>(_ list: [T], kind: String, count: Int) -> [T] {
        guard !list.isEmpty else { return [] }
        let n = list.count, start = ((page(kind) * count) % n + n) % n
        return (0..<min(count, n)).map { list[(start + $0) % n] }
    }
}

/// زر تقليب البكرة في الويدجت (لا يفتح التطبيق)
struct ReelIntent: AppIntent {
    static let title: LocalizedStringResource = "تقليب القائمة"
    static let isDiscoverable = false
    @Parameter(title: "النوع") var kind: String
    @Parameter(title: "الاتجاه") var delta: Int
    init() {}
    init(_ kind: String, _ delta: Int) { self.kind = kind; self.delta = delta }
    func perform() async throws -> some IntentResult {
        Reel.move(kind, by: delta)
        return .result()
    }
}
