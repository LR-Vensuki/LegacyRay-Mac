#import "LRServerCard.h"
#import "LRDraw.h"
#import "LRSound.h"

@implementation LRServerCard
@synthesize countryCode = _countryCode, title = _title, detail = _detail, value = _value,
            valueColor = _valueColor, swipeAction = _swipeAction, swipeDirection = _swipeDirection;

+ (CGFloat)height {
    return SKIN->flat ? 62 : 60;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (void)dealloc {
    [_countryCode release];
    [_title release];
    [_detail release];
    [_value release];
    [_valueColor release];
    [super dealloc];
}

#define LR_CARD_SETTER(name, ivar) \
- (void)name:(NSString *)v { if (v != ivar && ![v isEqual:ivar]) { [ivar release]; ivar = [v copy]; [self setNeedsDisplay:YES]; } }
LR_CARD_SETTER(setCountryCode, _countryCode)
LR_CARD_SETTER(setTitle, _title)
LR_CARD_SETTER(setDetail, _detail)
LR_CARD_SETTER(setValue, _value)

- (void)setValueColor:(NSColor *)v {
    if (v == _valueColor) return;
    [_valueColor release];
    _valueColor = [v retain];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    LRSkin *s = SKIN;
    NSRect b = [self bounds];
    BOOL pressed = _pressed;
    CGRect card = CGRectMake(1, 0, NSWidth(b) - 2, NSHeight(b) - 3);
    if (s->flat) {
        card = CGRectInset(NSRectToCGRect(b), 1, 1);
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -1), 3, [[NSColor colorWithCalibratedWhite:0 alpha:0.08f] CGColor]);
        LRAddRoundRect(ctx, card, 12);
        CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
        CGContextFillPath(ctx);
        CGContextRestoreGState(ctx);
        LRDrawGroupCell(ctx, card, LRPlateSingle, pressed, NO);
    } else {
        for (int i = 0; i < 3; ++i) {
            LRAddRoundRect(ctx, CGRectMake(card.origin.x - 0.5f + i * 0.2f, card.origin.y + 1.5f + i * 0.6f,
                                           card.size.width + 1 - i * 0.4f, card.size.height), 10);
            CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.14f);
            CGContextFillPath(ctx);
        }
        LRDrawGroupCell(ctx, card, LRPlateSingle, pressed, YES);
    }
    BOOL white = pressed && !s->flat;
    CGFloat midY = CGRectGetMidY(card);
    CGFloat x = card.origin.x + (s->flat ? 16 : 12);
    if ([_countryCode length] == 2) {
        LRDrawFlag(ctx, _countryCode, CGRectMake(x, round(midY - 13.5f), 27, 27));
        x += 38;
    } else {
        x += 2;
    }
    CGFloat right = CGRectGetMaxX(card) - 14;
    NSColor *chevron = white ? [NSColor whiteColor]
        : (s->flat ? [NSColor colorWithCalibratedWhite:0.78f alpha:1] : [NSColor colorWithCalibratedWhite:0.55f alpha:1]);
    LRDrawChevron(ctx, CGPointMake(right - 2, midY), 4.5f, NO, chevron, s->flat ? 2 : 2.4f);
    right -= 18;
    NSFont *valueFont = [LRSkin bodyFont:13];
    CGFloat valueW = 0;
    if ([_value length]) {
        valueW = MIN(LRTextSize(_value, valueFont).width, (right - x) * 0.4f);
        LRDrawText(_value, NSMakeRect(right - valueW, midY - 9, valueW, 18), valueFont,
                   white ? [NSColor whiteColor] : (_valueColor ? _valueColor : s->groupDetail), NSRightTextAlignment);
        valueW += 10;
    }
    CGFloat textW = right - valueW - x;
    NSFont *titleFont = s->flat ? [LRSkin bodyFont:15] : [LRSkin boldFont:15];
    NSFont *detailFont = [LRSkin bodyFont:11];
    BOOL twoLines = [_detail length] > 0;
    CGFloat titleY = twoLines ? midY - 19 : midY - 10;
    LRDrawText(_title, NSMakeRect(x, titleY, textW, 20), titleFont, white ? [NSColor whiteColor] : s->groupInk,
               NSLeftTextAlignment);
    if (twoLines)
        LRDrawText(_detail, NSMakeRect(x, midY + 2, textW, 16), detailFont,
                   white ? [NSColor whiteColor] : s->groupMuted, NSLeftTextAlignment);
}

- (void)setPressed:(BOOL)p {
    if (p == _pressed) return;
    _pressed = p;
    if (p) [LRSound click];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    if (![self isEnabled]) return;
    [self setPressed:YES];
    BOOL inside = YES;
    for (;;) {
        NSEvent *e = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask];
        inside = NSPointInRect([self convertPoint:[e locationInWindow] fromView:nil], [self bounds]);
        if ([e type] == NSLeftMouseUp) break;
        [self setPressed:inside];
    }
    [self setPressed:NO];
    if (inside) [self sendAction:[self action] to:[self target]];
}

- (void)step:(NSInteger)direction {
    if (!_swipeAction) return;
    _swipeDirection = direction;
    [self sendAction:_swipeAction to:[self target]];
}

/* a trackpad swipe (three fingers, or two where the system says so) */
- (void)swipeWithEvent:(NSEvent *)event {
    if ([event deltaX] != 0) [self step:[event deltaX] < 0 ? 1 : -1];
}

- (BOOL)acceptsFirstResponder {
    return NO;
}
@end
