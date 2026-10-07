#import "LRToast.h"
#import "LRDraw.h"

static LRToast *gCurrentToast = nil;

@implementation LRToast

+ (NSFont *)font {
    return SKIN->flat ? [LRSkin bodyFont:13] : [LRSkin boldFont:13];
}

- (BOOL)isFlipped {
    return YES;
}

- (id)initWithText:(NSString *)text tape:(NSColor *)tape width:(CGFloat)maxWidth {
    BOOL flat = SKIN->flat;
    NSFont *font = [LRToast font];
    NSRect box = [text boundingRectWithSize:NSMakeSize(maxWidth - 40, 400)
                                    options:NSStringDrawingUsesLineFragmentOrigin
                                 attributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];
    NSRect frame = NSMakeRect(0, 0, MIN(maxWidth, ceil(box.size.width) + 40),
                              ceil(box.size.height) + (flat ? 16 : 20));
    if ((self = [super initWithFrame:frame])) {
        _text = [text copy];
        _tape = [tape retain];
        [self setWantsLayer:YES];
    }
    return self;
}

- (void)dealloc {
    [_text release];
    [_tape release];
    [super dealloc];
}

- (NSDictionary *)textAttributes:(NSColor *)color {
    NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [p setAlignment:NSCenterTextAlignment];
    [p setLineBreakMode:NSLineBreakByWordWrapping];
    return [NSDictionary dictionaryWithObjectsAndKeys:[LRToast font], NSFontAttributeName,
            color, NSForegroundColorAttributeName, p, NSParagraphStyleAttributeName, nil];
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGRect b = NSRectToCGRect([self bounds]);
    NSRect tr = NSInsetRect([self bounds], 20, SKIN->flat ? 8 : 10);
    if (SKIN->flat) {
        LRAddRoundRect(ctx, CGRectInset(b, 1, 1), MIN(14.0f, b.size.height / 2));
        [LRColorAlpha(_tape, 0.9f) setFill];
        CGContextFillPath(ctx);
        [_text drawWithRect:tr options:NSStringDrawingUsesLineFragmentOrigin
                 attributes:[self textAttributes:[NSColor whiteColor]]];
        return;
    }
    CGRect g = CGRectInset(b, 0.5f, 0.5f);
    LRAddRoundRect(ctx, g, 9);
    [LRColorAlpha(LRColorMix(_tape, [NSColor blackColor], 0.35f), 0.84f) setFill];
    CGContextFillPath(ctx);
    CGContextSaveGState(ctx);
    LRAddRoundRect(ctx, g, 9);
    CGContextClip(ctx);
    LRFillVertical(ctx, CGRectMake(g.origin.x, g.origin.y, g.size.width, g.size.height / 2),
                   [NSColor colorWithCalibratedWhite:1 alpha:0.16f],
                   [NSColor colorWithCalibratedWhite:1 alpha:0.04f]);
    CGContextRestoreGState(ctx);
    LRAddRoundRect(ctx, g, 9);
    CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.28f);
    CGContextSetLineWidth(ctx, 1);
    CGContextStrokePath(ctx);
    [_text drawWithRect:NSOffsetRect(tr, 0, -1) options:NSStringDrawingUsesLineFragmentOrigin
             attributes:[self textAttributes:[NSColor colorWithCalibratedWhite:0 alpha:0.6f]]];
    [_text drawWithRect:tr options:NSStringDrawingUsesLineFragmentOrigin
             attributes:[self textAttributes:[NSColor whiteColor]]];
}

/* a click sends it away early */
- (void)mouseDown:(NSEvent *)event {
    [self leave];
}

- (void)leave {
    if (gCurrentToast != self) return;
    NSRect f = [self frame];
    f.origin.y = -f.size.height - 8;
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.22];
    [[self animator] setFrame:f];
    [[self animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];
    LRToast *me = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gCurrentToast == me) {
            [me removeFromSuperview];
            [gCurrentToast release];
            gCurrentToast = nil;
        }
    });
}

+ (void)notify:(NSString *)text {
    Class cls = NSClassFromString(@"NSUserNotification");
    if (!cls) return;
    id n = [[[cls alloc] init] autorelease];
    [n setValue:@"LegacyRay" forKey:@"title"];
    [n setValue:text forKey:@"informativeText"];
    id center = [NSClassFromString(@"NSUserNotificationCenter") performSelector:@selector(defaultUserNotificationCenter)];
    [center performSelector:@selector(deliverNotification:) withObject:n];
}

+ (void)show:(NSString *)text tape:(NSColor *)tape important:(BOOL)important {
    if (![text length]) return;
    id<LRToastHost> d = (id<LRToastHost>)[NSApp delegate];
    NSView *host = [d respondsToSelector:@selector(toastHostView)] ? [d toastHostView] : nil;
    if (!host || ![[host window] isVisible] || [[host window] isMiniaturized]) {
        if (important) [self notify:text];
        return;
    }
    if (gCurrentToast) {
        [gCurrentToast removeFromSuperview];
        [gCurrentToast release];
        gCurrentToast = nil;
    }
    CGFloat maxW = MIN(NSWidth([host bounds]) - 40, 460);
    LRToast *toast = [[LRToast alloc] initWithText:text tape:tape width:maxW];
    NSRect b = [host bounds];
    CGFloat x = round((NSWidth(b) - NSWidth([toast frame])) / 2);
    CGFloat top = [d toastTopInset] + 12;
    BOOL flippedHost = [host isFlipped];
    NSRect start = NSMakeRect(x, 0, NSWidth([toast frame]), NSHeight([toast frame]));
    NSRect rest = start;
    if (flippedHost) {
        start.origin.y = top - NSHeight(start) - 6;
        rest.origin.y = top;
    } else {
        start.origin.y = NSHeight(b) - top + 6;
        rest.origin.y = NSHeight(b) - top - NSHeight(rest);
    }
    [toast setFrame:start];
    [toast setAlphaValue:0];
    [toast setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin |
                               (flippedHost ? NSViewMaxYMargin : NSViewMinYMargin)];
    [host addSubview:toast positioned:NSWindowAbove relativeTo:nil];
    gCurrentToast = toast;
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.25];
    [[toast animator] setFrame:rest];
    [[toast animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
    NSTimeInterval stay = 2.4 + [text length] / 40.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(stay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast leave];
    });
}

+ (void)show:(NSString *)text {
    [self show:text tape:[NSColor colorWithCalibratedRed:0.12f green:0.12f blue:0.13f alpha:1] important:NO];
}

+ (void)showError:(NSString *)text {
    [self show:text tape:[NSColor colorWithCalibratedRed:0.72f green:0.10f blue:0.10f alpha:1] important:YES];
}

+ (void)showSuccess:(NSString *)text {
    [self show:text tape:[NSColor colorWithCalibratedRed:0.10f green:0.45f blue:0.20f alpha:1] important:YES];
}
@end
