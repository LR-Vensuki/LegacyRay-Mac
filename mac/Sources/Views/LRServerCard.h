/* the station on the dashboard: a white plate on the denim (a card with a
   hairline on yosemite) with the flag, the name, the protocol and the
   latency; clicking it opens the server, the arrow keys and a two finger
   swipe step to the next one */
#import "LRControl.h"

@interface LRServerCard : LRControl {
    NSString *_countryCode;
    NSString *_title;
    NSString *_detail;
    NSString *_value;
    NSColor *_valueColor;
    BOOL _pressed;
    SEL _swipeAction;
    NSInteger _swipeDirection;
}
@property (nonatomic, copy) NSString *countryCode;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, retain) NSColor *valueColor;
/* sent with swipeDirection 1 (next) or -1 (previous) */
@property (nonatomic, assign) SEL swipeAction;
@property (nonatomic, readonly) NSInteger swipeDirection;
+ (CGFloat)height;
@end
