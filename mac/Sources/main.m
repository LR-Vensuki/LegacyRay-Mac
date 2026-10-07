/* LegacyRay for os x: no nib, the delegate builds the menus and windows */
#import <Cocoa/Cocoa.h>
#import "LRAppDelegate.h"

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *app = [NSApplication sharedApplication];
    LRAppDelegate *delegate = [[LRAppDelegate alloc] init];
    [app setDelegate:delegate];
    [app run];
    [delegate release];
    [pool drain];
    return 0;
}
