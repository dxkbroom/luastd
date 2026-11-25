-- kotlin: kotlinx-coroutines-core/common/test/ScopedBuildersCancelledStartTest.kt@1.11.0
describe("ScopedBuildersCancelledStartTest", function ()
    -- not-applicable: ADR 0005 makes cancellation uncatchable by `runtest`'s
    -- pcall, so the Kotlin expected-cancellation assertion cannot be mirrored.
    -- `luastd_async_spec.lua` checks that cancelled parents skip each body.
    pending("testCancelledCoroutineScope")
    pending("testCancelledSupervisorScope")
    pending("testCancelledWithTimeout")
    pending("testWithContext")

    -- not-applicable: luastd has no dispatcher element or dispatcher-switching
    -- with_context overload, so this case's Unconfined-specific behavior cannot
    -- be expressed.
    pending("testWithContextWithDispatcher")
end)
