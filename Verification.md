# Verification results — version 1.2

Verified 23 October 2026, macOS 27.0.1 (26A434), Apple Silicon.

## Memory

All MB below are decimal (1 MB = 1,000,000 bytes), measured as physical footprint. The version 1.1 measurements are retained as historical regression evidence; they are not measurements of the final glass-label build.

| Measurement | Result |
| --- | ---: |
| Version 1.2 build 6, current shipping process sample | 11.093 MB |
| Prior version 1.0, settled shipping process | 12.551 MB |
| Version 1.1, shipping process opened normally through Launch Services | 8.766 MB |
| Version 1.1, shipping process peak in that sample | 8.799 MB |
| Version 1.1, later settled shipping sample | 8.373 MB |
| Instrumented version 1.1, initial settled idle | 9.471 MB |
| Instrumented version 1.1 after 100 toggles, external sync checks, three native menu open/close cycles | 8.914 MB |
| Shipping process RSS at the normal-launch sample | 47,264 KiB |

The under 10 MB idle physical-footprint target passed for version 1.1 on this Mac. The current version 1.2 build 6 sample was **11.093 MB**, so the final glass-label build is not currently verified below 10 MB. RSS is a different measurement and remains above 10 MB. A temporary UI process exists while a menu or error dialog is open, so combined active memory can exceed 10 MB. No idle UI helper remained after the menu cycles. Measurements are observations, not a hard cap across OS updates or every runtime condition.

Apple’s process-local space-efficient allocation mode accounts for most of the reduction. Startup objects are also released before the main event loop. The app retains the original toggle backend; an experimental separate toggle-worker design was not needed or shipped.

## Passed checks

- Unit checks: both directions, managed settings, missing APIs, malformed values, invalid reported state, synchronization failure, write/apply recovery, recovery of an absent key, avoiding an obviously different external value, and 100 repeated toggles.
- 100 real system toggles with icon-state checks and exact original preference restoration.
- A separate process changed the setting. The ordinary notification/timer refresh path synchronized the icon without manual refresh. Restoration synchronized as well.
- Three native menus rendered in short-lived copies of the executable, then each UI process exited.
- Normal Launch Services opening stays running with one icon. A subsequent direct launch exits cleanly without creating another status-item process. A kernel-held lock handles single-instance protection independently of Launch Services placeholder PIDs.
- Allocator startup with the variable absent, explicitly enabled, and explicitly disabled all completed diagnosis successfully. The environment policy affects only this app and its child UI process.
- The user confirmed the custom hover description is visible. The final label reads “Scroll Toggle”; its rendered layout was checked to contain both words. It uses the macOS system font and native Liquid Glass on macOS 26+, with a frosted fallback on older releases.
- The user confirmed that clicking the icon reverses physical two-finger trackpad scrolling immediately. The scrolling backend is unchanged in version 1.2.
- The universal build compiles for x86_64 macOS 10.13 and arm64 macOS 11. The x86_64 backend passed both toggle directions and exact restoration under Rosetta on this host. This does not verify older macOS or Intel hardware.
- Version 1.2 uses the public LSEnvironment bundle setting for its process-local allocator policy. The user confirmed that the icon is visible after correcting startup.
- ServiceManagement loads and login registration status can be queried; no registration was enabled during testing.
- Icon rendering visually inspected; filled and outlined versions use the same native drawing function.
- App property list and local ad-hoc code signature validated.

## Limits

Full logout/login startup, enabling/disabling registration approval, actual sleep/wake, a real managed configuration profile, Intel hardware, and other macOS releases remain unverified. Wake/session refresh handlers and managed-setting rejection are implemented. Saved/reported-state automation does not independently verify physical input events; that behavior was confirmed by the user.
