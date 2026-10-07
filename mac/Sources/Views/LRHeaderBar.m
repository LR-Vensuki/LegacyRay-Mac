#import "LRHeaderBar.h"
#import "LRBarKey.h"
#import "LRDraw.h"

#define LR_BAR_HEIGHT 40.0f

void LRBarMouseDown(NSView *view, NSEvent *event) {
    NSWindow *window = [view window];
    if ([event clickCount] == 2) {
        NSString *action = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleActionOnDoubleClick"];
        BOOL minimize = [[NSUserDefaults standardUserDefaults] boolForKey:@"AppleMiniaturizeOnDoubleClick"];
        if ([action isEqualToString:@"Minimize"] || (!action && minimize)) [window performMiniaturize:nil];
        else if (![action isEqualToString:@"None"]) [window performZoom:nil];
        return;
    }
    /* the content of a titled window does not move it on its own */
    NSPoint start = [NSEvent mouseLocation];
    NSPoint origin = [window frame].origin;
    BOOL moved = NO;
    for (;;) {
        NSEvent *e = [window nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask];
        if ([e type] == NSLeftMouseUp) break;
        NSPoint now = [NSEvent mouseLocation];
        if (!moved && hypot(now.x - start.x, now.y - start.y) < 2) continue;
        moved = YES;
        NSPoint o = NSMakePoint(origin.x + now.x - start.x, origin.y + now.y - start.y);
        /* never under the menu bar */
        NSScreen *screen = [window screen] ? [window screen] : [NSScreen mainScreen];
        CGFloat top = NSMaxY([screen visibleFrame]);
        if (o.y + NSHeight([window frame]) > top) o.y = top - NSHeight([window frame]);
        [window setFrameOrigin:o];
    }
}

static void LRDrawTitle(NSString *title, NSRect row, BOOL active) {
    if (![title length]) return;
    NSFont *font = [LRSkin titleFont:14];
    CGFloat h = LRTextSize(title, font).height;
    NSRect r = NSMakeRect(NSMinX(row) + 80, round(NSMidY(row) - h / 2), NSWidth(row) - 160, h + 2);
    LRDrawEngraved(title, r, font, NSCenterTextAlignment,
                   [NSColor colorWithCalibratedWhite:1 alpha:active ? 1 : 0.6f],
                   [NSColor colorWithCalibratedWhite:0 alpha:0.7f], -1);
}

@implementation LRHeaderBar
@synthesize title = _title, titleRow = _titleRow, drawsTitle = _drawsTitle;

+ (CGFloat)barHeight {
    return LR_BAR_HEIGHT;
}

- (id)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _leftKeys = [[NSMutableArray alloc] init];
        _rightKeys = [[NSMutableArray alloc] init];
        if (SKIN->flat && LRMacIsYosemite()) {
            /* NSVisualEffectMaterialTitlebar, within the window */
            _vibrancy = [LRMakeVibrantView([self bounds], 3, 1) retain];
            [_vibrancy setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
            [self addSubview:_vibrancy];
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_title release];
    [_leftKeys release];
    [_rightKeys release];
    [_vibrancy release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return !_vibrancy;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)viewDidMoveToWindow {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSWindow *w = [self window];
    if (!w) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyChanged) name:NSWindowDidBecomeKeyNotification object:w];
    [nc addObserver:self selector:@selector(keyChanged) name:NSWindowDidResignKeyNotification object:w];
}

