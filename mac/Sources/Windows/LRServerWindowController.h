/* the details of one server or one subscription, in a small window of its
   own: a denim plate across the top with the flag, the name and what it
   speaks (white on yosemite), the facts under it the way a get info window
   lists them, latency checks, and the actions in a row of buttons */
#import <Cocoa/Cocoa.h>

@class LRServer, LRSubscription;

@interface LRInfoHeader : NSView {
    NSString *_title, *_subtitle, *_country;
    NSImage *_icon;
}
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *country;
@property (nonatomic, retain) NSImage *icon;
@end

@interface LRServerWindowController : NSWindowController {
    LRServer *_server;
    LRSubscription *_subscription;
    NSMutableDictionary *_results;
    NSMutableSet *_running;
    NSArray *_stages;
    NSString *_hwid;
    BOOL _updating;
}
- (id)initWithServer:(LRServer *)server;
- (id)initWithSubscription:(LRSubscription *)subscription;
@end

/* the frame every small window here is built in: the header, a body and a
   bar of buttons, laid out top down; returns the window's content view */
NSView *LRBuildInfoContent(NSWindow *window, LRInfoHeader *header, NSView *body, NSArray *buttons);
