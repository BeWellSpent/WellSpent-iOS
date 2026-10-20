import Testing
@testable import WellSpent

@Suite("PushEventCenter")
@MainActor
struct PushEventCenterTests {
    @Test("a subscriber receives a published event")
    func subscriberReceivesPublishedEvent() async {
        let center = PushEventCenter()
        let stream = center.subscribe()
        var iterator = stream.makeAsyncIterator()

        center.publish(PushEvent(alertType: "review_pending", budgetProfileID: "budget-1"))

        let received = await iterator.next()
        #expect(received?.alertType == "review_pending")
        #expect(received?.budgetProfileID == "budget-1")
    }

    @Test("multiple concurrent subscribers each receive the same event")
    func multipleSubscribersEachReceiveEvent() async {
        let center = PushEventCenter()
        var iteratorA = center.subscribe().makeAsyncIterator()
        var iteratorB = center.subscribe().makeAsyncIterator()

        center.publish(PushEvent(alertType: "period_created", budgetProfileID: "budget-2"))

        let receivedA = await iteratorA.next()
        let receivedB = await iteratorB.next()
        #expect(receivedA?.budgetProfileID == "budget-2")
        #expect(receivedB?.budgetProfileID == "budget-2")
    }
}
