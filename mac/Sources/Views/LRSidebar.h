/* the servers, the way mail lists mailboxes on 10.8: a source list with a
   group per subscription (its traffic and days left under the name), the
   manual servers and the amneziawg profiles, flags and latency badges in the
   rows. a click picks the server the power button connects (and switches a
   running tunnel over), a double click or return connects, the context menu
   has the rest. a gradient button bar under it adds, removes and acts */
#import <Cocoa/Cocoa.h>

@class LRServer, LRSection, LRSubscription, LRAWGProfile;

@protocol LRSidebarOwner <NSObject>
- (void)showImportMenuFrom:(NSView *)view;
- (void)openServer:(LRServer *)server;
- (void)openSubscription:(LRSubscription *)subscription;
- (void)openAWGProfile:(LRAWGProfile *)profile;
- (void)shareServer:(LRServer *)server;
- (void)openAWGProfiles;
- (void)startDaemon;
@end

@interface LRSidebarTable : NSTableView
@end

@interface LRSidebar : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate> {
    id<LRSidebarOwner> _owner;        /* not retained */
    NSView *_view;
    NSScrollView *_scroll;
    LRSidebarTable *_table;
    NSView *_bottomBar;
    NSView *_empty;
    NSTextField *_emptyTitle;
    NSTextField *_emptyText;
    NSButton *_emptyPrimary;
    NSButton *_emptySecondary;
    NSButton *_removeButton;
    NSButton *_actionButton;
    NSMutableArray *_rows;
    BOOL _rebuilding;
    BOOL _offline;
}
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, readonly) NSTableView *table;
- (id)initWithOwner:(id<LRSidebarOwner>)owner;
- (void)rebuild;
/* latency or tunnel changes: redraw the rows, keep the structure */
- (void)refreshRows;
- (void)setDaemonOffline:(BOOL)offline;
/* the menus the window's own menu bar and the bar keys share */
- (NSMenu *)listMenu;
- (void)connectFastestOf:(NSArray *)servers;
- (void)selectCurrent;
@end
