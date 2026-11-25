-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectBufferedChannelTest.kt@1.11.0
describe("SelectBufferedChannelTest", function ()
    -- defer: luastd has no select builder or channel on_send clause to test
    -- successful selection of a buffered send.
    pending("testSelectSendSuccess")

    -- defer: no select default clause exists to test the ready-send versus
    -- default branch choice.
    pending("testSelectSendSuccessWithDefault")

    -- defer: channel send/receive exist, but there is no select clause that
    -- atomically chooses the buffered send then receive branch.
    pending("testSelectSendReceiveBuf")

    -- defer: there is no select on_send clause that suspends until buffer
    -- capacity becomes available.
    pending("testSelectSendWait")

    -- defer: there is no select on_receive clause for consuming a ready value.
    pending("testSelectReceiveSuccess")

    -- defer: there is no select default branch to verify that a ready receive
    -- is chosen instead of the fallback.
    pending("testSelectReceiveSuccessWithDefault")

    -- defer: no select default clause or registered receive exists to verify
    -- fallback while empty and cleanup before a later send.
    pending("testSelectReceiveWaitWithDefault")

    -- defer: the channel API has blocking receive but no selectable receive
    -- registration that wakes when another coroutine sends.
    pending("testSelectReceiveWait")

    -- defer: select on_receive has no equivalent for asserting that closed
    -- channels take the exception path from a selection clause.
    pending("testSelectReceiveClosed")

    -- defer: there is no suspended select receive registration to wake when a
    -- channel closes.
    pending("testSelectReceiveWaitClosed")

    -- defer: try_send is immediate and does not register or cancel select
    -- clauses; it cannot test cleanup of 1000 unsuccessful send registrations.
    pending("testSelectSendResourceCleanup")

    -- defer: try_receive is immediate and does not register or cancel select
    -- clauses; it cannot test cleanup of 1000 unsuccessful receive registrations.
    pending("testSelectReceiveResourceCleanup")

    -- defer: the runtime has no select operation whose already-ready receive
    -- clause can be checked for non-suspending dispatch behavior.
    pending("testSelectReceiveDispatchNonSuspending")

    -- defer: there is no select operation to test dispatch ordering when a
    -- selected callback yields before returning.
    pending("testSelectReceiveDispatchNonSuspending2")

    -- defer: receive/close are available, but there is no selectable
    -- on_receive_catching clause to observe closure without throwing.
    pending("testSelectReceiveOrClosedWaitClosed")

    -- defer: close(cause) exists, but no selectable receive-catching clause
    -- can return that cause as a closed result.
    pending("testSelectReceiveOrClosedWaitClosedWithCause")

    -- defer: the API lacks select on_receive_catching registrations, so the
    -- repeated send/receive rendezvous and result assertions are unsupported.
    pending("testSelectReceiveCatching")

    -- defer: no select receive-catching clause exists to test callback
    -- dispatch, yielding, and selected result delivery.
    pending("testSelectReceiveOrClosedDispatch")

    -- defer: try_receive reports closure but cannot model a select clause
    -- synchronously selecting a closed channel and returning a result object.
    pending("testSelectReceiveOrClosedForClosedChannel")

    -- defer: try_receive can yield buffered values, but there is no select
    -- receive-catching clause to distinguish buffered value from closed state.
    pending("testSelectReceiveOrClosedForClosedChannelWithValue")
end)
