#import "LRDashboardView.h"
#import "LRDraw.h"

typedef struct {
    CGFloat radius, side, centerY, statusY, cardY, cardW;
} LRDashGeometry;

@implementation LRDashboardView
@synthesize power = _power, card = _card, status = _status, detail = _detail, footnote = _footnote,
            topInset = _topInset;

- (id)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _power = [[LRPowerButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        [self addSubview:_power];
        _card = [[LRServerCard alloc] initWithFrame:NSMakeRect(0, 0, 360, [LRServerCard height])];
        [self addSubview:_card];
    }
    return self;
}

- (void)dealloc {
    [_power release];
    [_card release];
    [_status release];
    [_detail release];
    [_footnote release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

- (LRDashGeometry)geometry {
    LRDashGeometry g;
    NSRect b = [self bounds];
    CGFloat W = NSWidth(b), H = NSHeight(b) - _topInset;
    CGFloat cardH = [LRServerCard height];
    g.radius = MIN(100.0f, MAX(66.0f, MIN(W, H) * 0.17f));
    g.side = [LRPowerButton sideForRadius:g.radius];
    g.centerY = _topInset + MAX(g.side / 2 + 26, H * 0.37f);
    g.statusY = g.centerY + g.side / 2 + 16;
    g.cardW = MIN(W - 60, 400);
    g.cardY = MIN(g.statusY + 86, _topInset + H - cardH - 34);
    g.cardY = MAX(g.cardY, g.statusY + 52);
    return g;
}

- (void)layoutPane {
    NSRect b = [self bounds];
    CGFloat W = NSWidth(b);
    if (W < 10) return;
    LRDashGeometry g = [self geometry];
    [_power setFrame:NSMakeRect(round((W - g.side) / 2), round(g.centerY - g.side / 2), g.side, g.side)];
    [_card setFrame:NSMakeRect(round((W - g.cardW) / 2), round(g.cardY), g.cardW, [LRServerCard height])];
    [self setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self layoutPane];
}

- (void)setTopInset:(CGFloat)inset {
    _topInset = inset;
    [self layoutPane];
}

- (void)setStatus:(NSString *)s {
    if ([s isEqual:_status]) return;
    [_status release];
    _status = [s copy];
    [self setNeedsDisplay:YES];
}

- (void)setDetail:(NSString *)s {
    if ([s isEqual:_detail]) return;
    [_detail release];
    _detail = [s copy];
    LRDashGeometry g = [self geometry];
    [self setNeedsDisplayInRect:NSMakeRect(0, g.statusY, NSWidth([self bounds]), 60)];
}

- (void)setFootnote:(NSString *)s {
    if ([s isEqual:_footnote]) return;
    [_footnote release];
    _footnote = [s copy];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSRect b = [self bounds];
    LRSkin *s = SKIN;
    LRDashGeometry g = [self geometry];
    if (s->flat) {
        [s->background setFill];
        NSRectFill(dirty);
    } else {
        LRDrawDenim(dirty, 0.18f);
        LRDrawVignette(ctx, NSRectToCGRect(b), CGPointMake(NSMidX(b), g.centerY));
        /* the bar's shadow on the cloth */
        LRFillVertical(ctx, CGRectMake(0, _topInset, NSWidth(b), 7),
                       [NSColor colorWithCalibratedWhite:0 alpha:0.45f], [NSColor colorWithCalibratedWhite:0 alpha:0]);
    }
    CGFloat textW = MIN(NSWidth(b) - 40, 460);
    CGFloat tx = round((NSWidth(b) - textW) / 2);
    NSFont *statusFont = s->flat ? [LRSkin lightFont:24] : [LRSkin titleFont:19];
    NSFont *detailFont = [LRSkin bodyFont:s->flat ? 13 : 12];
    NSRect sr = NSMakeRect(tx, round(g.statusY), textW, 30);
    NSRect dr = NSMakeRect(tx, round(g.statusY + (s->flat ? 34 : 30)), textW, 34);
    if (s->flat) {
        LRDrawText(_status, sr, statusFont, s->pageInk, NSCenterTextAlignment);
        LRDrawText(_detail, dr, detailFont, s->pageMuted, NSCenterTextAlignment);
    } else {
        LRDrawEngraved(_status, sr, statusFont, NSCenterTextAlignment, s->pageInk, s->pageShadow, -1);
        LRDrawEngraved(_detail, dr, detailFont, NSCenterTextAlignment, s->pageMuted, s->pageShadow, -1);
    }
    if ([_footnote length]) {
        NSFont *f = [LRSkin bodyFont:11];
        NSRect fr = NSMakeRect(tx, NSHeight(b) - 24, textW, 16);
        if (s->flat) LRDrawText(_footnote, fr, f, s->pageMuted, NSCenterTextAlignment);
        else LRDrawEngraved(_footnote, fr, f, NSCenterTextAlignment,
                            LRColorAlpha(s->pageMuted, 0.75f), s->pageShadow, -1);
    }
}
@end
