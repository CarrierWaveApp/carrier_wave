import CarrierWaveData
import Foundation
import Testing

struct RegistryRunEventBodyTests {
    @Test func successOutcomeMapsToSuccessBodyWithoutErrorCode() {
        let body = RegistryRunEventBody.from(outcome: .success(executed: 3, elapsed: 0.4))
        #expect(body.success == true)
        #expect(body.failedStepIndex == nil)
        #expect(body.errorCode == nil)
    }

    @Test func failureOutcomeIncludesStepIndexAndShortToken() {
        let body = RegistryRunEventBody.from(
            outcome: .failure(reason: "PTT stuck high after step", stepIndex: 2)
        )
        #expect(body.success == false)
        #expect(body.failedStepIndex == 2)
        #expect(body.errorCode == "ptt-stuck-high-after")
    }

    @Test func cancelledOutcomeReportsCancelToken() {
        let body = RegistryRunEventBody.from(outcome: .cancelled)
        #expect(body.success == false)
        #expect(body.errorCode == "cancelled")
    }

    @Test func shortenStripsPunctuationAndCallsignsAndCaps() {
        let body = RegistryRunEventBody.from(
            outcome: .failure(reason: "Couldn't reach K6FR at 7.030 — try again", stepIndex: nil)
        )
        #expect(body.errorCode == "couldn-t-reach-k6fr")
        #expect((body.errorCode?.count ?? 0) <= 64)
    }

    @Test func emptyReasonProducesUnspecifiedToken() {
        let body = RegistryRunEventBody.from(outcome: .failure(reason: "!!!", stepIndex: nil))
        #expect(body.errorCode == "unspecified")
    }
}
