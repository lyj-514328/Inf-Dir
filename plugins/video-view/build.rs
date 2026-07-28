use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let mpv_dev = manifest_dir.join("mpv-dev");

    println!("cargo:rustc-link-search=native={}", mpv_dev.display());
    println!("cargo:rustc-link-lib=dylib=mpv");

    println!("cargo:rerun-if-changed=build.rs");
}
