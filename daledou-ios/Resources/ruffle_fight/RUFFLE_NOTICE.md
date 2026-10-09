# Battle replay runtime

The bundled runtime is a custom Ruffle 0.7.1 build named
`daledou-lazy-shapes-playback-rate-batched-heap` (release channel `daledou-lazy-shapes`).
Upstream source: https://github.com/ruffle-rs/ruffle, commit
`89a7049965f3090e706265670df309a5128233ac`.
The lazy-shapes patch keeps encoded static shapes in shared original SWF slices
until first drawing or precise hit testing, and defers renderer allocation until
drawing. Instances share decoded geometry and renderer handles; bounds are preserved.
The independent playback-rate patch adds a live finite 1–4 rate to the Ruffle API.
Frames, movie timers and AVM1/AVM2 getTimer use virtual playback time. Pausing or
changing rate rebases against real transition timestamps without movie reload or
time catch-up. Browser clocks, RAF and ActionScript Date are unchanged. Audio is
not time-stretched or pitch-corrected; stream-audio synchronization may constrain
acceleration. Original combat outcomes are not modified.
The memory-growth patch uses dlmalloc 0.2.14 (MIT OR Apache-2.0,
https://github.com/alexcrichton/dlmalloc-rs) with 4 MiB allocation granularity
for the web heap. It reduces small WASM memory growths that trigger repeated
V8 full GC above the external-memory threshold. It does not preallocate the
whole working set or change movie data; up to one batch of extra slack remains.
The added allocator's copyright and MIT license are in `ruffle/LICENSE_DLMALLOC_MIT`.
Patches, regression tests, source for the AVM2 browser probe and build instructions
are maintained in `android-app/scripts/ruffle/` in the application source repository.

Built with Rust 1.99.0, wasm-bindgen 0.2.127 and the upstream modern-WASM profile,
with Canvas, WebGL, wgpu-webgl and WebGPU support. Optional JPEG XR and wasm-opt
are not enabled. Both wrapper module choices reference this same patched modern
module; there is no unpatched legacy fallback. Unsupported WebAssembly features
produce a load error. Upstream MIT and Apache 2.0 licenses are included in ruffle/.
JavaScript source maps are omitted from the APK.

Lazy-shapes patch SHA-256: `cd57e5d0196f4bc53e7b6043fcc92f9c5ef1b5bf771b3eed619b02a4a42fe9a1`.
Playback-rate patch SHA-256: `4d3fde9b9c4cc742d36d6c84fe7f702285920c6e979642431b9530a6c020e592`.
Memory-growth patch SHA-256: `6fbf86b83202493954d7931c9192d438d9fcd000463d829d81182515e77d8816`.
WASM SHA-256: `8aec43442b18fc3bcc5884203f3c96089cd2d3a01ce492c56dff8b20133ae10e`.

Tencent game assets are fetched from the official public CDN and cached on-device.
The wrapper preserves the original movie and replay JSON. It does not implement combat outcomes.
The native asset loader has no account credentials and blocks unrelated network access.
