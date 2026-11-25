//! `luastd.fs`: permission checks and IO.
#![cfg(feature = "fs")]

mod common;

use std::cell::RefCell;
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;

use luastd_runtime::deno_permissions::PermissionsOptions;
use luastd_runtime::{Fs, PromptDecision, PromptRequest, Prompter, Runtime, permissions};

#[derive(Clone, Default)]
struct Recorder(Rc<RefCell<Vec<PromptRequest>>>);

impl Prompter for Recorder {
    fn prompt(&self, request: PromptRequest) -> Pin<Box<dyn Future<Output = PromptDecision>>> {
        self.0.borrow_mut().push(request);
        Box::pin(async move { PromptDecision::Deny })
    }
}

#[test]
fn fs_spec() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().to_string_lossy().to_string();
    let rt = Runtime::builder()
        .permissions(permissions::allow_all())
        .effect::<Fs>()
        .build()
        .unwrap();
    rt.lua().globals().set("TEST_DIR", path).unwrap();
    common::run_spec(
        &rt,
        "luastd_fs_spec.lua",
        include_str!("lua/luastd_fs_spec.lua"),
    );
    drop(dir);
}

#[test]
fn prompt_denial_is_remembered() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("f.txt");
    let recorder = Recorder::default();
    let opts = PermissionsOptions {
        prompt: true,
        ..Default::default()
    };
    let rt = Runtime::builder()
        .permissions(permissions::from_options(&opts).unwrap())
        .prompter(recorder.clone())
        .effect::<Fs>()
        .build()
        .unwrap();
    let path = file.to_string_lossy().to_string();
    let kind: String = rt
        .run(async |lua| {
            lua.load(format!(
                r#"
                local fs = require("luastd.fs")
                local ok, err = pcall(fs.read, "{path}")
                assert(not ok)
                return err.kind
                "#,
                path = path
            ))
            .eval_async()
            .await
        })
        .unwrap();
    assert_eq!(kind, "PermissionDenied");
    // second call does not prompt again
    assert_eq!(recorder.0.borrow().len(), 1);
}

#[test]
fn try_read_returns_false_on_denial() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("f.txt");
    let recorder = Recorder::default();
    let opts = PermissionsOptions {
        prompt: true,
        ..Default::default()
    };
    let rt = Runtime::builder()
        .permissions(permissions::from_options(&opts).unwrap())
        .prompter(recorder.clone())
        .effect::<Fs>()
        .build()
        .unwrap();
    let path = file.to_string_lossy().to_string();
    let (ok, kind): (bool, String) = rt
        .run(async |lua| {
            lua.load(format!(
                r#"
                local fs = require("luastd.fs")
                local ok, err = fs.try_read("{path}")
                return ok, err.kind
                "#,
                path = path
            ))
            .eval_async()
            .await
        })
        .unwrap();
    assert!(!ok);
    assert_eq!(kind, "PermissionDenied");
}
