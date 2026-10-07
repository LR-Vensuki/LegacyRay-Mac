/* the main window: the denim bar across the top, the server list on the
   left, the dashboard with the big button on the right. on 10.8 / 10.9 the
   classic finish carries the denim up into the title bar (the leather of
   calendar); on yosemite the content runs under a transparent title bar */
#import <Cocoa/Cocoa.h>
#import "LRSidebar.h"
#import "LRToast.h"

@class LRHeaderBar, LRDashboardView, LRTitlebarOverlay, LRBarKey;

@interface LRMainWindowController : NSWindowController <NSWindowDelegate, NSSplitViewDelegate,
                                                        LRSidebarOwner> {
    LRHeaderBar *_header;
    LRTitlebarOverlay *_overlay;
    NSSplitView *_split;
    LRSidebar *_sidebar;
    LRDashboardView *_dashboard;
    LRBarKey *_checkKey;
    NSString *_shownError;
    BOOL _yosemiteChrome;
}
@property (nonatomic, readonly) LRSidebar *sidebar;
@property (nonatomic, readonly) LRDashboardView *dashboard;
- (id)initMainWindow;
- (void)refresh;
/* the importer's menu, anchored to a key or a button */
- (NSMenu *)importMenu;
@end
