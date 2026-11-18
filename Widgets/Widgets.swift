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
        // عدّاد الصلاة في الجزيرة الديناميكية وشاشة القفل
        PrayerActivityWidget()
        // أزرار مركز التحكم (امتداد الويدجت يتطلب iOS 18؛ التطبيق نفسه يعمل من iOS 17)
        RadioControl()
        QuranControl()
        SleepControl()
        PrayerCountdownControl()
        ScannerControl()
        QiblaControl()
    }
}
