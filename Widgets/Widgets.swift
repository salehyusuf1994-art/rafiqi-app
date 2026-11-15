import SwiftUI
import WidgetKit
import AppIntents

// ويدجت الشاشة الرئيسية: ثلاث ويدجت بالمقاس (صغير/متوسط/كبير) في Designs.swift،
// وتُختار الويدجت نفسها باسمها من «تعديل الأداة» — بدل ١٠٠ ويدجت منفصلة في قائمة الإضافة.

@main
struct HilalWidgetBundle: WidgetBundle {
    var body: some Widget {
        RafiqiSmall()
        RafiqiMedium()
        LockGroup().body
        LockGroup2().body
    }
}
