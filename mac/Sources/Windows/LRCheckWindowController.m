#import "LRCheckWindowController.h"
#import "LRServerWindowController.h"
#import "LRConnectionCheck.h"
#import "LRBlocks.h"
#import "LRDraw.h"
#import "LRToast.h"

/* the list of steps: a lamp, the name and what was found, the time */
@interface LRCheckList : NSView {
@public
    NSArray *steps;
    NSString *verdict;
    LRCheckResult overall;
}
@end

@implementation LRCheckList

- (void)dealloc {
    [steps release];
    [verdict release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    LRSkin *s = SKIN;
    NSRect b = [self bounds];
    [[NSColor whiteColor] setFill];
    NSRectFill(b);
    CGFloat y = 0, rowH = 44;
    NSUInteger i = 0;
    for (LRCheckStep *step in steps) {
        NSRect row = NSMakeRect(0, y, NSWidth(b), rowH);
        if (i % 2 == 1 && !s->flat) {
            [[NSColor colorWithCalibratedRed:0.93f green:0.95f blue:0.98f alpha:1] setFill];
            NSRectFill(row);
        }
        NSColor *lamp = s->ledOff;
        BOOL on = YES;
        NSString *mark;
        NSColor *markColor = s->groupMuted;
        switch (step.result) {
            case LRCheckRunning: lamp = s->ledAmber; mark = L(@"checking..."); break;
            case LRCheckPassed: lamp = s->ledGreen; markColor = s->good;
                mark = step.ms > 0 ? [NSString stringWithFormat:@"%d %@", step.ms, L(@"ms")] : @"OK"; break;
            case LRCheckWarning: lamp = s->ledAmber; markColor = s->warn; mark = L(@"Warning"); break;
            case LRCheckFailed: lamp = s->ledRed; markColor = s->bad; mark = L(@"Failed"); break;
            case LRCheckSkipped: on = NO; mark = L(@"Skipped"); break;
            default: on = NO; mark = @"—"; break;
        }
        LRDrawLED(ctx, CGPointMake(22, y + rowH / 2), 5.5f, lamp, on);
        NSFont *markFont = [NSFont systemFontOfSize:12];
        CGFloat mw = MIN(LRTextSize(mark, markFont).width, 120);
        LRDrawText(mark, NSMakeRect(NSWidth(b) - 16 - mw, y + 14, mw, 16), markFont, markColor, NSRightTextAlignment);
        CGFloat tw = NSWidth(b) - 40 - mw - 30;
        if ([step.detail length]) {
            LRDrawText(step.name, NSMakeRect(40, y + 6, tw, 17), [NSFont systemFontOfSize:13], [NSColor blackColor],
                       NSLeftTextAlignment);
            LRDrawText(step.detail, NSMakeRect(40, y + 23, tw, 15), [NSFont systemFontOfSize:11],
                       [NSColor disabledControlTextColor], NSLeftTextAlignment);
        } else {
            LRDrawText(step.name, NSMakeRect(40, y + 13, tw, 17), [NSFont systemFontOfSize:13], [NSColor blackColor],
                       NSLeftTextAlignment);
        }
        [[NSColor colorWithCalibratedWhite:0.88f alpha:1] setFill];
        NSRectFill(NSMakeRect(40, y + rowH - 1, NSWidth(b) - 40, 1));
        y += rowH;
        ++i;
    }
    if ([verdict length]) {
        NSRect vr = NSMakeRect(20, y + 12, NSWidth(b) - 40, NSHeight(b) - y - 16);
        NSColor *c = overall == LRCheckFailed ? s->bad : (overall == LRCheckWarning ? s->warn : s->good);
        NSMutableParagraphStyle *p = [[[NSMutableParagraphStyle alloc] init] autorelease];
        [p setLineBreakMode:NSLineBreakByWordWrapping];
        [verdict drawWithRect:vr options:NSStringDrawingUsesLineFragmentOrigin
                   attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:13],
                               NSFontAttributeName, c, NSForegroundColorAttributeName, p,
                               NSParagraphStyleAttributeName, nil]];
    }
}
@end

@implementation LRCheckWindowController

- (id)init {
    NSWindow *w = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 420)
                                               styleMask:NSTitledWindowMask | NSClosableWindowMask |
                                                         NSMiniaturizableWindowMask
                                                 backing:NSBackingStoreBuffered defer:YES] autorelease];
    [w setTitle:L(@"Connection quality")];
    [w setReleasedWhenClosed:NO];
    if ((self = [super initWithWindow:w])) {
        _check = [[LRConnectionCheck alloc] init];
        [self build];
        [w center];
        [self run];
    }
    return self;
}

- (void)dealloc {
    [_check cancel];
    [_check release];
    [_steps release];
    [_run release];
    [_copy release];
    [super dealloc];
}

- (void)windowWillClose:(NSNotification *)n {
    [_check cancel];
}

- (void)build {
    __block LRCheckWindowController *me = self;
    LRInfoHeader *header = [[[LRInfoHeader alloc] initWithFrame:NSZeroRect] autorelease];
    header.title = L(@"Connection quality");
    header.subtitle = L(@"Test DNS, proxy HTTP and the device path");
    header.icon = LRImageWithSize(NSMakeSize(40, 40), YES, ^(CGContextRef ctx, CGRect r) {
        LRDrawLED(ctx, CGPointMake(20, 20), 14, SKIN->ledGreen, YES);
    });
    _steps = [[LRCheckList alloc] initWithFrame:NSMakeRect(0, 0, 480, 7 * 44 + 64)];
    [_run release];
    _run = [LRPushButton(L(@"Run Again"), ^(id s) { [me run]; }) retain];
    [_copy release];
    _copy = [LRPushButton(L(@"Copy Result"), ^(id s) {
        LRSetPasteboardString([me->_check textReport]);
        [LRToast showSuccess:L(@"Copied to the clipboard")];
    }) retain];
    LRBuildInfoContent([self window], header, _steps, [NSArray arrayWithObjects:_run, _copy, nil]);
    [[self window] setDelegate:(id)self];
}

- (void)update {
    LRCheckList *list = (LRCheckList *)_steps;
    [list->steps release];
    list->steps = [[_check steps] copy];
    [list->verdict release];
    list->verdict = [[_check verdict] copy];
    list->overall = [_check overall];
    [list setNeedsDisplay:YES];
    [_run setEnabled:![_check running]];
    [_copy setEnabled:[_check verdict] != nil];
}

- (void)run {
    __block LRCheckWindowController *me = self;
    [_check startWithUpdate:^(LRConnectionCheck *check) { [me update]; }];
    [self update];
}
@end
