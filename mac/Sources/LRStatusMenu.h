/* the menu bar item: the icon's stitched tile in miniature, hollow while
   off, breathing while a tunnel comes up, solid while it is up; its menu
   connects, switches servers (grouped like the window's list, with flags and
   latency) and opens the window. it stays while the window is closed */
#import <Cocoa/Cocoa.h>

@interface LRStatusMenu : NSObject <NSMenuDelegate> {
    NSStatusItem *_item;
    NSMenu *_menu;
    NSTimer *_blink;
    BOOL _blinkOn;
}
- (void)rebuild;
@end
