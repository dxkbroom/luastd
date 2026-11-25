-- Port of kotlinx.coroutines' MutexTest.

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

-- kotlin: kotlinx-coroutines-core/common/test/sync/MutexTest.kt@1.11.0
describe("MutexTest", function ()
    it(
        "testSimple",
        runtest(function (t)
            local mutex = async.mutex()
            t:expect(1)
            async.launch(function ()
                t:expect(4)
                mutex:lock()
                t:expect(7)
                mutex:unlock()
                t:expect(8)
            end)
            t:expect(2)
            mutex:lock()
            t:expect(3)
            async.yield()
            t:expect(5)
            mutex:unlock()
            t:expect(6)
            async.yield()
            t:finish(9)
        end)
    )

    it("tryLockTest", function ()
        local mutex = async.mutex()
        assert.is_false(mutex:is_locked())
        assert.is_true(mutex:try_lock())
        assert.is_true(mutex:is_locked())
        assert.is_false(mutex:try_lock())
        assert.is_true(mutex:is_locked())
        mutex:unlock()
        assert.is_false(mutex:is_locked())
        assert.is_true(mutex:try_lock())
        assert.is_true(mutex:is_locked())
        assert.is_false(mutex:try_lock())
        assert.is_true(mutex:is_locked())
        mutex:unlock()
        assert.is_false(mutex:is_locked())
    end)

    it(
        "withLockTest",
        runtest(function (t)
            local mutex = async.mutex()
            assert.is_false(mutex:is_locked())
            mutex:with_lock(function ()
                assert.is_true(mutex:is_locked())
            end)
            assert.is_false(mutex:is_locked())
            t:finish(1)
        end)
    )

    it(
        "testWithLockFailureUnlocksTheMutex",
        runtest(function (t)
            local mutex = async.mutex()
            assert.is_false(mutex:is_locked())
            local ok, err = pcall(function ()
                mutex:with_lock(function ()
                    t:expect(1)
                    assert.is_true(mutex:is_locked())
                    error(luastd_test.TestException())
                end)
            end)
            assert.is_false(ok)
            t:expect(2)
            assert.is_false(mutex:is_locked())
            t:finish(3)
        end)
    )

    it(
        "withLockOnEarlyReturnTest",
        runtest(function (t)
            local mutex = async.mutex()
            assert.is_false(mutex:is_locked())
            local function f()
                mutex:with_lock(function ()
                    assert.is_true(mutex:is_locked())
                    return
                end)
            end
            f()
            assert.is_false(mutex:is_locked())
            t:finish(1)
        end)
    )

    -- adapted: the runtime schedules waiters on its LocalSet instead of
    -- recursively resuming them through Unconfined; exercise queued lock
    -- handoff with a bounded number of waiters supported by this runtime.
    it(
        "testUnconfinedStackOverflow",
        runtest({ timeout = 10000 }, function ()
            local waiters = 128
            local mutex = async.mutex(true)
            local entered = 0
            local done = 0
            local jobs = {}
            for _ = 1, waiters do
                jobs[#jobs + 1] = async.launch(function ()
                    entered = entered + 1
                    mutex:with_lock(function () done = done + 1 end)
                end)
            end
            while entered < waiters do
                async.yield()
            end
            mutex:unlock()
            for _, job in ipairs(jobs) do
                async.join(job)
            end
            assert.is_equal(waiters, done)
        end)
    )

    it(
        "holdLock",
        runtest(function (t)
            local mutex = async.mutex()
            local firstOwner = {}
            local secondOwner = {}

            assert.is_false(mutex:holds_lock(firstOwner))
            assert.is_false(mutex:holds_lock(secondOwner))

            mutex:lock(firstOwner)
            local secondLockJob = async.launch(function ()
                mutex:lock(secondOwner)
            end)

            assert.is_true(mutex:holds_lock(firstOwner))
            assert.is_false(mutex:holds_lock(secondOwner))

            mutex:unlock(firstOwner)
            async.join(secondLockJob)

            assert.is_false(mutex:holds_lock(firstOwner))
            assert.is_true(mutex:holds_lock(secondOwner))

            mutex:unlock(secondOwner)

            assert.is_false(mutex:holds_lock(firstOwner))
            assert.is_false(mutex:holds_lock(secondOwner))
            t:finish(1)
        end)
    )

    it("testUnlockWithNullOwner", function ()
        local owner = {}
        local mutex = async.mutex()
        assert.is_true(mutex:try_lock(owner))
        local ok, err = pcall(function () mutex:unlock({}) end)
        assert.is_false(ok)
        mutex:unlock(nil)
        assert.is_false(mutex:holds_lock(owner))
        assert.is_false(mutex:is_locked())
    end)

    it(
        "testUnlockWithoutOwnerWithLockedQueue",
        runtest(function (t)
            local owner = {}
            local owner2 = {}
            local mutex = async.mutex()
            assert.is_true(mutex:try_lock(owner))
            t:expect(1)
            async.launch(function ()
                t:expect(2)
                mutex:lock(owner2)
            end)
            async.yield()
            t:expect(3)
            local ok, err = pcall(function () mutex:unlock(owner2) end)
            assert.is_false(ok)
            mutex:unlock()
            assert.is_false(mutex:holds_lock(owner))
            assert.is_true(mutex:holds_lock(owner2))
            t:finish(4)
        end)
    )

    it(
        "testIllegalStateInvariant",
        runtest(function (t)
            local mutex = async.mutex()
            local owner = {}
            assert.is_true(mutex:try_lock(owner))
            local ok1 = pcall(function () mutex:try_lock(owner) end)
            assert.is_false(ok1)
            local ok2 = pcall(function () mutex:lock(owner) end)
            assert.is_false(ok2)
            t:finish(1)
        end)
    )

    -- not-applicable: this reproduces a Kotlin/JS IR inlining bug in the
    -- Kotlin compiler; luastd does not target Kotlin/JS or share that compiler.
    pending("testWithLockJsMiscompilation")

    it("testMutexIsNotSemaphore", function ()
        assert.is_nil(getmetatable(async.mutex())._core)
    end)
end)
