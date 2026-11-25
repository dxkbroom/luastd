-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectRendezvousChannelTest.kt@1.11.0
describe("SelectRendezvousChannelTest", function ()
    -- defer: send/receive are available, but there is no select on_send clause
    -- to match a waiting receiver atomically.
    pending("testSelectSendSuccess")

    -- defer: there is no select default clause to choose a ready rendezvous
    -- send instead of the fallback.
    pending("testSelectSendSuccessWithDefault")

    -- defer: no select on_send registration or default branch exists to test
    -- fallback while a rendezvous receiver is absent.
    pending("testSelectSendWaitWithDefault")

    -- defer: channel:send can suspend, but there is no select on_send clause
    -- that waits for a receiver and invokes a selected callback.
    pending("testSelectSendWait")

    -- defer: there is no select on_receive clause to match a waiting sender.
    pending("testSelectReceiveSuccess")

    -- defer: there is no select default branch to verify a ready receive wins
    -- over fallback when a sender is waiting.
    pending("testSelectReceiveSuccessWithDefault")

    -- defer: try_receive is non-suspending, but there is no select registration
    -- or default branch to verify fallback and later rendezvous cleanup.
    pending("testSelectReceiveWaitWithDefault")

    -- defer: channel:receive can suspend but cannot register as a selectable
    -- receive clause to resume when a sender arrives.
    pending("testSelectReceiveWait")

    -- defer: receive reports channel closure, but there is no select receive
    -- clause to assert that closure takes its exception path.
    pending("testSelectReceiveClosed")

    -- defer: there is no suspended select receive registration to wake with a
    -- closed-channel exception.
    pending("testSelectReceiveWaitClosed")

    -- defer: try_send has no select registration lifecycle, so it cannot test
    -- cleanup of 1000 unsuccessful rendezvous send clauses.
    pending("testSelectSendResourceCleanup")

    -- defer: try_receive has no select registration lifecycle, so it cannot
    -- test cleanup of 1000 unsuccessful rendezvous receive clauses.
    pending("testSelectReceiveResourceCleanup")

    -- defer: channel rendezvous exists, but there is no multi-channel select
    -- operation whose chosen clause can be invalidated by another channel closing.
    pending("testSelectAtomicFailure")

    -- defer: the runtime lacks a select receive clause and selection result,
    -- so callback yield and post-selection dispatch cannot be checked.
    pending("testSelectWaitDispatch")

    -- defer: close is supported, but there is no on_receive_catching clause
    -- that turns closure into a non-throwing result.
    pending("testSelectReceiveCatchingWaitClosed")

    -- defer: close(cause) is supported, but no selectable receive-catching
    -- clause can return the close cause as a result.
    pending("testSelectReceiveCatchingWaitClosedWithCause")

    -- defer: try_receive can report closure, but there is no select
    -- receive-catching result callback for an already closed channel.
    pending("testSelectReceiveCatchingForClosedChannel")

    -- defer: the API lacks select on_receive_catching, needed for repeated
    -- rendezvous delivery with a closed-aware result.
    pending("testSelectReceiveCatching")

    -- defer: no select receive-catching callback exists to test dispatch,
    -- yielding, and delivery of the selected result.
    pending("testSelectReceiveCatchingDispatch")

    -- defer: close and buffered/rendezvous receive exist, but no select send
    -- clause can test failure of a selected send after close.
    pending("testSelectSendWhenClosed")

    -- defer: the runtime has no select builder to reject incompatible send and
    -- receive clauses atomically before channel operations begin.
    pending("testSelectSendAndReceive")

    -- defer: the runtime has no select builder to reject receive and send
    -- clauses atomically before channel operations begin.
    pending("testSelectReceiveAndSend")
end)
