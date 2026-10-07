#import "LRPowerButton.h"
#import "LRDraw.h"
#import "LRSound.h"

/* between the cap and the frame: the well (9) and the stitched ring (17) */
#define LR_POWER_MARGIN 19.0f

/* a flipped bitmap at the backing scale, for a layer's contents */
static CGImageRef LRRender(CGSize size, CGFloat scale, void (^draw)(CGContextRef ctx, CGRect rect)) CF_RETURNS_RETAINED;
static CGImageRef LRRender(CGSize size, CGFloat scale, void (^draw)(CGContextRef ctx, CGRect rect)) {
    size_t w = (size_t)ceil(size.width * scale), h = (size_t)ceil(size.height * scale);
    if (!w || !h) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(space);
    if (!ctx) return NULL;
    CGContextTranslateCTM(ctx, 0, h);
    CGContextScaleCTM(ctx, scale, -scale);
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithGraphicsPort:ctx flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];
    draw(ctx, CGRectMake(0, 0, size.width, size.height));
    [NSGraphicsContext restoreGraphicsState];
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}

static NSColor *LRPowerColor(LRPowerState s) {
    switch (s) {
        case LRPowerOn: return SKIN->ledGreen;
        case LRPowerTuning: return SKIN->ledAmber;
        case LRPowerFault: return SKIN->ledRed;
        case LRPowerOff: break;
    }
    return SKIN->flat ? [NSColor colorWithCalibratedWhite:0.55f alpha:1]
                      : [NSColor colorWithCalibratedRed:0.635f green:0.647f blue:0.663f alpha:1];
}

static void LRAddPowerGlyph(CGContextRef ctx, CGPoint c, CGFloat gr) {
    CGContextAddArc(ctx, c.x, c.y, gr, (CGFloat)-M_PI_2 + 0.72f, (CGFloat)-M_PI_2 - 0.72f + (CGFloat)M_PI * 2, 0);
    CGContextMoveToPoint(ctx, c.x, c.y - gr * 1.22f);
    CGContextAddLineToPoint(ctx, c.x, c.y - gr * 0.28f);
}

static void LRStroke(CGContextRef ctx, NSColor *c) {
    NSColor *rgb = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    CGContextSetRGBStrokeColor(ctx, [rgb redComponent], [rgb greenComponent], [rgb blueComponent], [rgb alphaComponent]);
}

static void LRFill(CGContextRef ctx, NSColor *c) {
    NSColor *rgb = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    CGContextSetRGBFillColor(ctx, [rgb redComponent], [rgb greenComponent], [rgb blueComponent], [rgb alphaComponent]);
}

@implementation LRPowerButton
@synthesize powerState = _powerState;

+ (CGFloat)sideForRadius:(CGFloat)radius {
    return SKIN->flat ? radius * 2 + 24 : radius * 2 + LR_POWER_MARGIN * 2;
}

- (id)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setWantsLayer:YES];
        [self setLayerContentsRedrawPolicy:NSViewLayerContentsRedrawOnSetNeedsDisplay];
        _ring = [[CAShapeLayer layer] retain];
        _ring.fillColor = NULL;
        _ring.lineWidth = 3;
        _cap = [[CALayer layer] retain];
        _glyph = [[CALayer layer] retain];
    }
    return self;
}

