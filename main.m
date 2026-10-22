#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/SMAppService.h>
#import <mach/mach.h>
#include <dlfcn.h>
#include <math.h>
#include <sys/file.h>
#include <fcntl.h>
#include <errno.h>

static CFStringRef const ScrollKey = CFSTR("com.apple.swipescrolldirection");
static NSString *const ScrollNotification = @"SwipeScrollDirectionDidChangeNotification";
// Private ABI, inspected on macOS 27 arm64: full-register 0/1 argument/result.
static uint64_t (*GetDirection)(void);
static void (*SetDirection)(uint64_t);
static void *ScrollFramework;

static BOOL Synchronize(void) {
    return CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                   kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static id CopyStored(void) {
    return CFBridgingRelease(CFPreferencesCopyValue(ScrollKey, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
}
static void Store(id value) {
    CFPreferencesSetValue(ScrollKey, (__bridge CFPropertyListRef)value,
                         kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                         kCFPreferencesAnyHost);
}
static BOOL Same(id a, id b) { return a == b || [a isEqual:b]; }
static BOOL IsBoolean(id value) {
    return value && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}
static BOOL IsManaged(void) {
    return CFPreferencesAppValueIsForced(ScrollKey, kCFPreferencesAnyApplication);
}
static NSString *ReadState(BOOL *enabled) {
    if (!GetDirection || !SetDirection)
        return @"This macOS version does not expose the required scrolling functions.";
    if (!Synchronize()) return @"macOS could not refresh the scrolling preference.";
    id raw = CopyStored();
    if (raw && !IsBoolean(raw))
        return @"The scrolling preference has an unexpected type. Set it in Trackpad Settings first.";
    uint64_t state = GetDirection();
    if (state > 1) return @"macOS returned an unrecognized scrolling state.";
    *enabled = state == 1;
    return nil;
}
static NSString *ChangeDirection(void) {
    BOOL before;
    NSString *error = ReadState(&before);
    if (error) return error;
    if (IsManaged()) return @"Natural Scrolling is controlled by your administrator.";
    id original = CopyStored();
    NSNumber *desired = before ? @NO : @YES;
    Store(desired);
    BOOL saved = Synchronize();
    // Do not touch live input state unless persistence succeeded.
    if (saved && Same(CopyStored(), desired)) {
        SetDirection(!before);
        BOOL after;
        error = ReadState(&after);
        if (!error && after == !before && Same(CopyStored(), desired)) return nil;
    }
    // Best effort rollback, but avoid overwriting a different external change.
    if (!Synchronize())
        return @"The change failed and macOS could not refresh the preference for recovery. Check Trackpad Settings.";
    id current = CopyStored();
    if (!Same(current, desired) && !Same(current, original))
        return @"The setting changed elsewhere during the toggle. Check Trackpad Settings.";
    if (IsManaged()) return @"The setting became managed during the toggle. Check Trackpad Settings.";
    SetDirection(before);
    Store(original); // Preserve absence as well as explicit true/false.
    BOOL restored = Synchronize();
    BOOL after;
    NSString *readError = ReadState(&after);
    if (restored && !readError && after == before && Same(CopyStored(), original))
        return @"macOS did not confirm the change. Your previous setting was restored.";
    return @"The change failed and recovery could not be verified. Check Trackpad Settings.";
}
static void LoadScrollFramework(void) {
    ScrollFramework = dlopen("/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport",
                             RTLD_LAZY | RTLD_LOCAL);
    if (ScrollFramework) {
        GetDirection = dlsym(ScrollFramework, "swipeScrollDirection");
        SetDirection = dlsym(ScrollFramework, "setSwipeScrollDirection");
    }
}

// Draw once per state, rather than loading SF Symbols and their asset caches.
static NSImage *StatusIcon(NSInteger state) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(18, 18)];
    [image lockFocus];
    [[NSColor blackColor] set];
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1.5, 1.5, 15, 15)];
    ring.lineWidth = 1.2;
    if (state == 1) [ring fill]; else [ring stroke];
    if (state == 1) [[NSColor clearColor] set];
    NSBezierPath *arrows = [NSBezierPath bezierPath];
    arrows.lineWidth = 1.35;
    arrows.lineCapStyle = NSLineCapStyleRound;
    arrows.lineJoinStyle = NSLineJoinStyleRound;
    [arrows moveToPoint:NSMakePoint(6.5, 5.5)];
    [arrows lineToPoint:NSMakePoint(6.5, 12.5)];
    [arrows moveToPoint:NSMakePoint(4.5, 10.5)];
    [arrows lineToPoint:NSMakePoint(6.5, 12.5)];
    [arrows lineToPoint:NSMakePoint(8.5, 10.5)];
    [arrows moveToPoint:NSMakePoint(11.5, 12.5)];
    [arrows lineToPoint:NSMakePoint(11.5, 5.5)];
    [arrows moveToPoint:NSMakePoint(9.5, 7.5)];
    [arrows lineToPoint:NSMakePoint(11.5, 5.5)];
    [arrows lineToPoint:NSMakePoint(13.5, 7.5)];
    if (state == 1) {
        [NSGraphicsContext currentContext].compositingOperation = NSCompositingOperationClear;
    }
    [arrows stroke];
    [image unlockFocus];
    image.template = YES;
    return image;
}

