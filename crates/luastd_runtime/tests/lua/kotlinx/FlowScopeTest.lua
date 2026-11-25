-- Port of kotlinx.coroutines' FlowScopeTest.
-- Cancellation/scope semantics differ in the single-threaded runtime.
-- kotlin: kotlinx-coroutines-core/common/test/flow/internal/FlowScopeTest.kt@1.11.0
describe("FlowScopeTest", function ()
    -- defer: cancellation propagation through flow scopes not yet ported.
    pending("testCancellation")

    -- defer: cancellation propagation through flow scopes not yet ported.
    pending("testCancellationWithChildCancelled")

    -- defer: suspension-point cancellation not yet ported.
    pending("testCancellationWithSuspensionPoint")

    -- defer: nested scope semantics not yet ported.
    pending("testNestedScopes")
end)
