#import "LRControl.h"

@implementation LRControl

- (void)setTarget:(id)target {
    _lrTarget = target;
}

- (id)target {
    return _lrTarget;
}

- (void)setAction:(SEL)action {
    _lrAction = action;
}

- (SEL)action {
    return _lrAction;
}

- (BOOL)lr_fire:(SEL)action {
    if (!action) return NO;
    return [NSApp sendAction:action to:_lrTarget from:self];
}

- (BOOL)lr_fire {
    return [self lr_fire:_lrAction];
}

@end
