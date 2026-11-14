import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - واجهة النشاط المباشر للمباراة (شاشة القفل والجزيرة الديناميكية) — في امتداد الويدجت فقط

struct LAStatus: View {
    let st: MatchAttributes.ContentState
    let kickoff: Date
    var size: CGFloat = 12
    var body: some View {
        if st.running || (st.state == "pre" && kickoff <= Date()) {
            Text(timerInterval: (st.state == "pre" ? kickoff : st.clockStart)...Date.distantFuture, countsDown: false, showsHours: false)
                .font(.system(size: size, weight: .bold).monospacedDigit())
                .foregroundStyle(S_RED)
                .multilineTextAlignment(.center)
                .frame(width: size * 3.2)
        } else if st.halftime {
            Text(Lang.isEN ? "Half-time" : "استراحة").font(.system(size: size, weight: .bold)).foregroundStyle(S_RED)
        } else if st.state == "post" {
            Text(Lang.isEN ? "Full time" : "انتهت").font(.system(size: size, weight: .semibold)).foregroundStyle(.secondary)
        } else if st.state == "pre" {
            Text(verbatim: "\(STime.time(kickoff)) \(STime.ampm(kickoff))").font(.system(size: size, weight: .semibold))
        } else {
            Text(Lang.isEN ? "Live" : "مباشر").font(.system(size: size, weight: .bold)).foregroundStyle(S_RED)
        }
    }
}

struct LATeam: View {
    let team: STeam
    var reds: Int
    var logo: CGFloat = 40
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                SLogo(team: team, size: logo)
                if reds > 0 {
                    SCard(red: true, n: reds, size: logo * 0.34).offset(x: 4, y: -2)
                }
            }
            Text(team.display).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

struct LAScore: View {
    let st: MatchAttributes.ContentState
    var size: CGFloat = 30
    var body: some View {
        Text(st.state == "pre" ? "–" : lrmPair(ar(st.hs), ar(st.aws), "  -  "))
            .font(.system(size: size, weight: .heavy, design: .rounded).monospacedDigit())
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// في العربي الفريق المستضيف يمين
private func laTeams(_ a: MatchAttributes) -> (left: STeam, right: STeam) {
    Lang.isEN ? (a.home, a.away) : (a.away, a.home)
}

/// فريق جانب في الجزيرة الديناميكية: المنطقة «leading» تكون يمين الشاشة إذا كان اتجاه النظام عربيًا،
/// فنختار الفريق حسب موضع المنطقة الفعلي (المستضيف يمين في العربي ويسار في الإنجليزي)
struct LASide: View {
    let a: MatchAttributes
    let st: MatchAttributes.ContentState
    let leading: Bool
    var compact = false
    @Environment(\.layoutDirection) private var dir
    var body: some View {
        let onLeft = leading == (dir == .leftToRight)
        let sides = laTeams(a)
        let team = onLeft ? sides.left : sides.right
        let isHome = team.id == a.home.id
        let reds = isHome ? st.homeRed : st.awayRed
        let score = isHome ? st.hs : st.aws
        if compact {
            HStack(spacing: 4) {
                if onLeft {
                    SLogo(team: team, size: 18)
                    if st.state != "pre" { Text(ar(score)).font(.system(size: 14, weight: .heavy, design: .rounded)) }
                } else {
                    Text(st.state == "pre" ? STime.time(a.kickoff) : ar(score)).font(.system(size: 14, weight: .heavy, design: .rounded))
                    SLogo(team: team, size: 18)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        } else {
            LATeam(team: team, reds: reds, logo: 34)
        }
    }
}

struct MatchLockView: View {
    let a: MatchAttributes
    let st: MatchAttributes.ContentState
    var body: some View {
        let sides = laTeams(a)
        let leftReds = Lang.isEN ? st.homeRed : st.awayRed, rightReds = Lang.isEN ? st.awayRed : st.homeRed
        let score = Lang.isEN ? st : MatchAttributes.ContentState(hs: st.aws, aws: st.hs, state: st.state, status: st.status,
                                                                    clockStart: st.clockStart, running: st.running, last: st.last,
                                                                    homeRed: st.awayRed, awayRed: st.homeRed)
        VStack(spacing: 6) {
            Text(a.leagueName).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                LATeam(team: sides.left, reds: leftReds).frame(width: 96)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    LAScore(st: score, size: 32)
                    LAStatus(st: st, kickoff: a.kickoff, size: 12)
                }
                Spacer(minLength: 0)
                LATeam(team: sides.right, reds: rightReds).frame(width: 96)
            }
            // الترتيب محسوب لليسار ثم اليمين كما يُرى (المستضيف يمين في العربي)
            .environment(\.layoutDirection, .leftToRight)
            if !st.last.isEmpty {
                Text(st.last).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .environment(\.sTint, .white)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchAttributes.self) { ctx in
            MatchLockView(a: ctx.attributes, st: ctx.state)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let st = ctx.state
            let leftScore = Lang.isEN ? st.hs : st.aws, rightScore = Lang.isEN ? st.aws : st.hs
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LASide(a: ctx.attributes, st: st, leading: true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LASide(a: ctx.attributes, st: st, leading: false)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(st.state == "pre" ? "–" : lrmPair(ar(leftScore), ar(rightScore), "  -  "))
                            .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                        LAStatus(st: st, kickoff: ctx.attributes.kickoff, size: 12)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(st.last.isEmpty ? ctx.attributes.leagueName : st.last)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            } compactLeading: {
                LASide(a: ctx.attributes, st: st, leading: true, compact: true)
            } compactTrailing: {
                LASide(a: ctx.attributes, st: st, leading: false, compact: true)
            } minimal: {
                Text(st.state == "pre" ? "⚽︎" : lrmPair(ar(leftScore), ar(rightScore), "-"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .environment(\.layoutDirection, .leftToRight)
            }
            .keylineTint(S_RED)
        }
    }
}
