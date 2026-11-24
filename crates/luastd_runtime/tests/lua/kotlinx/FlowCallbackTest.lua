-- Port of kotlinx.coroutines' FlowCallbackTest.
-- callbackFlow/awaitClose are not implemented in luastd.flow.
-- kotlin: kotlinx-coroutines-core/common/test/flow/channels/FlowCallbackTest.kt@1.11.0
describe("FlowCallbackTest", function ()
    -- defer: callbackFlow and awaitClose are not implemented.
    pending("testClosedPrematurely")

    -- defer: callbackFlow and awaitClose are not implemented.
    pending("testNotClosedPrematurely")
end)