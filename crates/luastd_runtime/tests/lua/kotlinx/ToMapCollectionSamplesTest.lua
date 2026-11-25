-- kotlin: kotlinx-coroutines-core/common/test/flow/terminal/ToMapCollectionSamplesTest.kt@1.11.0
local flow = require("luastd.flow")
local runtest = require("luastd_test").runtest

local function person(first_name, last_name)
    return { firstName = first_name, lastName = last_name }
end

local scientists = { person("Grace", "Hopper"), person("Jacob", "Bernoulli"), person("Johann", "Bernoulli") }

describe("ToMapCollectionSamplesTest", function ()
    -- adapted: Lua tables do not preserve Kotlin's insertion-ordered Map entries;
    -- compare the resulting keys and values directly instead.
    it(
        "testAssociate",
        runtest(function ()
            local by_last_name = flow.from({ "Grace Hopper", "Jacob Bernoulli", "Johann Bernoulli" }):associate(function (
                name
            )
                local first_name, last_name = name:match("^(%S+) (%S+)$")
                return last_name, first_name
            end)
            assert.same({ Hopper = "Grace", Bernoulli = "Johann" }, by_last_name)
        end)
    )

    -- adapted: verify map contents without relying on Kotlin's insertion order.
    it(
        "testAssociateBy",
        runtest(function ()
            local by_last_name = flow.from(scientists):associate_by(function (value)
                return value.lastName
            end)
            assert.same({
                Hopper = person("Grace", "Hopper"),
                Bernoulli = person("Johann", "Bernoulli")
            }, by_last_name)
        end)
    )

    -- adapted: verify keyed contents without relying on Kotlin's insertion order.
    it(
        "testAssociateByWithValueTransform",
        runtest(function ()
            local by_last_name = flow.from(scientists):associate_by(function (value)
                return value.lastName
            end,
                function (value)
                    return value.firstName
                end)
            assert.same({ Hopper = "Grace", Bernoulli = "Johann" }, by_last_name)
        end)
    )

    -- adapted: Lua maps have no insertion-ordered entries, so compare keyed values.
    it(
        "testAssociateByTo",
        runtest(function ()
            local by_last_name = {}
            assert.same({}, by_last_name)
            local returned = flow.from(scientists):associate_by_to(by_last_name, function (value)
                return value.lastName
            end)
            assert.is_true(returned == by_last_name)
            assert.same({
                Hopper = person("Grace", "Hopper"),
                Bernoulli = person("Johann", "Bernoulli")
            }, by_last_name)
        end)
    )

    -- adapted: Lua maps have no insertion-ordered entries, so compare keyed values.
    it(
        "testAssociateByToWithValueTransform",
        runtest(function ()
            local by_last_name = {}
            assert.same({}, by_last_name)
            flow.from(scientists):associate_by_to(
                by_last_name,
                function (value)
                    return value.lastName
                end,
                function (value)
                    return value.firstName
                end
            )
            assert.is_true(next(by_last_name) ~= nil)
            assert.same({ Hopper = "Grace", Bernoulli = "Johann" }, by_last_name)
        end)
    )

    -- adapted: Lua maps have no insertion-ordered entries, so compare keyed values.
    it(
        "testAssociateTo",
        runtest(function ()
            local by_last_name = {}
            assert.same({}, by_last_name)
            flow.from(scientists):associate_to(by_last_name, function (value)
                return value.lastName, value.firstName
            end)
            assert.is_true(next(by_last_name) ~= nil)
            assert.same({ Hopper = "Grace", Bernoulli = "Johann" }, by_last_name)
        end)
    )

    -- adapted: Lua maps have no insertion-ordered entries, so compare keyed values.
    it(
        "testAssociateWith",
        runtest(function ()
            local with_length = flow.from({ "a", "abc", "ab", "def", "abcd" }):associate_with(function (word)
                return #word
            end)
            assert.same({ a = 1, abc = 3, ab = 2, def = 3, abcd = 4 }, with_length)
        end)
    )

    -- adapted: Kotlin data classes compare structurally, while Lua table keys use
    -- identity; full-name strings preserve the duplicate-key case in this sample.
    it(
        "associateWithTo",
        runtest(function ()
            local names = { "Grace Hopper", "Jacob Bernoulli", "Jacob Bernoulli" }
            local with_length = {}
            assert.same({}, with_length)
            flow.from(names):associate_with_to(with_length, function (name)
                return #name:gsub(" ", "")
            end)
            assert.is_true(next(with_length) ~= nil)
            assert.same({ ["Grace Hopper"] = 11, ["Jacob Bernoulli"] = 14 }, with_length)
        end)
    )

    -- adapted: Lua maps have no insertion-ordered keys; check each group by key.
    it(
        "testGroupBy",
        runtest(function ()
            local words = { "a", "abc", "ab", "def", "abcd" }
            local by_length = flow.from(words):group_by(function (word)
                return #word
            end)
            assert.same({ [1] = { "a" }, [2] = { "ab" }, [3] = { "abc", "def" }, [4] = { "abcd" } }, by_length)
            local mutable_by_length = flow.from(words):group_by_to({}, function (word)
                return #word
            end)
            assert.same(by_length, mutable_by_length)
        end)
    )

    -- adapted: Lua maps have no insertion-ordered keys; check each group by key.
    it(
        "testGroupByWithValueTransform",
        runtest(function ()
            local name_to_team = {
                { name = "Alice", team = "Marketing" }, { name = "Bob", team = "Sales" },
                { name = "Carol", team = "Marketing" }
            }
            local names_by_team = flow.from(name_to_team):group_by(function (entry)
                return entry.team
            end,
                function (entry)
                    return entry.name
                end)
            assert.same({ Marketing = { "Alice", "Carol" }, Sales = { "Bob" } }, names_by_team)
            local mutable_names_by_team = flow.from(name_to_team):group_by_to(
                {},
                function (entry)
                    return entry.team
                end,
                function (entry)
                    return entry.name
                end
            )
            assert.same(names_by_team, mutable_names_by_team)
        end)
    )
end)
