// Opt-in live check: changes Natural Scrolling 100 times, restores it, tests menus.
#define main ProductMain
#include "main.m"
#undef main
#import <objc/runtime.h>
#include <assert.h>
static double Footprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return info.phys_footprint / 1000000.0;
}
// Test-only menu dismissal; no input synthesis or Accessibility permission.
@interface NSMenu (Verification)
- (BOOL)verifyPopup:(NSMenuItem *)item atLocation:(NSPoint)point inView:(NSView *)view;
@end
@implementation NSMenu (Verification)
- (BOOL)verifyPopup:(NSMenuItem *)item atLocation:(NSPoint)point inView:(NSView *)view {
    printf("Menu process: native popup entered.\n"); fflush(stdout);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self cancelTracking];
    });
    return [self verifyPopup:item atLocation:point inView:view]; // Swizzled original.
}
@end
@interface VerifyApp : ScrollApp
@property id original;
@property BOOL originalDirection;
@property BOOL failed;
@property int menuChecks;
@end
@implementation VerifyApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [super applicationDidFinishLaunching:notification];
    BOOL before = NO;
    NSString *error = ReadState(&before);
    if (error || IsManaged()) { fprintf(stderr,"Cannot test: %s\n",error.UTF8String ?: "managed preference"); exit(1); }
    self.original = CopyStored(); self.originalDirection = before;
    [self performSelector:@selector(exercise) withObject:nil afterDelay:3];
}
- (void)exercise {
    printf("Idle physical footprint: %.3f MB\n", Footprint());
    @try {
        for (int i=0;i<100;i++) {
            @autoreleasepool {
                NSString *error = ChangeDirection();
                if (error) [NSException raise:@"Verification" format:@"%@",error];
                [self refresh:nil];
                if (self.displayedState != (i % 2 ? self.originalDirection : !self.originalDirection))
                    [NSException raise:@"Verification" format:@"Icon state mismatch"];
            }
        }
        printf("PASS: 100 real toggles and icon refreshes.\n");
    } @catch (NSException *exception) {
        self.failed = YES; fprintf(stderr,"FAIL: %s\n",exception.reason.UTF8String);
    } @finally {
        SetDirection(self.originalDirection); Store(self.original);
        BOOL restored = Synchronize(), after = NO;
        NSString *error = ReadState(&after);
        if (!restored || error || after != self.originalDirection || !Same(CopyStored(), self.original)) {
            self.failed = YES;
            fprintf(stderr,"FAIL: original setting could not be verified. Check Trackpad Settings.\n");
        } else printf("PASS: exact original preference restored.\n");
    }
    NSTask *external = [[NSTask alloc] init];
    external.executableURL = [NSBundle mainBundle].executableURL;
    external.arguments = @[@"--external-toggle"];
    NSError *launchError = nil;
    if (![external launchAndReturnError:&launchError]) {
        self.failed = YES;
        fprintf(stderr, "FAIL: external toggle launch: %s\n", launchError.localizedDescription.UTF8String);
        [self checkMenu];
        return;
    }
    [external waitUntilExit];
    if (external.terminationStatus) self.failed = YES;
    [self performSelector:@selector(checkExternalChange) withObject:nil afterDelay:6.5];
}
- (void)checkExternalChange {
    if (self.stateError || self.displayedState != !self.originalDirection) {
        self.failed = YES; fprintf(stderr,"FAIL: external state did not sync.\n");
    } else printf("PASS: external-process change synchronized without manual refresh.\n");
    SetDirection(self.originalDirection); Store(self.original);
    BOOL synced = Synchronize(), after = NO;
    if (!synced || ReadState(&after) || after != self.originalDirection || !Same(CopyStored(), self.original)) {
        self.failed = YES; fprintf(stderr,"FAIL: external-test restoration.\n");
    }
    [self performSelector:@selector(checkRestoredState) withObject:nil afterDelay:6.5];
}
- (void)checkRestoredState {
    if (self.stateError || self.displayedState != self.originalDirection) {
        self.failed = YES; fprintf(stderr,"FAIL: restored state did not sync.\n");
    } else printf("PASS: restored state synchronized without manual refresh.\n");
    [self checkMenu];
}
- (void)checkMenu {
    if (self.menuChecks && self.menuTask.running) {
        self.failed = YES;
        fprintf(stderr,"FAIL: menu process did not exit.\n");
        [self.menuTask terminate];
    }
    if (self.menuChecks++ < 3) {
        [self showMenu];
        [self performSelector:@selector(checkMenu) withObject:nil afterDelay:3];
    } else [self performSelector:@selector(finish) withObject:nil afterDelay:3];
}
- (void)finish {
    double footprint = Footprint();
    printf("After 100 toggles and 3 menu open/close cycles: %.3f MB physical footprint\n",footprint);
    if (footprint < 0 || footprint >= 10.0) {
        self.failed = YES; fprintf(stderr,"FAIL: 10 MB idle budget exceeded.\n");
    } else printf("PASS: below 10 MB (decimal).\n");
    fflush(stdout);
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--external-toggle") == 0) {
            LoadScrollFramework();
            NSString *error = ChangeDirection();
            if (error) fprintf(stderr,"FAIL: %s\n",error.UTF8String);
            return error ? 1 : 0;
        }
        if (argc > 1) {
            Method normal = class_getInstanceMethod([NSMenu class], @selector(popUpMenuPositioningItem:atLocation:inView:));
            Method check = class_getInstanceMethod([NSMenu class], @selector(verifyPopup:atLocation:inView:));
            method_exchangeImplementations(normal, check);
            return ProductMain(argc, argv);
        }
        NSApplication *app;
        VerifyApp *delegate;
        @autoreleasepool {
            app = [NSApplication sharedApplication];
            [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
            delegate = [[VerifyApp alloc] init];
            app.delegate = delegate;
        }
        [app run];
        return delegate.failed ? 1 : 0;
    }
}
