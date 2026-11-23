-- Port of kotlinx.coroutines' SemaphoreTest.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

-- kotlin: kotlinx-coroutines-core/common/test/sync/SemaphoreTest.kt@1.11.0
describe("SemaphoreTest", function ()
    it(
        "testSimple",
        runtest(function (t)
            local semaphore = async.semaphore(2)
            async.launch(function ()
                t:expect(3)
                semaphore:release()
                t:expect(4)
            end)
            t:expect(1)
            semaphore:acquire()
            semaphore:acquire()
            t:expect(2)
            semaphore:acquire()
            t:finish(5)
        end)
    )

    it(
        "testSimpleAsMutex",
        runtest(function (t)
            local semaphore = async.semaphore(1)
            t:expect(1)
            async.launch(function ()
                t:expect(4)
                semaphore:acquire()
                t:expect(7)
                semaphore:release()
                t:expect(8)
            end)
            t:expect(2)
            semaphore:acquire()
            t:expect(3)
            async.yield()
            t:expect(5)
            semaphore:release()
            t:expect(6)
            async.yield()
            t:finish(9)
        end)
    )

    it(
        "tryAcquireTest",
        runtest(function (t)
            local semaphore = async.semaphore(2)
            assert.is_true(semaphore:try_acquire())
            assert.is_true(semaphore:try_acquire())
            assert.is_false(semaphore:try_acquire())
            assert.is_equal(0, semaphore:available_permits())
            semaphore:release()
            assert.is_equal(1, semaphore:available_permits())
            assert.is_true(semaphore:try_acquire())
            assert.is_equal(0, semaphore:available_permits())
            t:finish(1)
        end)
    )

    it(
        "withSemaphoreTest",
        runtest(function (t)
            local semaphore = async.semaphore(1)
            assert.is_equal(1, semaphore:available_permits())
            semaphore:with_permit(function ()
                assert.is_equal(0, semaphore:available_permits())
            end)
            assert.is_equal(1, semaphore:available_permits())
            t:finish(1)
        end)
    )

    it(
        "withSemaphoreOnFailureTest",
        runtest(function (t)
            local semaphore = async.semaphore(1)
            assert.is_equal(1, semaphore:available_permits())
            local ok, err = pcall(function ()
                semaphore:with_permit(function ()
                    assert.is_equal(0, semaphore:available_permits())
                    error(luastd_test.TestException())
                end)
            end)
            assert.is_false(ok)
            assert.is_equal(1, semaphore:available_permits())
            t:finish(1)
        end)
    )

    it(
        "withSemaphoreOnEarlyReturnTest",
        runtest(function (t)
            local semaphore = async.semaphore(1)
            assert.is_equal(1, semaphore:available_permits())
            local function f()
                semaphore:with_permit(function ()
                    assert.is_equal(0, semaphore:available_permits())
                    return
                end)
            end
            f()
            assert.is_equal(1, semaphore:available_permits())
            t:finish(1)
        end)
    )

    it(
        "fairnessTest",
        runtest(function (t)
            local semaphore = async.semaphore(1)
            semaphore:acquire()
            async.launch(function ()
                t:expect(2)
                semaphore:acquire()
                t:expect(6)
            end)
            async.launch(function ()
                t:expect(3)
                semaphore:acquire()
                t:expect(9)
            end)
            t:expect(1)
            async.yield()
            t:expect(4)
            semaphore:release()
            t:expect(5)
            async.yield()
            t:expect(7)
            semaphore:release()
            t:expect(8)
            async.yield()
            t:finish(10)
        end)
    )

    it(
        "testCancellationReturnsPermitBack",
        runtest(function (t)
            local semaphore = async.semaphore(1)
            semaphore:acquire()
            assert.is_equal(0, semaphore:available_permits())
            local job = async.launch(function ()
                assert.is_false(semaphore:try_acquire())
                semaphore:acquire()
            end)
            async.yield()
            job:cancel()
            async.join(job)
            assert.is_equal(0, semaphore:available_permits())
            semaphore:release()
            assert.is_equal(1, semaphore:available_permits())
            t:finish(1)
        end)
    )

    it(
        "testCancellationDoesNotResumeWaitingAcquirers",
        runtest(function (t)
            local semaphore = async.semaphore(1)
            semaphore:acquire()
            local job1 = async.launch(function ()
                t:expect(2)
                semaphore:acquire()
                t:expect_unreached()
            end)
            local job2 = async.launch(function ()
                t:expect(3)
                semaphore:acquire()
                t:expect_unreached()
            end)
            t:expect(1)
            async.yield()
            t:expect(4)
            job2:cancel()
            async.yield()
            t:expect(5)
            job1:cancel()
            t:finish(6)
        end)
    )

    it(
        "testAcquiredPermits",
        runtest(function (t)
            local semaphore = async.semaphore(5, 4)
            assert.is_equal(1, semaphore:available_permits())
            semaphore:acquire()
            assert.is_equal(0, semaphore:available_permits())
            assert.is_false(semaphore:try_acquire())
            semaphore:release()
            assert.is_equal(1, semaphore:available_permits())
            assert.is_true(semaphore:try_acquire())
            t:finish(1)
        end)
    )

    it(
        "testReleaseAcquiredPermits",
        runtest(function (t)
            local semaphore = async.semaphore(5, 4)
            assert.is_equal(1, semaphore:available_permits())
            for i = 1, 4 do
                semaphore:release()
            end
            assert.is_equal(5, semaphore:available_permits())
            local ok, err = pcall(function () semaphore:release() end)
            assert.is_false(ok)
            for i = 1, 5 do
                assert.is_true(semaphore:try_acquire())
            end
            assert.is_false(semaphore:try_acquire())
            t:finish(1)
        end)
    )

    it("testIllegalArguments", function ()
        local cases = { { -1, 0 }, { 0, 0 }, { 1, -1 }, { 1, 2 } }
        for _, c in ipairs(cases) do
            local ok, err = pcall(function () async.semaphore(c[1], c[2]) end)
            assert.is_false(ok)
        end
    end)

    -- defer: JS miscompilation reproducer; not applicable.
    pending("testWithPermitJsMiscompilation")
end)
