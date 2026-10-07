/* the base of the drawn controls (the power button, the server card, the bar
   keys). NSControl keeps target and action in its cell, and a control that
   draws itself has none: on 10.8 setTarget: and setAction: fall through to
   nil and a click goes nowhere. these keep both in the control itself */
#import <Cocoa/Cocoa.h>

@interface LRControl : NSControl {
    id _lrTarget;
    SEL _lrAction;
}
/* sends the action to the target, or up the responder chain without one */
- (BOOL)lr_fire;
- (BOOL)lr_fire:(SEL)action;
@end
