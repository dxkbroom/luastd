//! `luastd.flow`: cold flows.

mod common;

use luastd_runtime::Runtime;

#[test]
fn flow_spec() {
    let rt = Runtime::builder().build().unwrap();
    common::run_spec(
        &rt,
        "luastd_flow_spec.lua",
        include_str!("lua/luastd_flow_spec.lua"),
    );
}
