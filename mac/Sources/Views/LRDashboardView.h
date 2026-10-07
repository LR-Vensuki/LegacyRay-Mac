/* the right pane: the denim page (a shade darker than the bars, lit in the
   middle) or the white yosemite page, with the power button, what the tunnel
   is doing under it and the server card. the window controller feeds it */
#import <Cocoa/Cocoa.h>
#import "LRPowerButton.h"
#import "LRServerCard.h"

@interface LRDashboardView : NSView {
    LRPowerButton *_power;
    LRServerCard *_card;
    NSString *_status;
    NSString *_detail;
    NSString *_footnote;
    CGFloat _topInset;
}
@property (nonatomic, readonly) LRPowerButton *power;
@property (nonatomic, readonly) LRServerCard *card;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *detail;
/* one quiet line at the bottom: the network and the local proxy */
@property (nonatomic, copy) NSString *footnote;
/* the part of the pane a bar covers (yosemite runs content under it) */
@property (nonatomic, assign) CGFloat topInset;
@end