- (void)dealloc {
    [_ring release];
    [_cap release];
    [_glyph release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (CGFloat)radius {
    NSRect b = [self bounds];
    CGFloat side = MIN(NSWidth(b), NSHeight(b));
    return SKIN->flat ? side / 2 - 12 : side / 2 - LR_POWER_MARGIN;
}

- (CGPoint)center {
    NSRect b = [self bounds];
    return CGPointMake(NSMidX(b), NSMidY(b));
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    _builtFor = 0;
    [self rebuildLayers];
}

- (void)viewDidChangeBackingProperties {
    _builtFor = 0;
    [self rebuildLayers];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self rebuildLayers];
}

- (void)rebuildLayers {
    CALayer *host = [self layer];
    if (!host) return;
    CGFloat R = [self radius];
    CGFloat scale = LRBackingScale(self);
    if (R < 10) return;
    if (R == _builtFor && scale == _builtScale && [_cap superlayer] == host) {
        [self applyState];
        return;
    }
    _builtFor = R;
    _builtScale = scale;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_ring removeFromSuperlayer];
    [_cap removeFromSuperlayer];
    [_glyph removeFromSuperlayer];
    if (SKIN->flat) {
        [host addSublayer:_ring];
        [host addSublayer:_cap];
    } else {
        [host addSublayer:_cap];
        [host addSublayer:_glyph];
    }
    [CATransaction commit];
    [self applyState];
    [self setNeedsDisplay:YES];
}

/* layer geometry runs bottom up in a layer-backed view whatever the view
   says; this turns a flipped rect into the host layer's */
- (CGRect)layerRect:(CGRect)r {
    if ([[self layer] isGeometryFlipped]) return r;
    return CGRectMake(r.origin.x, NSHeight([self bounds]) - CGRectGetMaxY(r), r.size.width, r.size.height);
}

#pragma mark classic

- (CGImageRef)capImage:(CGFloat)R pressed:(BOOL)pressed CF_RETURNS_RETAINED {
    return LRRender(CGSizeMake(R * 2, R * 2), _builtScale, ^(CGContextRef ctx, CGRect rect) {
        CGPoint c = CGPointMake(R, R);
        CGContextSaveGState(ctx);
        CGContextAddEllipseInRect(ctx, rect);
        CGContextClip(ctx);
        if (pressed)
            LRFillVertical(ctx, rect, [NSColor colorWithCalibratedRed:0.894f green:0.894f blue:0.886f alpha:1],
                           [NSColor colorWithCalibratedRed:0.769f green:0.773f blue:0.761f alpha:1]);
        else
            LRFillVertical(ctx, rect, [NSColor colorWithCalibratedRed:0.984f green:0.984f blue:0.980f alpha:1],
                           [NSColor colorWithCalibratedRed:0.831f green:0.835f blue:0.824f alpha:1]);
        NSImage *tile = LRDenimTile();
        if (tile) {
            /* the icon's twill, just visible through the white */
            CGContextSaveGState(ctx);
            CGContextSetBlendMode(ctx, kCGBlendModeMultiply);
            CGContextSetAlpha(ctx, 0.035f);
            [[NSColor colorWithPatternImage:tile] setFill];
            NSRectFillUsingOperation(NSRectFromCGRect(rect), NSCompositeSourceOver);
            CGContextRestoreGState(ctx);
        }
        LRFillRadial(ctx, CGPointMake(c.x - R * 0.25f, c.y - R * 0.55f), 0, R * 1.2f,
                     [NSColor colorWithCalibratedWhite:1 alpha:pressed ? 0.3f : 0.55f],
                     [NSColor colorWithCalibratedWhite:1 alpha:0]);
        CGContextRestoreGState(ctx);
        CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.55f);
        CGContextSetLineWidth(ctx, 1);
        CGContextStrokeEllipseInRect(ctx, CGRectInset(rect, 0.5f, 0.5f));
        CGContextSetRGBStrokeColor(ctx, 1, 1, 1, pressed ? 0.5f : 0.9f);
        CGContextAddArc(ctx, c.x, c.y, R - 1.5f, (CGFloat)M_PI * 1.1f, (CGFloat)M_PI * 1.9f, 0);
        CGContextStrokePath(ctx);
    });
}

- (CGFloat)glyphSide:(CGFloat)R {
    CGFloat gr = R * 0.34f, lw = MAX(2.0f, R * 0.085f);
    return ceil(gr * 2.6f + lw + 14);
}

