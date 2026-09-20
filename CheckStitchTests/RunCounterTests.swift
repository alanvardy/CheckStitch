import CheckStitchCore
import Foundation
import Testing

@MainActor
struct RunCounterTests {
    @Test
    func missingValueReadsZero() {
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        #expect(counter.count == 0)
    }

    @Test
    func incrementPersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let counter = RunCounter(defaults: defaults)
        counter.increment()
        counter.increment()

        let fresh = RunCounter(defaults: defaults)
        #expect(fresh.count == 2, "a fresh instance over the same suite reads the persisted value")
    }

    @Test
    func corruptValueReadsZero() {
        let defaults = makeIsolatedDefaults()
        defaults.set("nope", forKey: RunCounter.defaultsKey)

        let counter = RunCounter(defaults: defaults)
        #expect(counter.count == 0)
    }

    @Test
    func negativeValueReadsZero() {
        let defaults = makeIsolatedDefaults()
        defaults.set(-4, forKey: RunCounter.defaultsKey)

        let counter = RunCounter(defaults: defaults)
        #expect(counter.count == 0)
    }

    @Test
    func resetReturnsToZero() {
        let defaults = makeIsolatedDefaults()
        let counter = RunCounter(defaults: defaults)
        counter.increment()
        counter.increment()
        counter.reset()

        #expect(counter.count == 0)
    }
}