use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let la = manifest_dir.join("libarchive");

    println!(
        "cargo:rustc-link-search=native={}",
        la.join("lib").display()
    );
    println!("cargo:rustc-link-lib=dylib=libarchive");
    println!("cargo:rerun-if-changed=libarchive/lib/libarchive.lib");

    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let target_dir = out_dir.ancestors().nth(3).unwrap();
    let dll_src = la.join("bin/archive.dll");
    let dll_dst = target_dir.join("archive.dll");
    if dll_src.exists() && !dll_dst.exists() {
        let _ = fs::copy(&dll_src, &dll_dst);
    }
}