- (CGImageRef)glyphImage:(CGFloat)R state:(LRPowerState)state CF_RETURNS_RETAINED {
    CGFloat gr = R * 0.34f, lw = MAX(2.0f, R * 0.085f);
    CGFloat side = [self glyphSide:R];
    NSColor *ink = LRPowerColor(state);
    BOOL lit = state != LRPowerOff;
    return LRRender(CGSizeMake(side, side), _builtScale, ^(CGContextRef ctx, CGRect rect) {
        CGPoint c = CGPointMake(side / 2, side / 2 + gr * 0.1f);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineWidth(ctx, lw);
        /* the light catches the lower edge of the groove */
        LRAddPowerGlyph(ctx, CGPointMake(c.x, c.y + 1), gr);
        CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.95f);
        CGContextStrokePath(ctx);
        LRAddPowerGlyph(ctx, CGPointMake(c.x, c.y - 0.6f), gr);
        CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.18f);
        CGContextStrokePath(ctx);
        CGContextSaveGState(ctx);
        if (lit) CGContextSetShadowWithColor(ctx, CGSizeZero, 5, [LRColorAlpha(ink, 0.6f) CGColor]);
        LRAddPowerGlyph(ctx, c, gr);
        LRStroke(ctx, ink);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    });
}

#pragma mark flat

- (CGImageRef)flatCapImage:(CGFloat)R pressed:(BOOL)pressed color:(NSColor *)color CF_RETURNS_RETAINED {
    CGFloat rc = R - 7;
    BOOL filled = _powerState == LRPowerOn;
    LRPowerState state = _powerState;
    return LRRender(CGSizeMake(rc * 2 + 2, rc * 2 + 2), _builtScale, ^(CGContextRef ctx, CGRect rect) {
        CGPoint c = CGPointMake(rc + 1, rc + 1);
        CGRect disc = CGRectMake(1, 1, rc * 2, rc * 2);
        NSColor *fill = filled ? color : [NSColor whiteColor];
        if (pressed) fill = LRColorMix(fill, [NSColor blackColor], 0.08f);
        if (!filled) {
            /* the faint shadow a white disc needs on a white page */
            CGContextSaveGState(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 3,
                                        [[NSColor colorWithCalibratedWhite:0 alpha:0.12f] CGColor]);
            LRFill(ctx, fill);
            CGContextFillEllipseInRect(ctx, CGRectInset(disc, 1, 1));
            CGContextRestoreGState(ctx);
        }
        LRFill(ctx, fill);
        CGContextFillEllipseInRect(ctx, CGRectInset(disc, filled ? 0 : 1, filled ? 0 : 1));
        NSColor *ink = filled ? [NSColor whiteColor]
            : (state == LRPowerOff ? [NSColor colorWithCalibratedWhite:0.55f alpha:1] : color);
        LRStroke(ctx, ink);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineWidth(ctx, MAX(2.0f, rc * 0.07f));
        LRAddPowerGlyph(ctx, c, rc * 0.36f);
        CGContextStrokePath(ctx);
    });
}

#pragma mark state

