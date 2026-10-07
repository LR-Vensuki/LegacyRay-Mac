/* the one big button: a pearl cap of matte cloth in a stitched well on the
   denim, the power glyph pressed into it and lit from behind by the state;
   a white disc in a thin ring on yosemite. the glyph (or the ring) breathes
   while a tunnel is coming up, the only animation on the dashboard */
#import "LRControl.h"

typedef enum {
    LRPowerOff = 0,
    LRPowerTuning,
    LRPowerOn,
    LRPowerFault
} LRPowerState;

@interface LRPowerButton : LRControl {
    LRPowerState _powerState;
    BOOL _pressed;
    BOOL _tracking;
    CALayer *_cap;
    CALayer *_glyph;
    CAShapeLayer *_ring;
    CGFloat _builtFor;
    CGFloat _builtScale;
}
@property (nonatomic, assign) LRPowerState powerState;
+ (CGFloat)sideForRadius:(CGFloat)radius;
- (CGFloat)radius;
@end
