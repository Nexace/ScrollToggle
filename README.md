# ScrollToggle

A tiny native macOS menu-bar switch for the system Natural Scrolling setting.

## Use

Open **ScrollToggle.app**. The circle-and-arrows icon appears in the menu bar:

- **Left-click:** toggle Natural Scrolling immediately.
- **Filled circle:** on. **Outline circle:** off.
- **Right-click** (or Control-click): status, Launch at Login, Trackpad Settings, Quit.
- **Hover:** a rounded “Scroll Toggle” label in the macOS system font appears after about half a second.
- Launch at Login is initially off. Enable it in the menu if wanted. macOS may ask you to approve it under **System Settings → General → Login Items & Extensions**. A mixed checkmark means approval is pending; select the item to open those settings.

The setting is shared by mouse and trackpad. This changes the real system preference rather than reversing individual scroll events. Quitting keeps your selected preference.

On macOS 10.13–12, Launch at Login opens the manual setup instructions instead of registering automatically.

Download and unzip [ScrollToggle.zip](ScrollToggle.zip), or build the app below. Copy the `.app` into Applications and open it there before enabling login startup. Disable Launch at Login before deleting the app.

## Memory design

Objective-C, AppKit, one small executable, hand-drawn template icon. No Swift runtime, web view, network client, event tap, or persistent helper/service. A tolerant five-second timer and change/wake notifications refresh external changes. Normal operation invokes no command-line tools.

Version 1.2 uses the public app-bundle `LSEnvironment` setting to enable Apple's process-local space-efficient allocation policy (`MallocSpaceEfficient=1`) before a normal launch. It releases temporary startup objects before the main event loop. There is no GUI self-relaunch and no global environment change. A kernel file lock in the user's private temporary directory prevents duplicate icons and is released automatically on exit or crash.

The hover description uses native Liquid Glass on macOS 26 and later, with a frosted background on older releases. It is a temporary native label process. It closes when the pointer leaves or after eight seconds, so label/font/window caches do not remain in the icon process. It uses local status-button tracking and requires no input-monitoring permission.

Opening a native menu on macOS 27 left approximately 6 MB of AppKit caches in the original single-process implementation. The finished app instead launches **the same executable briefly** to show its native menu, hover description, or error dialog. That UI process exits on dismissal; only the small status-item process remains. There is no separately installed helper.

The **under 10 MB target is idle physical footprint**, in decimal MB. Opening the menu temporarily increases total memory while the UI process exists. RSS includes resident shared/framework pages and is larger; this is not an under-10-MB RSS claim. Measurements on other macOS versions can differ. The final glass-label build measured 11.093 MB in its latest sample; earlier builds measured below 10 MB. See `Verification.md` for results.

## Build

Building requires a current Xcode/Command Line Tools installation with both architecture SDK targets. The universal app targets Intel macOS 10.13+ and Apple Silicon macOS 11+. Only macOS 27.0.1 (26A434) has been tested here; see `Compatibility.md` for the exact limits.

```sh
./build.sh
open ScrollToggle.app
```

The script builds and combines Intel x86_64 and Apple Silicon arm64 executables, uses size optimization, and signs locally with an ad-hoc signature. There are no packages to install. It does not install or enable login startup.

Do not rebuild the bundle while its app or menu process is running: quit first.

The local build is not notarized. Sharing outside this Mac calls for Developer ID signing and Apple notarization; transferred/downloaded ad-hoc builds may trigger Gatekeeper. Do not disable Gatekeeper to distribute it. Private framework use makes Mac App Store distribution unsuitable.

## Permissions and compatibility

No Accessibility, Input Monitoring, Screen Recording, Automation, administrator, or Full Disk Access permission is required by this implementation. The app is intentionally not App Sandbox enabled because it changes a current-user global preference. Login startup uses Apple's `SMAppService` and its normal approval flow on macOS 13+. Older versions provide manual System Preferences instructions.

Immediate application uses a **private API**, dynamically resolved at runtime. Apple can change it. If either required function is missing, toggling is disabled and Trackpad Settings remains available. It does not silently fall back to an unverified notification-only change. Managed preferences and malformed values produce a clear error.

## Checks

```sh
./test.sh
./test.sh --live
./ScrollToggle.app/Contents/MacOS/ScrollToggle --diagnose
footprint -p ScrollToggle --noCategories -f bytes
```

Launch the `.app` normally to apply the bundled memory policy. A direct executable launch bypasses Launch Services; for an equivalent diagnostic run, prefix it with `MallocSpaceEfficient=1`. The test script sets this only for its own test processes.

The default tests use in-memory substitutes and do not change macOS preferences. **`--live` temporarily changes Natural Scrolling 100 times**, tests cross-process state sync and native menus, then restores the original value. Run it while the Mac is awake and unlocked, and do not interrupt it. The user confirmed immediate two-finger scrolling reversal; automated checks still verify saved/reported state rather than physical events. Sleep/wake, a full logout/login launch, and registration approval are not reproduced automatically.