@interface ScrollApp : NSObject <NSApplicationDelegate>
@property NSStatusItem *item;
@property NSTimer *timer;
@property NSInteger displayedState;
@property BOOL managed;
@property NSString *stateError;
@property BOOL menuOnly;
@property NSPoint menuPosition;
@property NSString *quitToken;
@property NSTask *menuTask;
@property NSString *initialError;
@property NSString *hoverHelp;
@property NSString *hintText;
@property NSPanel *hintPanel;
@property NSTask *hintTask;
@property NSTimer *hoverTimer;
@property NSTrackingArea *hoverArea;
@property NSPoint hintAnchor;
@property NSTimer *hintTimer;
@end

@implementation ScrollApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.displayedState = -2;
    if (self.hintText) { [self presentHint]; return; }
    LoadScrollFramework();
    if (self.initialError) {
        [self showError:self.initialError];
        [NSApp terminate:nil];
        return;
    }
    if (self.menuOnly) {
        NSMenu *menu = [self makeMenu];
        [menu popUpMenuPositioningItem:nil atLocation:self.menuPosition inView:nil];
        [NSApp terminate:nil];
        return;
    }
    self.quitToken = [NSUUID UUID].UUIDString;
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(requestQuit:)
        name:@"local.amogh.ScrollToggle.quit" object:self.quitToken
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    self.item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.item.button.target = self;
    self.item.button.action = @selector(clicked:);
    [self.item.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self.item.button addTrackingArea:self.hoverArea];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:)
        name:ScrollNotification object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    NSNotificationCenter *workspace = [[NSWorkspace sharedWorkspace] notificationCenter];
    [workspace addObserver:self selector:@selector(refresh:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspace addObserver:self selector:@selector(refresh:) name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
    self.timer = [NSTimer timerWithTimeInterval:5 target:self selector:@selector(refresh:)
                                      userInfo:nil repeats:YES];
    self.timer.tolerance = 1;
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self refresh:nil];
    // Re-register after the system has attached the hosted menu-bar view.
    [self performSelector:@selector(updateHoverHelp) withObject:nil afterDelay:1];
}
- (void)applicationDidBecomeActive:(NSNotification *)notification { [self refresh:notification]; }
- (void)refresh:(id)sender {
    (void)sender;
    // Distributed notifications are hints. Always re-read; never trust payloads.
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(refresh:) withObject:nil waitUntilDone:NO];
        return;
    }
    BOOL enabled = NO;
    self.stateError = ReadState(&enabled);
    self.managed = IsManaged();
    NSInteger state = self.stateError ? -1 : enabled;
    if (state != self.displayedState) {
        self.displayedState = state;
        self.item.button.image = StatusIcon(state);
        self.item.button.appearsDisabled = state == -1;
        NSString *label = state == -1 ? @"Natural Scrolling: unavailable" :
                          enabled ? @"Natural Scrolling: on" : @"Natural Scrolling: off";
        [self updateHoverHelp];
        [self.item.button setAccessibilityLabel:@"Toggle Natural Scrolling"];
        [self.item.button setAccessibilityValue:label];
    }
}
- (void)updateHoverHelp {
    NSString *help = @"Scroll Toggle";
    self.hoverHelp = help;
    self.item.button.toolTip = nil; // The label below does not depend on system tooltip forwarding.
    self.item.button.accessibilityHelp = help;
    self.item.button.image.accessibilityDescription = @"Toggle Natural Scrolling";
}
- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    if (getenv("SCROLLTOGGLE_TRACE_HOVER")) fprintf(stderr, "hover entered\n");
    [self.hoverTimer invalidate];
    self.hoverTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self
        selector:@selector(showHint:) userInfo:nil repeats:NO];
}
- (void)mouseExited:(NSEvent *)event { (void)event; [self hideHint]; }
- (void)hideHint {
    [self.hoverTimer invalidate]; self.hoverTimer = nil;
    if (self.hintTask.running) [self.hintTask terminate];
    self.hintTask = nil;
}
- (void)showHint:(id)sender {
    (void)sender;
    self.hoverTimer = nil;
    if (self.menuTask.running || self.hintTask.running) return;
    NSPoint point = [NSEvent mouseLocation];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSBundle mainBundle].executableURL;
    task.arguments = @[@"--hint", [NSString stringWithFormat:@"%.1f",point.x],
        [NSString stringWithFormat:@"%.1f",point.y], self.hoverHelp ?: @"Scroll Toggle"];
    NSError *error = nil;
    if ([task launchAndReturnError:&error]) self.hintTask = task;
    else self.item.button.toolTip = self.hoverHelp;
}
- (void)presentHint {
    // A short-lived native panel keeps text/font/window caches out of the icon process.
    NSTextField *label = [NSTextField labelWithString:self.hintText];
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    label.textColor = [NSColor labelColor];
    label.lineBreakMode = NSLineBreakByClipping;
    label.maximumNumberOfLines = 1;
    NSSize textSize = label.cell.cellSize; // Includes the text field's own padding.
    [label setFrameSize:NSMakeSize(ceil(textSize.width), ceil(textSize.height))];
    NSSize size = NSMakeSize(ceil(label.frame.size.width)+24, ceil(label.frame.size.height)+14);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,size.width,size.height)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    panel.level = NSPopUpMenuWindowLevel;
    panel.hidesOnDeactivate = NO;
    panel.ignoresMouseEvents = YES;
    panel.hasShadow = YES;
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorIgnoresCycle;
    NSRect bounds = NSMakeRect(0,0,size.width,size.height);
    NSView *content = [[NSView alloc] initWithFrame:bounds];
    [label setFrameOrigin:NSMakePoint(12,7)];
    [content addSubview:label];
    if (@available(macOS 26.0, *)) {
        NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:bounds];
        glass.style = NSGlassEffectViewStyleRegular;
        glass.cornerRadius = size.height / 2;
        glass.contentView = content;
        panel.contentView = glass;
    } else {
        NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:bounds];
        if (@available(macOS 10.14, *)) glass.material = NSVisualEffectMaterialToolTip;
        else glass.material = NSVisualEffectMaterialMenu;
        glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        glass.state = NSVisualEffectStateActive;
        glass.wantsLayer = YES;
        glass.layer.cornerRadius = size.height / 2;
        glass.layer.masksToBounds = YES;
        [glass addSubview:content];
        panel.contentView = glass;
    }
    NSPoint point = self.menuPosition;
    NSScreen *screen = [NSScreen mainScreen];
    for (NSScreen *candidate in [NSScreen screens])
        if (NSPointInRect(point,candidate.frame)) { screen = candidate; break; }
    NSRect frame = screen.frame;
    CGFloat x = MAX(NSMinX(frame)+4, MIN(point.x-size.width/2,NSMaxX(frame)-size.width-4));
    CGFloat y = MAX(NSMinY(frame)+4, point.y-size.height-16);
    [panel setFrameOrigin:NSMakePoint(x,y)];
    self.hintAnchor = point;
    self.hintPanel = panel;
    [panel orderFrontRegardless];
    self.hintTimer = [NSTimer scheduledTimerWithTimeInterval:0.15 target:self
        selector:@selector(checkHintPointer:) userInfo:nil repeats:YES];
    [self performSelector:@selector(closeHint) withObject:nil afterDelay:8];
}
- (void)checkHintPointer:(id)sender {
    (void)sender;
    NSPoint point = [NSEvent mouseLocation];
    if (fabs(point.x-self.hintAnchor.x)>24 || fabs(point.y-self.hintAnchor.y)>24) [self closeHint];
}
- (void)closeHint { [self.hintTimer invalidate]; [NSApp terminate:nil]; }
- (void)clicked:(id)sender {
    (void)sender;
    [self hideHint];
    NSEvent *event = [NSApp currentEvent];
    if (event.type == NSEventTypeRightMouseUp || (event.modifierFlags & NSEventModifierFlagControl))
        [self showMenu];
    else [self toggle:nil];
}
- (void)showError:(NSString *)message {
    if (!self.menuOnly) {
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSBundle mainBundle].executableURL;
        task.arguments = @[@"--error", message, self.quitToken];
        NSError *launchError = nil;
        if ([task launchAndReturnError:&launchError]) self.menuTask = task;
        else { NSBeep(); self.item.button.toolTip = message; }
        return;
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"ScrollToggle";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Open Trackpad Settings"];
    if ([alert runModal] == NSAlertSecondButtonReturn) [self openSettings:nil];
}
- (void)toggle:(id)sender {
    (void)sender;
    NSString *error = ChangeDirection();
    [self refresh:nil];
    if (error) [self showError:error];
}
- (SMAppService *)loginService API_AVAILABLE(macos(13.0)) {
    // Keep ServiceManagement and its dependencies unloaded until the menu needs them.
    static Class serviceClass;
    if (!serviceClass) {
        [[NSBundle bundleWithPath:@"/System/Library/Frameworks/ServiceManagement.framework"] load];
        serviceClass = NSClassFromString(@"SMAppService");
    }
    return [serviceClass mainAppService];
}
- (NSMenu *)makeMenu {
    [self refresh:nil];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"ScrollToggle"];
    menu.autoenablesItems = NO;
    NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:
        self.stateError ? @"Natural Scrolling: unavailable" :
        self.displayedState ? @"Natural Scrolling: on" : @"Natural Scrolling: off"
        action:@selector(toggle:) keyEquivalent:@""];
    status.target = self;
    status.enabled = !self.stateError && !self.managed;
    status.state = self.displayedState == 1 ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:status];
    if (self.managed) {
        NSMenuItem *managed = [[NSMenuItem alloc] initWithTitle:@"Controlled by your administrator" action:nil keyEquivalent:@""];
        managed.enabled = NO;
        [menu addItem:managed];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:@"Launch at Login" action:@selector(toggleLogin:) keyEquivalent:@""];
    login.target = self;
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [self loginService];
        login.enabled = service != nil;
        login.state = service.status == SMAppServiceStatusEnabled ? NSControlStateValueOn :
                      service.status == SMAppServiceStatusRequiresApproval ? NSControlStateValueMixed : NSControlStateValueOff;
    } else {
        login.title = @"Launch at Login…";
    }
    [menu addItem:login];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Open Trackpad Settings…" action:@selector(openSettings:) keyEquivalent:@""];
    settings.target = self;
    [menu addItem:settings];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit ScrollToggle" action:@selector(requestQuit:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
    return menu;
}
- (void)showMenu {
    if (self.menuTask.running) return;
    // ponytail: macOS retains ~6 MB of menu caches. A transient UI process releases
    // them at exit, keeping the persistent status item below the idle RAM budget.
    // Hosted status items on newer macOS expose placeholder window frames.
    NSPoint point = [NSEvent mouseLocation];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSBundle mainBundle].executableURL;
    task.arguments = @[@"--menu", [NSString stringWithFormat:@"%.1f", point.x],
                      [NSString stringWithFormat:@"%.1f", point.y - 6], self.quitToken];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) [self showError:error.localizedDescription];
    else self.menuTask = task;
}
- (void)requestQuit:(id)sender {
    (void)sender;
    [self hideHint];
    if (self.menuOnly)
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"local.amogh.ScrollToggle.quit"
            object:self.quitToken userInfo:nil deliverImmediately:YES];
    else if (self.menuTask.running) [self.menuTask terminate];
    [NSApp terminate:nil];
}
- (void)toggleLogin:(id)sender {
    (void)sender;
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [self loginService];
        if (!service) { [self showError:@"macOS could not load login-item support."]; return; }
        NSError *error = nil;
        if (service.status == SMAppServiceStatusRequiresApproval) {
            [[service class] openSystemSettingsLoginItems];
            return;
        }
        BOOL success = service.status == SMAppServiceStatusEnabled ?
            [service unregisterAndReturnError:&error] : [service registerAndReturnError:&error];
        if (!success) [self showError:error.localizedDescription ?: @"macOS could not update Launch at Login."];
        else if (service.status == SMAppServiceStatusRequiresApproval)
            [[service class] openSystemSettingsLoginItems];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
            @"x-apple.systempreferences:com.apple.preferences.users?LoginItems"]];
        [self showError:@"On this macOS version, add ScrollToggle in System Preferences → Users & Groups → Login Items."];
    }
}
- (void)openSettings:(id)sender {
    (void)sender;
    NSString *link;
    if (@available(macOS 13.0, *)) link = @"x-apple.systempreferences:com.apple.Trackpad-Settings.extension";
    else link = @"x-apple.systempreferences:com.apple.preference.trackpad";
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    if (![workspace openURL:[NSURL URLWithString:link]]) {
        NSURL *settings = [workspace URLForApplicationWithBundleIdentifier:@"com.apple.systempreferences"];
        if (settings) [workspace openURL:settings];
    }
}
@end

