#import <AppKit/AppKit.h>
static id FakeStored;
static BOOL FakeManaged, SyncOK = YES, IgnoreSetter, ExternalChange;
static uint64_t FakeDirection;
static int SetCalls, SyncCalls, FailSyncAt;
static Boolean TestSync(CFStringRef domain, CFStringRef user, CFStringRef host) {
    (void)domain; (void)user; (void)host;
    SyncCalls++;
    return SyncOK && SyncCalls != FailSyncAt;
}
static CFPropertyListRef TestCopy(CFStringRef key, CFStringRef domain, CFStringRef user, CFStringRef host) {
    (void)key; (void)domain; (void)user; (void)host;
    return FakeStored ? CFRetain((__bridge CFTypeRef)FakeStored) : NULL;
}
static void TestStore(CFStringRef key, CFPropertyListRef value, CFStringRef domain, CFStringRef user, CFStringRef host) {
    (void)key; (void)domain; (void)user; (void)host;
    FakeStored = (__bridge id)value;
}
static Boolean TestManaged(CFStringRef key, CFStringRef domain) {
    (void)key; (void)domain;
    return FakeManaged;
}
#define CFPreferencesSynchronize TestSync
#define CFPreferencesCopyValue TestCopy
#define CFPreferencesSetValue TestStore
#define CFPreferencesAppValueIsForced TestManaged
#define SCROLL_TESTING
#include "main.m"
#include <assert.h>
static uint64_t TestGet(void) { return FakeDirection; }
static void TestSet(uint64_t value) {
    SetCalls++;
    if (!IgnoreSetter) FakeDirection = value;
    if (ExternalChange) FakeStored = @"external";
}
static void Reset(id stored, BOOL direction) {
    FakeStored = stored; FakeDirection = direction;
    FakeManaged = IgnoreSetter = ExternalChange = NO;
    SetCalls = SyncCalls = FailSyncAt = 0;
    SyncOK = YES; GetDirection = TestGet; SetDirection = TestSet;
}
int main(void) {
    @autoreleasepool {
        Reset(@YES, YES);
        assert(ChangeDirection() == nil && FakeDirection == 0 && Same(FakeStored, @NO));
        assert(ChangeDirection() == nil && FakeDirection == 1 && Same(FakeStored, @YES));
        Reset(@YES, YES); FakeManaged = YES;
        assert(ChangeDirection() && SetCalls == 0 && Same(FakeStored, @YES));
        Reset(@YES, YES); SetDirection = NULL;
        assert(ChangeDirection() && SetCalls == 0 && Same(FakeStored, @YES));
        Reset(@"bad type", YES);
        assert(ChangeDirection() && SetCalls == 0 && Same(FakeStored, @"bad type"));
        Reset(@YES, YES); FakeDirection = 2;
        assert(ChangeDirection() && SetCalls == 0);
        Reset(@YES, YES); SyncOK = NO;
        assert(ChangeDirection() && SetCalls == 0 && Same(FakeStored, @YES));
        Reset(@YES, YES); FailSyncAt = 2;
        assert(ChangeDirection() && Same(FakeStored, @YES) && FakeDirection == 1);
        Reset(@YES, YES); IgnoreSetter = YES;
        assert(ChangeDirection() && Same(FakeStored, @YES) && FakeDirection == 1);
        Reset(nil, YES); IgnoreSetter = YES;
        assert(ChangeDirection() && FakeStored == nil && FakeDirection == 1);
        Reset(@YES, YES); ExternalChange = YES;
        assert(ChangeDirection() && SetCalls == 1 && Same(FakeStored, @"external"));
        Reset(@YES, YES);
        for (int i=0;i<100;i++) assert(ChangeDirection() == nil);
        assert(Same(FakeStored, @YES) && FakeDirection == 1);
        printf("PASS: toggles, managed/missing API/invalid state, sync failure, rollback, absent value, concurrent change, 100 toggles.\n");
        ScrollApp *app = [[ScrollApp alloc] init];
        [app refresh:nil];
        assert([app.hoverHelp isEqualToString:@"ScrollToggle\nNatural scrolling: On\nClick to turn off · Right-click for options"]);
        FakeDirection = 0; FakeStored = @NO;
        [app refresh:nil];
        assert([app.hoverHelp containsString:@"Natural scrolling: Off\nClick to turn on"]);
        FakeManaged = YES;
        [app refresh:nil]; // Managed state can change without changing direction.
        assert([app.hoverHelp containsString:@"Managed by your administrator"]);
        assert(![app.hoverHelp containsString:@"Click to turn"]);
        SetDirection = NULL;
        [app refresh:nil];
        assert([app.hoverHelp isEqualToString:@"ScrollToggle\nNatural scrolling: Unavailable\nRight-click for options"]);
        printf("PASS: hover status and actions for on, off, managed, and unavailable states.\n");
    }
}
