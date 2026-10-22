# Compatibility and verification

## What this build covers

ScrollToggle 1.2 is one universal application containing:

- **Intel x86_64:** deployment target macOS 10.13 or later, on systems that support this architecture.
- **Apple Silicon arm64:** deployment target macOS 11.0 or later.

These are build/deployment targets, **not certification that every release has been tested**. macOS 10.12 and earlier, 32-bit Intel, and PowerPC are not supported by this build. Supporting those requires a separate legacy implementation and matching test systems. Future macOS versions cannot be guaranteed because the immediate-apply mechanism is a private Apple API.

| macOS versions | Expected behavior / guard | Verification |
| --- | --- | --- |
| 10.13–10.15, Intel | Native icon, toggle, hover label, Trackpad preferences; login startup is configured manually in System Preferences | Compiles for 10.13; not run on these releases |
| 11–12, Intel / Apple Silicon where supported | Same functionality; manual login startup | Both architecture targets compile; not run on these releases |
| 13–15 and 26 | Native icon and toggle; SMAppService login registration with OS approval handling | Newer API calls guarded; not run on these releases |
| 27.0.1 (26A434), Apple Silicon | Current host; hosted status-item behavior accounted for | Native app, scrolling, visibility, and state sync tested |
| 27.0.1, x86_64 under Rosetta | Intel backend on this Apple Silicon host | Getter, both toggle directions, and exact restoration tested; not equivalent to testing an Intel Mac or an older OS |
| Later versions | Runtime framework/symbol checks; disable toggling if unavailable | Unverified |

## Defensive behavior across releases

- No private framework is linked at build time. The app resolves the required functions at runtime and disables the toggle with a clear settings fallback when they are unavailable.
- The private setting key is accessed with public CFPreferences storage APIs and verified after writes. Managed/malformed preferences are rejected.
- SMAppService is called only on macOS 13+. Older systems open Users & Groups login settings and explain how to add the application manually.
- Trackpad Settings uses the current link on macOS 13+ and the legacy Trackpad preferences link on older systems. If the link fails, it opens the system settings/preferences application.
- Normal startup uses the public LSEnvironment app-bundle key to set the memory policy before launch. It does not re-execute the GUI process or alter the global environment.
- The menu is anchored to the click position rather than trusting the placeholder status-item window frames exposed by newer macOS releases.
- A rounded hover label uses native Liquid Glass on macOS 26 and later, with native frosted material on older releases. It avoids depending on system tooltip forwarding. It uses a temporary native panel process, closes when the pointer leaves, and has an eight-second safety timeout. Pointer tracking is local to the app's own status button; no global input monitor or privacy permission is added.

Actual testing on additional macOS releases is required before advertising them as verified. In particular, successful compilation and Rosetta execution do not prove that the private scrolling API has identical behavior on older systems.