- (void)applyState {
    CGFloat R = [self radius];
    if (R < 10 || !_builtScale) return;
    NSColor *color = LRPowerColor(_powerState);
    CGPoint c = [self center];
    BOOL pressed = _pressed;
    CALayer *pulsing;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (SKIN->flat) {
        CGFloat rc = R - 7;
        CGImageRef cap = [self flatCapImage:R pressed:pressed color:color];
        _cap.contents = (id)cap;
        CGImageRelease(cap);
        _cap.contentsScale = _builtScale;
        _cap.frame = [self layerRect:CGRectMake(c.x - rc - 1, c.y - rc - 1, rc * 2 + 2, rc * 2 + 2)];
        CGFloat ringR = R - 1.5f;
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathAddEllipseInRect(p, NULL, CGRectMake(-ringR, -ringR, ringR * 2, ringR * 2));
        _ring.path = p;
        CGPathRelease(p);
        CGRect rr = [self layerRect:CGRectMake(c.x, c.y, 0, 0)];
        _ring.frame = CGRectMake(rr.origin.x, rr.origin.y, 0, 0);
        _ring.strokeColor = [(_powerState != LRPowerOff ? color : [NSColor colorWithCalibratedWhite:0.82f alpha:1]) CGColor];
        pulsing = _ring;
    } else {
        CGFloat dy = pressed ? 1 : 0;
        CGImageRef cap = [self capImage:R pressed:pressed];
        _cap.contents = (id)cap;
        CGImageRelease(cap);
        _cap.contentsScale = _builtScale;
        _cap.frame = [self layerRect:CGRectMake(c.x - R, c.y - R + dy, R * 2, R * 2)];
        CGFloat side = [self glyphSide:R];
        CGImageRef g = [self glyphImage:R state:_powerState];
        _glyph.contents = (id)g;
        CGImageRelease(g);
        _glyph.contentsScale = _builtScale;
        _glyph.frame = [self layerRect:CGRectMake(round(c.x - side / 2), round(c.y - side / 2) + dy, side, side)];
        pulsing = _glyph;
    }
    [CATransaction commit];
    [pulsing removeAnimationForKey:@"pulse"];
    if (_powerState == LRPowerTuning) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
        a.fromValue = [NSNumber numberWithFloat:1];
        a.toValue = [NSNumber numberWithFloat:0.35f];
        a.duration = 0.8;
        a.autoreverses = YES;
        a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [pulsing addAnimation:a forKey:@"pulse"];
    }
}

- (void)setPowerState:(LRPowerState)s {
    if (s == _powerState) return;
    _powerState = s;
    [self applyState];
}

/* the stitched ring, the well and the cap's shadow in it */
- (void)drawRect:(NSRect)dirty {
    if (SKIN->flat) return;
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGFloat R = [self radius];
    CGPoint c = [self center];
    LRDrawStitchCircle(ctx, c, R + 17);
    CGFloat well = R + 9;
    CGRect wellRect = CGRectMake(c.x - well, c.y - well, well * 2, well * 2);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.42f);
    CGContextFillEllipseInRect(ctx, wellRect);
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, wellRect);
    CGContextClip(ctx);
    LRFillVertical(ctx, CGRectMake(wellRect.origin.x, wellRect.origin.y, wellRect.size.width, 14),
                   [NSColor colorWithCalibratedWhite:0 alpha:0.5f], [NSColor colorWithCalibratedWhite:0 alpha:0]);
    CGContextRestoreGState(ctx);
    CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.10f);
    CGContextSetLineWidth(ctx, 1);
    CGContextAddArc(ctx, c.x, c.y + 0.5f, well, (CGFloat)M_PI * 0.15f, (CGFloat)M_PI * 0.85f, 0);
    CGContextStrokePath(ctx);
    for (int i = 0; i < 7; ++i) {
        CGFloat r = R + 3.5f - i * 0.6f;
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.08f);
        CGContextFillEllipseInRect(ctx, CGRectMake(c.x - r, c.y + 3 - r, r * 2, r * 2));
    }
}

#pragma mark mouse

- (BOOL)hit:(NSPoint)p {
    CGPoint c = [self center];
    CGFloat dx = p.x - c.x, dy = p.y - c.y;
    CGFloat r = [self radius] + 10;
    return dx * dx + dy * dy <= r * r;
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *v = [super hitTest:point];
    if (v != self) return v;
    return [self hit:[self convertPoint:point fromView:[self superview]]] ? self : nil;
}

- (void)setPressed:(BOOL)pressed {
    if (pressed == _pressed) return;
    _pressed = pressed;
    if (pressed) [LRSound clunk];
    [self applyState];
}

- (void)mouseDown:(NSEvent *)event {
    if (![self isEnabled]) return;
    [self setPressed:YES];
    BOOL inside = YES;
    for (;;) {
        NSEvent *e = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask];
        NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
        inside = [self hit:p];
        if ([e type] == NSLeftMouseUp) break;
        [self setPressed:inside];
    }
    [self setPressed:NO];
    if (inside) [self sendAction:[self action] to:[self target]];
}

- (BOOL)acceptsFirstResponder {
    return NO;
}
@end
