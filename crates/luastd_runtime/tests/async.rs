//! `luastd.async`: structured concurrency in a runtime (ADR 0003, 0005).

mod common;

use std::cell::RefCell;
use std::rc::Rc;

use luastd_runtime::mlua::{Function, Lua, Result, Table, Value};
use luastd_runtime::{Runtime, cancel_jobs, set_unhandled_handler};

fn runtime() -> Runtime {
    Runtime::builder().build().unwrap()
}

#[test]
fn async_spec() {
    common::run_spec(
        &runtime(),
        "luastd_async_spec.lua",
        include_str!("lua/luastd_async_spec.lua"),
    );
}

#[test]
fn run_waits_for_jobs_launched_by_the_main_chunk() {
    let rt = runtime();
    rt.run(async |lua| {
        lua.load(
            r#"
            local async = require("luastd.async")
            async.launch(function () async.delay(20); done = true end)
            "#,
        )
        .exec_async()
        .await
    })
    .unwrap();
    assert!(rt.lua().globals().get::<bool>("done").unwrap());
}

#[test]
fn scope_removes_children_that_complete_out_of_order() {
    let rt = runtime();
    let order: String = rt
        .run(async |lua| {
            lua.load(
                r#"
                local async = require("luastd.async")
                local completed = {}
                async.scope(function (scope)
                    scope:launch(function () async.delay(25); completed[#completed + 1] = "first" end)
                    scope:launch(function () async.delay(2); completed[#completed + 1] = "second" end)
                    scope:launch(function () async.delay(10); completed[#completed + 1] = "third" end)
                end)
                return table.concat(completed, ",")
                "#,
            )
            .eval_async::<String>()
            .await
        })
        .unwrap();

    assert_eq!(order, "second,third,first");
}

#[test]
fn context_jobs_parent_both_launch_forms_and_runtime_closes_standalone_supervisors() {
    let rt = runtime();
    let supervisor_active_during_run: bool = rt
        .run(async |lua| {
            lua.load(
                r#"
                local async = require("luastd.async")
                supervisor = async.supervisor_job()
                local first = async.context(supervisor, async.coroutine_name("first"))
                local second = async.context(async.coroutine_name("second"), first)
                assert(second:job():is_active())
                assert(second:coroutine_name() == "first")

                local top_level = async.launch(first, function ()
                    assert(async.current_context():coroutine_name() == "first")
                    top_level_ran = true
                end)
                local scoped
                async.scope(function (scope)
                    scoped = scope:launch(second, function ()
                        assert(async.current_context():coroutine_name() == "first")
                        scoped_ran = true
                    end)
                end)
                async.join_all(top_level, scoped)
                return supervisor:is_active()
                "#,
            )
            .eval_async::<bool>()
            .await
        })
        .unwrap();

    assert!(supervisor_active_during_run);
    assert!(rt.lua().globals().get::<bool>("top_level_ran").unwrap());
    assert!(rt.lua().globals().get::<bool>("scoped_ran").unwrap());
    let (active, cancelled, completed): (bool, bool, bool) = rt
        .lua()
        .load("return supervisor:is_active(), supervisor:is_cancelled(), supervisor:is_completed()")
        .eval()
        .unwrap();
    assert!(!active);
    assert!(cancelled);
    assert!(completed);
}

#[test]
fn root_jobs_fail_independently() {
    let rt = runtime();
    rt.run(async |lua| {
        lua.load(
            r#"
            local async = require("luastd.async")
            async.launch(function () async.delay(5); error("lone failure") end)
            async.launch(function () async.delay(20); survived = true end)
            "#,
        )
        .exec_async()
        .await
    })
    .unwrap();
    assert!(rt.lua().globals().get::<bool>("survived").unwrap());
}

#[test]
fn cancel_jobs_stops_background_work() {
    let rt = runtime();
    let ticks: i64 = rt
        .run(async |lua: Lua| -> Result<i64> {
            lua.load(
                r#"
                local async = require("luastd.async")
                ticks = 0
                async.launch(function ()
                    async.finally(function ()
                        while true do async.delay(1); ticks = ticks + 1 end
                    end, function () stopped = true end)
                end)
                "#,
            )
            .exec_async()
            .await?;
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
            cancel_jobs(&lua);
            lua.globals().get("ticks")
        })
        .unwrap();
    assert!(ticks > 0);
    assert!(rt.lua().globals().get::<bool>("stopped").unwrap());
}

#[test]
fn a_failing_main_cancels_launched_jobs() {
    let rt = runtime();
    let result: Result<()> = rt.run(async |lua| {
        lua.load(
            r#"
            local async = require("luastd.async")
            async.launch(function ()
                async.finally(function () async.delay(60000) end, function () cleaned = true end)
            end)
            async.delay(5) -- let the job start; an unstarted job never runs its body
            error("main failed")
            "#,
        )
        .exec_async()
        .await
    });
    assert!(result.unwrap_err().to_string().contains("main failed"));
    assert!(rt.lua().globals().get::<bool>("cleaned").unwrap());
}

#[test]
fn launching_needs_run() {
    let rt = runtime();
    let error = rt
        .lua()
        .load(r#"require("luastd.async").launch(function () end)"#)
        .exec()
        .unwrap_err();
    assert!(error.to_string().contains("Runtime::run"), "{error}");
}

#[test]
fn pcall_is_replaced_but_still_catches_errors() {
    let rt = runtime();
    let (ok, kind): (bool, String) = rt
        .lua()
        .load(r#"local ok, e = pcall(error, { kind = "K" }); return ok, e.kind"#)
        .eval()
        .unwrap();
    assert!(!ok);
    assert_eq!(kind, "K");
    // The replacement is a Lua function, not the C builtin.
    let pcall: Function = rt.lua().globals().get("pcall").unwrap();
    assert!(pcall.info().what != "C");
}

#[test]
fn cancellation_survives_a_rust_frame() {
    let rt = runtime();
    let call = rt
        .lua()
        .create_async_function(|_, f: Function| async move { f.call_async::<()>(()).await })
        .unwrap();
    rt.lua().globals().set("call", call).unwrap();
    let (reached, cancelled): (bool, bool) = rt
        .run(async |lua| {
            lua.load(
                r#"
                local async = require("luastd.async")
                local reached = false
                local job = async.launch(function ()
                    -- `call` is Rust: the cancellation crosses it twice.
                    pcall(call, function () async.delay(1000) end)
                    reached = true
                end)
                async.delay(5)
                job:cancel()
                async.join(job)
                return reached, job:is_cancelled()
                "#,
            )
            .eval_async()
            .await
        })
        .unwrap();
    assert!(!reached, "pcall swallowed a cancellation that crossed Rust");
    assert!(cancelled);
}

#[test]
fn unhandled_failures_go_to_the_handler() {
    let rt = runtime();
    let seen: Rc<RefCell<Vec<String>>> = Rc::default();
    let sink = seen.clone();
    let previous = set_unhandled_handler(
        rt.lua(),
        Some(Rc::new(move |_: &Lua, value: Value| {
            let kind = match value {
                Value::Table(t) => t.get::<String>("kind").unwrap_or_default(),
                other => format!("{other:?}"),
            };
            sink.borrow_mut().push(kind);
        })),
    )
    .unwrap();
    assert!(previous.is_none());
    rt.run(async |lua| {
        lua.load(
            r#"
            local async = require("luastd.async")
            async.launch(function () error({ kind = "Root" }) end)
            async.supervisor_scope(function ()
                async.launch(function () error({ kind = "Supervised" }) end)
                -- awaited failures and cancellations are not unhandled
                local d = async.async(function () error({ kind = "Awaited" }) end)
                async.try_await(d)
                async.launch(function () async.delay(1000) end):cancel()
            end)
            "#,
        )
        .exec_async()
        .await
    })
    .unwrap();
    let mut seen = seen.borrow().clone();
    seen.sort();
    assert_eq!(seen, ["Root", "Supervised"]);
    assert!(set_unhandled_handler(rt.lua(), None).unwrap().is_some());
}

#[test]
fn unhandled_handler_sees_the_error_value() {
    let rt = runtime();
    let kept: Rc<RefCell<Option<Table>>> = Rc::default();
    let sink = kept.clone();
    set_unhandled_handler(
        rt.lua(),
        Some(Rc::new(move |_: &Lua, value: Value| {
            if let Value::Table(t) = value {
                *sink.borrow_mut() = Some(t);
            }
        })),
    )
    .unwrap();
    let raised: Table = rt
        .run(async |lua| {
            lua.load(
                r#"
                local async = require("luastd.async")
                raised = { kind = "Same" }
                async.launch(function () error(raised) end)
                "#,
            )
            .exec_async()
            .await?;
            lua.globals().get("raised")
        })
        .unwrap();
    assert_eq!(
        kept.borrow().as_ref().map(Table::to_pointer),
        Some(raised.to_pointer())
    );
}
