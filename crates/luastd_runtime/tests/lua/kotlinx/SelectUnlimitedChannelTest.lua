-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectUnlimitedChannelTest.kt@1.11.0
describe("SelectUnlimitedChannelTest", function ()
    -- defer: luastd supports async.UNLIMITED channels, send, and close, but has
    -- no select builder or Channel:on_send clause to test a selected send's
    -- failure after the channel is closed with a buffered value still present.
    pending("testSelectSendWhenClosed")
end)