#ifndef SCROLL_TESTING
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--diagnose") == 0) {
            LoadScrollFramework();
            BOOL enabled = NO;
            NSString *error = ReadState(&enabled);
            printf("private APIs: %s; state: %s; managed: %s\n",
                   GetDirection && SetDirection ? "available" : "unavailable",
                   error ? error.UTF8String : enabled ? "on" : "off", IsManaged() ? "yes" : "no");
            return error ? 1 : 0;
        }
        BOOL menuOnly = argc == 5 && strcmp(argv[1], "--menu") == 0;
        BOOL errorOnly = argc == 4 && strcmp(argv[1], "--error") == 0;
        BOOL hintOnly = argc == 5 && strcmp(argv[1], "--hint") == 0;
        NSPoint position = NSZeroPoint;
        if (menuOnly || hintOnly) {
            char *xEnd, *yEnd;
            double x = strtod(argv[2], &xEnd), y = strtod(argv[3], &yEnd);
            if (!*argv[2] || *xEnd || !*argv[3] || *yEnd || !isfinite(x) || !isfinite(y)) return 2;
            position = NSMakePoint(x, y);
        }
        if (argc != 1 && !menuOnly && !errorOnly && !hintOnly) { fprintf(stderr, "Usage: ScrollToggle [--diagnose]\n"); return 2; }
        NSApplication *app;
        ScrollApp *delegate;
        @autoreleasepool {
            if (!menuOnly && !errorOnly && !hintOnly) {
                // A kernel lock handles simultaneous direct launches and crashes.
                NSString *lockPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"local.amogh.ScrollToggle.lock"];
                int lock = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
                if (lock < 0) { perror("ScrollToggle: instance lock"); return 1; }
                if (flock(lock, LOCK_EX | LOCK_NB) != 0) {
                    int reason = errno;
                    close(lock);
                    if (reason == EWOULDBLOCK) return 0;
                    errno = reason;
                    perror("ScrollToggle: instance lock");
                    return 1;
                }
                // Keep the descriptor open. The OS releases the lock at process exit.
            }
            app = [NSApplication sharedApplication];
            [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
            delegate = [[ScrollApp alloc] init];
            delegate.menuOnly = menuOnly || errorOnly || hintOnly;
            delegate.menuPosition = position;
            if (hintOnly) delegate.hintText = [NSString stringWithUTF8String:argv[4]];
            if (menuOnly) delegate.quitToken = [NSString stringWithUTF8String:argv[4]];
            if (errorOnly) {
                delegate.initialError = [NSString stringWithUTF8String:argv[2]];
                delegate.quitToken = [NSString stringWithUTF8String:argv[3]];
            }
            app.delegate = delegate;
        }
        [app run];
    }
    return 0;
}
#endif
