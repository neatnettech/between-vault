import Foundation
import Testing

@testable import BetweenVault

/// The update notice: when it asks Apple, what it believes, and what it shows.
@MainActor
struct UpdateNoticeTests {
    private let day: TimeInterval = 24 * 3600
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    /// A notice whose "App Store" answers with `answers` in turn, and counts the questions.
    private func notice(
        _ defaults: UserDefaults, current: String = "1.0.1", answers: [String?]
    ) -> (UpdateNotice, Counter) {
        let counter = Counter(answers)
        return (UpdateNotice(defaults: defaults, current: current, fetch: { await counter.next() }), counter)
    }

    private actor Counter {
        private var answers: [String?]
        private(set) var asked = 0
        init(_ answers: [String?]) { self.answers = answers }
        func next() -> String? {
            asked += 1
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }

    @Test func aNewerVersionIsOffered() async {
        let (notice, _) = notice(defaults(), answers: ["1.0.2"])
        await notice.check(now: start)
        #expect(notice.available == "1.0.2")
    }

    @Test func theSameOrAnOlderVersionIsNot() async {
        for latest in ["1.0.1", "1.0.0", "0.9"] {
            let (notice, _) = notice(defaults(), answers: [latest])
            await notice.check(now: start)
            #expect(notice.available == nil)
        }
    }

    @Test func versionsCompareByNumberNotByLetters() {
        #expect(UpdateNotice.isNewer("1.0.10", than: "1.0.9"))
        #expect(UpdateNotice.isNewer("1.1", than: "1.0.9"))
        #expect(!UpdateNotice.isNewer("1.0.9", than: "1.0.10"))
        #expect(!UpdateNotice.isNewer("2.0", than: ""))
    }

    @Test func itAsksOnceADay() async {
        let (notice, counter) = notice(defaults(), answers: ["1.0.2", "1.0.3"])
        await notice.check(now: start)
        await notice.check(now: start.addingTimeInterval(day - 1))
        #expect(await counter.asked == 1)
        #expect(notice.available == "1.0.2")
        await notice.check(now: start.addingTimeInterval(day))
        #expect(await counter.asked == 2)
        #expect(notice.available == "1.0.3")
    }

    /// A clock moved back must not hold the next question off for longer than a day.
    @Test func aClockMovedBackAsksAgain() async {
        let (notice, counter) = notice(defaults(), answers: ["1.0.2", "1.0.2"])
        await notice.check(now: start)
        await notice.check(now: start.addingTimeInterval(-10 * day))
        #expect(await counter.asked == 2)
    }

    /// Offline or an unreadable answer: nothing changes, and the next unlock tries again.
    @Test func aFailedAskChangesNothingAndIsRetried() async {
        let (notice, counter) = notice(defaults(), answers: [nil, "1.0.2"])
        await notice.check(now: start)
        #expect(notice.available == nil)
        await notice.check(now: start.addingTimeInterval(60))
        #expect(await counter.asked == 2)
        #expect(notice.available == "1.0.2")
    }

    @Test func dismissingSilencesThatVersionOnly() async {
        let (notice, _) = notice(defaults(), answers: ["1.0.2", "1.0.3"])
        await notice.check(now: start)
        notice.dismiss()
        #expect(notice.available == nil)
        await notice.check(now: start.addingTimeInterval(day))
        #expect(notice.available == "1.0.3")
    }

    /// What was learned and dismissed survives a relaunch, with no new question.
    @Test func aRelaunchKeepsTheState() async {
        let store = defaults()
        let (first, _) = notice(store, answers: ["1.0.2"])
        await first.check(now: start)
        let (second, counter) = notice(store, answers: [])
        #expect(second.available == "1.0.2")
        await second.check(now: start.addingTimeInterval(60))
        #expect(await counter.asked == 0)
        second.dismiss()
        #expect(notice(store, answers: []).0.available == nil)
    }

    /// Once the owner has updated, the stored newer version is no longer newer.
    @Test func updatingClearsTheNotice() async {
        let store = defaults()
        let (old, _) = notice(store, answers: ["1.0.2"])
        await old.check(now: start)
        #expect(notice(store, current: "1.0.2", answers: []).0.available == nil)
    }

    @Test func onlyAVersionShapedAnswerIsBelieved() {
        func answer(_ version: String) -> Data { Data(#"{"resultCount":1,"results":[{"version":"\#(version)"}]}"#.utf8) }
        #expect(UpdateNotice.latestVersion(in: answer("1.0.2")) == "1.0.2")
        #expect(UpdateNotice.latestVersion(in: answer("12")) == "12")
        for bad in ["", "1..2", "1.0.x", "update now!", "١.٠", "1.0.2.3.4.5.6.7.8"] {
            #expect(UpdateNotice.latestVersion(in: answer(bad)) == nil, "\(bad)")
        }
        #expect(UpdateNotice.latestVersion(in: Data(#"{"resultCount":0,"results":[]}"#.utf8)) == nil)
        #expect(UpdateNotice.latestVersion(in: Data("not json".utf8)) == nil)
    }
}
