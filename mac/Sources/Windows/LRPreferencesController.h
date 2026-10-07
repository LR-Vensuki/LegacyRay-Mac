/* preferences the way system preferences and mail did them on 10.8: a
   toolbar of icons, one pane under it, the window resizing to the pane with
   an animation. every daemon setting is the daemon's (it keeps them in its
   config), the rest are this app's */
#import <Cocoa/Cocoa.h>

@interface LRPreferencesController : NSWindowController <NSToolbarDelegate, NSTableViewDataSource,
                                                         NSTableViewDelegate> {
    NSString *_pane;
    NSView *_current;
    NSArray *_rules;
    NSArray *_sites;
    NSTableView *_rulesTable;
    NSTableView *_sitesTable;
    NSString *_hwid;
    BOOL _refreshing;
    BOOL _busy;
}
- (void)selectPane:(NSString *)identifier;
@end
