#import "LRBarKey.h"
#import "LRDraw.h"
#import "LRSound.h"

@implementation LRBarKey
@synthesize title = _title, glyph = _glyph, dropMenu = _dropMenu, handler = _handler;

+ (NSColor *)glyphInk {
    return SKIN->flat ? SKIN->tint : [NSColor whiteColor];
}

+ (LRBarKey *)keyWithTitle:(NSString *)title handler:(void (^)(LRBarKey *))handler {
    LRBarKey *k = [[[LRBarKey alloc] initWithFrame:NSMakeRect(0, 0, 60, 26)] autorelease];
    k.title = title;
    k.handler = handler;
    return k;
}

+ (LRBarKey *)keyWithGlyph:(NSImage *)glyph handler:(void (^)(LRBarKey *))handler {
    LRBarKey *k = [[[LRBarKey alloc] initWithFrame:NSMakeRect(0, 0, 34, 26)] autorelease];
    k.glyph = glyph;
    k.handler = handler;
    return k;
}

- (void)dealloc {
    [_title release];
    [_glyph release];
    [_dropMenu release];
    [_handler release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (NSFont *)font {
    return SKIN->flat ? [LRSkin bodyFont:13] : [LRSkin boldFont:12];
}

- (CGFloat)preferredWidth {
    if (_glyph) return SKIN->flat ? 30 : 36;
    return MAX(SKIN->flat ? 30.0f : 50.0f, LRTextSize(_title, [self font]).width + (SKIN->flat ? 12 : 22));
}

- (void)setTitle:(NSString *)t {
    if (t == _title) return;
    [_title release];
    _title = [t copy];
    [self setNeedsDisplay:YES];
}

- (void)setGlyph:(NSImage *)g {
    if (g == _glyph) return;
    [_glyph release];
    _glyph = [g retain];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSRect b = [self bounds];
    BOOL flat = SKIN->flat;
    BOOL enabled = [self isEnabled];
    LRDrawBarKey(ctx, NSRectToCGRect(NSInsetRect(b, 0, 0)), _pressed, enabled);
    CGFloat alpha = enabled ? (flat && _pressed ? 0.45f : 1) : 0.4f;
    if (_glyph) {
        NSSize g = [_glyph size];
        NSRect r = NSMakeRect(round(NSMidX(b) - g.width / 2), round(NSMidY(b) - g.height / 2), g.width, g.height);
        if (!flat)
            [_glyph drawInRect:NSOffsetRect(r, 0, -1) fromRect:NSZeroRect operation:NSCompositeSourceOver
                      fraction:0.35f * alpha respectFlipped:YES hints:nil];
        [_glyph drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:alpha
            respectFlipped:YES hints:nil];
        return;
    }
    NSFont *font = [self font];
    NSRect tr = NSMakeRect(4, round(NSMidY(b) - LRTextSize(@"Ag", font).height / 2), NSWidth(b) - 8, 18);
    NSColor *ink = flat ? LRColorAlpha(SKIN->tint, alpha) : [NSColor colorWithCalibratedWhite:1 alpha:alpha];
    if (flat) LRDrawText(_title, tr, font, ink, NSCenterTextAlignment);
    else LRDrawEngraved(_title, tr, font, NSCenterTextAlignment, ink,
                        [NSColor colorWithCalibratedWhite:0 alpha:0.6f * alpha], -1);
}

- (void)setPressed:(BOOL)p {
    if (p == _pressed) return;
    _pressed = p;
    if (p) [LRSound click];
    [self setNeedsDisplay:YES];
}

- (void)fire {
    if (_handler) _handler(self);
    else [self lr_fire];
}

- (void)mouseDown:(NSEvent *)event {
    if (![self isEnabled]) return;
    if (_dropMenu) {
        [self setPressed:YES];
        if (_handler) _handler(self);
        NSPoint at = NSMakePoint(0, NSHeight([self bounds]) + 4);
        [_dropMenu popUpMenuPositioningItem:nil atLocation:at inView:self];
        [self setPressed:NO];
        return;
    }
    [self setPressed:YES];
    BOOL inside = YES;
    for (;;) {
        NSEvent *e = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask];
        inside = NSPointInRect([self convertPoint:[e locationInWindow] fromView:nil], [self bounds]);
        if ([e type] == NSLeftMouseUp) break;
        [self setPressed:inside];
    }
    [self setPressed:NO];
    if (inside) [self fire];
}

- (BOOL)acceptsFirstResponder {
    return NO;
}
@end