- (void)keyChanged {
    [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString *)t {
    if ([t isEqual:_title]) return;
    [_title release];
    _title = [t copy];
    [self setNeedsDisplay:YES];
}

- (void)setTitleRow:(CGFloat)row {
    _titleRow = row;
    [self layoutKeys];
    [self setNeedsDisplay:YES];
}

- (void)replace:(NSMutableArray *)list with:(NSArray *)keys {
    for (NSView *k in list) [k removeFromSuperview];
    [list setArray:keys ? keys : [NSArray array]];
    for (NSView *k in list) [self addSubview:k];
    [self layoutKeys];
}

- (void)setLeftKeys:(NSArray *)keys {
    [self replace:_leftKeys with:keys];
}

- (void)setRightKeys:(NSArray *)keys {
    [self replace:_rightKeys with:keys];
}

- (void)layoutKeys {
    NSRect b = [self bounds];
    CGFloat keyH = SKIN->flat ? 26 : 28;
    CGFloat y = round(_titleRow + (LR_BAR_HEIGHT - keyH) / 2 - (SKIN->flat ? 0 : 1));
    CGFloat gap = SKIN->flat ? 4 : 7;
    CGFloat x = 10;
    for (LRBarKey *k in _leftKeys) {
        CGFloat w = [k preferredWidth];
        [k setFrame:NSMakeRect(x, y, w, keyH)];
        [k setAutoresizingMask:NSViewMaxXMargin];
        x += w + gap;
    }
    x = NSWidth(b) - 10;
    for (LRBarKey *k in _rightKeys) {
        CGFloat w = [k preferredWidth];
        x -= w;
        [k setFrame:NSMakeRect(x, y, w, keyH)];
        [k setAutoresizingMask:NSViewMinXMargin];
        x -= gap;
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)old {
    [super resizeSubviewsWithOldSize:old];
    [self layoutKeys];
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSRect b = [self bounds];
    BOOL active = [[self window] isKeyWindow] || [[self window] isMainWindow];
    if (SKIN->flat) {
        if (!_vibrancy) {
            [[NSColor colorWithCalibratedWhite:active ? 0.965f : 0.98f alpha:1] setFill];
            NSRectFill(b);
        }
        [SKIN->separator setFill];
        CGFloat hair = LRHairlineFor(self);
        NSRectFillUsingOperation(NSMakeRect(0, NSHeight(b) - hair, NSWidth(b), hair), NSCompositeSourceOver);
        return;
    }
    LRDrawDenim(b, 0);
    /* light from above, strongest on the title row */
    CGFloat locs[4] = { 0, 0.5f, 0.5f, 1 };
    LRFillLinear(ctx, CGPointMake(0, NSMinY(b) + _titleRow), CGPointMake(0, NSMaxY(b)),
                 [NSArray arrayWithObjects:[NSColor colorWithCalibratedWhite:1 alpha:0.10f],
                  [NSColor colorWithCalibratedWhite:1 alpha:0.04f], [NSColor colorWithCalibratedWhite:1 alpha:0],
                  [NSColor colorWithCalibratedWhite:0 alpha:0.14f], nil], locs);
    if (_titleRow > 0) {
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, CGRectMake(0, 0, NSWidth(b), _titleRow));
        LRFillVertical(ctx, CGRectMake(0, 0, NSWidth(b), _titleRow),
                       [NSColor colorWithCalibratedWhite:1 alpha:0.14f], [NSColor colorWithCalibratedWhite:1 alpha:0.08f]);
        CGContextRestoreGState(ctx);
        if (_drawsTitle) LRDrawTitle(_title, NSMakeRect(0, 0, NSWidth(b), _titleRow), active);
    }
    CGFloat seam = NSMaxY(b) - 4.5f;
    LRDrawStitchLine(ctx, CGPointMake(0, seam), CGPointMake(NSWidth(b), seam));
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.9f);
    CGContextFillRect(ctx, CGRectMake(0, NSHeight(b) - 1, NSWidth(b), 1));
}

- (void)mouseDown:(NSEvent *)event {
    LRBarMouseDown(self, event);
}
@end

@implementation LRTitlebarOverlay
@synthesize title = _title;

+ (LRTitlebarOverlay *)installInWindow:(NSWindow *)window {
    NSView *frameView = [[window contentView] superview];
    if (!frameView) return nil;
    NSRect fb = [frameView bounds];
    NSRect content = [window contentRectForFrameRect:[window frame]];
    CGFloat titleH = NSHeight([window frame]) - NSHeight(content);
    LRTitlebarOverlay *o = [[[LRTitlebarOverlay alloc]
                             initWithFrame:NSMakeRect(0, NSHeight(fb) - titleH, NSWidth(fb), titleH)] autorelease];
    [o setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    NSArray *subs = [frameView subviews];
    /* under the traffic lights and the toolbar button, over the frame's own
       title bar drawing */
    if ([subs count]) [frameView addSubview:o positioned:NSWindowBelow relativeTo:[subs objectAtIndex:0]];
    else [frameView addSubview:o];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:o selector:@selector(redraw) name:NSWindowDidBecomeKeyNotification object:window];
    [nc addObserver:o selector:@selector(redraw) name:NSWindowDidResignKeyNotification object:window];
    return o;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_title release];
    [super dealloc];
}

- (void)redraw {
    [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString *)t {
    if ([t isEqual:_title]) return;
    [_title release];
    _title = [t copy];
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSRect b = [self bounds];
    BOOL active = [[self window] isKeyWindow] || [[self window] isMainWindow];
    /* the window's own corners: round on top, square below */
    const CGFloat r = 4.5f;
    CGContextSaveGState(ctx);
    CGContextMoveToPoint(ctx, 0, NSHeight(b));
    CGContextAddArcToPoint(ctx, 0, 0, NSMidX(b), 0, r);
    CGContextAddArcToPoint(ctx, NSWidth(b), 0, NSWidth(b), NSHeight(b), r);
    CGContextAddLineToPoint(ctx, NSWidth(b), NSHeight(b));
    CGContextClosePath(ctx);
    CGContextClip(ctx);
    LRDrawDenim(b, 0);
    LRFillVertical(ctx, NSRectToCGRect(b), [NSColor colorWithCalibratedWhite:1 alpha:0.14f],
                   [NSColor colorWithCalibratedWhite:1 alpha:0.08f]);
    /* the bevel of the window's top edge */
    CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.22f);
    CGContextFillRect(ctx, CGRectMake(0, 0, NSWidth(b), 1));
    CGContextRestoreGState(ctx);
    LRDrawTitle(_title, b, active);
}

- (void)mouseDown:(NSEvent *)event {
    LRBarMouseDown(self, event);
}
@end
