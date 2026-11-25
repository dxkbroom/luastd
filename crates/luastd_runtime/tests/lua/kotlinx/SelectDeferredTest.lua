-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectDeferredTest.kt@1.11.0
describe("SelectDeferredTest", function ()
    -- defer: the async API can await a Deferred but has no select builder or
    -- Deferred:on_await clause to register and run this completion handler.
    pending("testSimpleReturnsImmediately")

    -- defer: this case checks a selected Deferred clause across yields; the
    -- runtime has no select builder or Deferred:on_await registration API.
    pending("testSimpleWithYield")

    -- defer: selection also starts a lazy Deferred; luastd has lazy launch but
    -- no select/on_await operation to trigger it through a registered clause.
    pending("testSelectIncompleteLazy")

    -- defer: selecting the first completed among two Deferreds and invoking
    -- only its clause requires the absent select builder and on_await clauses.
    pending("testSelectTwo")

    -- defer: this selects between an exceptional and successful Deferred, so
    -- await on one Deferred cannot test selection precedence or clause choice.
    pending("testSelectFailure")

    -- defer: the test waits for a selected Deferred cancellation and relies on
    -- select cancellation propagation; no select builder/on_await exists.
    pending("testSelectCancel")

    -- defer: deferred completion-state assertions are made inside a select
    -- builder before registering on_await; luastd has no such builder/clauses.
    pending("testSelectIncomplete")

    -- defer: this requires an unconfined dispatcher to complete immediately
    -- before the on_await clause is registered; neither select nor dispatchers
    -- are exposed by luastd.
    pending("testSelectIncompleteFastPath")
end)
