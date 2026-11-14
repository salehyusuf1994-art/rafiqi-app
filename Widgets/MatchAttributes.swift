import Foundation
import ActivityKit

// MARK: - بيانات النشاط المباشر للمباراة (مشتركة بين التطبيق والويدجت) — يحدّثها التطبيق من الجهاز نفسه

struct MatchAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var hs: Int
        var aws: Int
        var state: String
        var status: String
        var clockStart: Date
        var running: Bool
        var last: String
        var homeRed: Int
        var awayRed: Int
    }
    var matchId: String
    var league: String
    var leagueName: String
    var kickoff: Date
    var home: STeam
    var away: STeam
}

extension MatchAttributes.ContentState {
    init(_ m: SMatch) {
        let lastGoal = m.goals.last
        let lastText = lastGoal.map { "⚽︎ \($0.minute) \($0.player)" } ?? ""
        self.init(hs: m.hs ?? 0, aws: m.aws ?? 0, state: m.state, status: m.status, clockStart: m.clockStart,
                  running: m.running, last: lastText, homeRed: m.reds(m.home.id), awayRed: m.reds(m.away.id))
    }
    var halftime: Bool { status == "STATUS_HALFTIME" }
}
