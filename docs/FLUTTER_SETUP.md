# Flutter setup

The Rust side (`crates/core`, `app/rust`) builds and passes its tests without Flutter. The Dart side in `app/lib` was written but **has not been compiled or run**, because the machine that generated this project had no Flutter SDK. Expect small fixes on first run. The first run is also when the platform folders and bindings get generated.

## Prerequisites
- Flutter SDK (stable channel) and, for each target, its toolchain: Android Studio + NDK for Android, Xcode for iOS and macOS (macOS only), Visual Studio C++ tools for Windows, GTK dev packages for Linux.
- Rust via rustup. For Android: `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`. For iOS: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`.
- The codegen tool, **same version as the crate** (`=2.13.0` in `app/rust/Cargo.toml`):
  ```
  cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
  ```

## Steps
0. Snapshot so you can see what the tools change:
   ```
   git init && git add -A && git commit -m "baseline"
   ```
1. Add the platform runners (Android, iOS, desktop):
   ```
   cd app
   flutter create --platforms=android,ios,windows,macos,linux --project-name vaultkeep --org dev.vaultkeep .
   ```
   Check `git status`. If it replaced `lib/main.dart` or added `test/widget_test.dart`, restore ours: `git checkout -- lib test` and delete `test/widget_test.dart`.
2. Wire up flutter_rust_bridge. Run `flutter_rust_bridge_codegen integrate --help` first and compare with the official [quickstart](https://cjycode.com/flutter_rust_bridge/quickstart), then (flag as shown there):
   ```
   flutter_rust_bridge_codegen integrate --integration-backend native-assets
   ```
   Check `git status` again. Keep our `app/rust/` crate (name `rust_lib_vaultkeep`, which must stay) and our `app/lib/main.dart`; restore them if overwritten and delete any sample code it added (for example `rust/src/api/simple.rs`). Make sure `app/pubspec.yaml` contains `flutter_rust_bridge: 2.13.0` exactly.
3. Generate the bindings:
   ```
   flutter_rust_bridge_codegen generate
   ```
   This writes `app/lib/src/rust/**` and `app/rust/src/frb_generated.rs`.
4. Check everything:
   ```
   cd .. && cargo test
   cd app && flutter pub get && flutter analyze && flutter test
   ```
   `flutter test` runs the controller tests against a fake backend and does not need the native library.
5. Run it:
   ```
   flutter run -d linux      # or windows, macos, or a connected Android/iOS device
   ```
   On first launch the app offers to create `vaultkeep.kdbx` in the app documents folder. Type a path inside a Drive/OneDrive/Dropbox folder instead if you want the sync client to carry the file between devices.

## If something fails
- Version mismatch errors: the crate, the Dart package and the codegen tool must all be 2.13.0.
- "library not found": the Rust crate name must be `rust_lib_vaultkeep`, matching the project name `vaultkeep`.
- Codegen did not add `mod frb_generated;` to `app/rust/src/lib.rs`: add it.
- Ask Antigravity to apply the `flutter-rust-bridge` skill; it knows these steps.
