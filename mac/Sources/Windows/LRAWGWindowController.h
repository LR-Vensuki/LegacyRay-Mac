/* amneziawg and wireguard profiles, the way the amnezia client keeps them: a
   list on the left, the chosen one on the right with its endpoint, routes
   and state, a handshake check, sharing, and the obfuscation keys (Jc, Jmin,
   Jmax, S1-S4, H1-H4) editable one by one */
#import <Cocoa/Cocoa.h>

@class LRAWGProfile;

@interface LRAWGWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate> {
    NSTableView *_list;
    NSView *_detailHolder;
    NSArray *_profiles;
    LRAWGProfile *_selected;
    NSString *_check;
    BOOL _checking;
}
- (void)selectProfile:(LRAWGProfile *)profile;
@end
