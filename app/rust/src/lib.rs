#![deny(unsafe_code)]
//! Bridge crate: the only Rust code the Flutter app loads.
//!
//! `flutter_rust_bridge_codegen generate` scans `crate::api` and writes
//! `frb_generated.rs` here plus the Dart bindings in `app/lib/src/rust/`.
//! If codegen does not add it automatically, declare `mod frb_generated;` below.

pub mod api;
#[allow(unsafe_code)]
mod frb_generated;
mod session;
