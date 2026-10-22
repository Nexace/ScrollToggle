# How the toggle works

## Natural reference

Inspected [davidalecrim1/natural](https://github.com/davidalecrim1/natural), pinned to commit `76caac00a390e4cb105e9e1076038e3bb52b15d5`.

Its [scroll module](https://github.com/davidalecrim1/natural/blob/76caac00a390e4cb105e9e1076038e3bb52b15d5/src-tauri/src/scroll.rs) reads and writes the global `com.apple.swipescrolldirection` preference using `defaults`, loads `PreferencePanesSupport.framework`, and calls `setSwipeScrollDirection`. It falls back to a distributed notification if the framework is unavailable. The implementation ignores persistence failures and assumes the requested state succeeded; this app checks both persistence and reported state instead. No upstream Rust/Tauri implementation or assets were copied.

## Verified locally

On macOS 27.0.1 (26A434), arm64:

- `dlopen` successfully loads `/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport`. The framework executable is supplied from the dyld shared cache: the absent on-disk binary is not proof that loading will fail.
- `dlsym` resolves `setSwipeScrollDirection` and `swipeScrollDirection`; guessed names `getSwipeScrollDirection` and `isSwipeScrollDirectionInverted` do not resolve.
- Disassembly shows the setter consumes a full-register 0/1 argument. The implementation uses a 64-bit argument and result on the tested architecture. The setter updates preferences and invokes additional system work, including notification handling.
- The getter refreshes preferences and reads the Boolean value, with an enabled default when absent or of the wrong type. It is **not independent evidence of live hardware behavior**. ScrollToggle rejects malformed stored values instead of silently choosing a default.
- Real integration tests changed both Boolean values, verified persistence and reported state, and restored the exact original preference. Another process's change was reflected by the status item's normal refresh path.

The setter has no useful success result. Saved-state verification does not prove scroll delivery. The user confirmed that clicking the icon reverses physical two-finger trackpad scrolling immediately. The scrolling backend is unchanged in version 1.2.

## Public and private mechanisms

[CFPreferencesSetValue](https://developer.apple.com/documentation/corefoundation/cfpreferencessetvalue(_:_:_:_:_:)) and [CFPreferencesSynchronize](https://developer.apple.com/documentation/corefoundation/cfpreferencessynchronize(_:_:_:)) are supported public preference-storage APIs. The specific system key and private framework functions have no supported public scrolling-setting contract. Preference persistence alone is insufficient evidence that the input system applied a change.

This app uses only the current-user/global/any-host domain and one key. It never replaces the entire global domain, edits plist files directly, kills `cfprefsd`, restarts the input system, or needs root. It checks for managed preferences before changing anything.

A toggle snapshots the original state, writes and synchronizes the desired Boolean, calls the setter, then rereads and verifies the saved/reported state. Failure attempts recovery of the original explicit value or absence. Recovery is best effort; it reports an unverified recovery and avoids overwriting an obviously different concurrent value. CFPreferences provides no atomic compare-and-swap against unrelated apps changing this setting.

The private change notification is only a refresh hint. Its payload is not trusted, and the five-second timer covers missed notifications. The app also refreshes after waking/session activation and before menu display.

## Login startup

The native SDK's `SMAppService.h` documents main-app login registration on macOS 13+, code signing, and enabled/requires-approval/unregistered states. ServiceManagement loads only in the temporary UI process when required. Enabling registration does not create an app-owned launch agent or background helper. The app shows macOS's approval screen when needed; registration starts off.

## Version 1.1 memory policy

Apple’s [libmalloc implementation](https://github.com/apple-oss-distributions/libmalloc/blob/main/src/malloc.c) reads `MallocSpaceEfficient` at initialization. Its space-efficient mode favors releasing unused allocation pages and disables some caching. Controlled app-local trials reduced this app’s physical footprint from roughly 12 MB to below 10 MB. This is an implementation policy, not a hard memory cap; measurements remain the acceptance criterion.

Version 1.2 supplies this policy through Apple's public [LSEnvironment](https://developer.apple.com/documentation/bundleresources/information-property-list/lsenvironment) app-bundle key. The GUI process no longer re-executes itself. This preserves the normal Launch Services startup path; the user confirmed icon visibility after the correction. A kernel-held file lock prevents duplicate instances.

Hosted status items on newer macOS can expose placeholder window frames, so menus use the actual click position. Native tooltip property checks did not prove a description was rendered: the user reported that no tooltip appeared. A custom native hover-label process now handles the description independently of that forwarding path; the user confirmed it appears. The final single-line label reads “Scroll Toggle” and uses native NSGlassEffectView on macOS 26+, with NSVisualEffectView on older releases.
