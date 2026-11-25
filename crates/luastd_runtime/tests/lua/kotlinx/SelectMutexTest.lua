-- kotlin: kotlinx-coroutines-core/common/test/selects/SelectMutexTest.kt@1.11.0
describe("SelectMutexTest", function ()
    -- defer: the mutex API has lock/unlock/try_lock but no select expression
    -- or mutex onLock clause, so immediate and suspended select acquisition
    -- cannot be represented.
    pending("testSelectLock")
    pending("testSelectLockWait")
end)
