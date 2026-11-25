//! `luastd.process`: permission checks and IO.
#![cfg(feature = "process")]

mod common;

use luastd_runtime::deno_permissions::PermissionsOptions;
use luastd_runtime::{Process, Runtime, permissions};

#[test]
fn process_spec() {
    let rt = Runtime::builder()
        .permissions(permissions::allow_all())
        .effect::<Process>()
        .build()
        .unwrap();
    common::run_spec(
        &rt,
        "luastd_process_spec.lua",
        include_str!("lua/luastd_process_spec.lua"),
    );
}
