import SwiftUI
import WidgetKit
import AppIntents

// ويدجت الشاشة الرئيسية: ثلاث ويدجت بالمقاس (صغير/متوسط/كبير) في Designs.swift،
// وتُختار الويدجت نفسها باسمها من «تعديل الأداة» — بدل ١٠٠ ويدجت منفصلة في قائمة الإضافة.

struct SportsC: WidgetBundle {
    var body: some Widget { LS_Rect(); LS_Circle(); LS_Inline(); MatchLiveActivity() }
}
@main
struct HilalWidgetBundle: WidgetBundle {
    var body: some Widget {
        RafiqiSmall()
        RafiqiMedium()
        RafiqiLarge()
        LockGroup().body
        LockGroup2().body
        SportsC().body
    }
}
