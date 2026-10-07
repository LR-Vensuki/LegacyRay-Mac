#import "LRShareWindowController.h"
#import "LRServerWindowController.h"
#import "LRBlocks.h"
#import "LRDraw.h"
#import "LRQRCode.h"
#import "LRToast.h"

/* the card the code sits on */
@interface LRQRCard : NSView {
    NSImage *_code;
}
@property (nonatomic, retain) NSImage *code;
@end

@implementation LRQRCard
@synthesize code = _code;

- (void)dealloc {
    [_code release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirty {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    NSRect b = [self bounds];
    LRSkin *s = SKIN;
    CGRect card = CGRectInset(NSRectToCGRect(b), 30, 22);
    if (s->flat) {
        [s->background setFill];
        NSRectFill(b);
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -1), 6, [[NSColor colorWithCalibratedWhite:0 alpha:0.12f] CGColor]);
        LRAddRoundRect(ctx, card, 14);
        CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
        CGContextFillPath(ctx);
        CGContextRestoreGState(ctx);
    } else {
        LRDrawDenim(b, 0.18f);
        LRDrawVignette(ctx, NSRectToCGRect(b), CGPointMake(NSMidX(b), NSMidY(b)));
        /* a paper card with a soft shadow, sewn on at the corners */
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -3), 8, [[NSColor colorWithCalibratedWhite:0 alpha:0.6f] CGColor]);
        LRAddRoundRect(ctx, card, 6);
        CGContextSetRGBFillColor(ctx, 0.985f, 0.982f, 0.968f, 1);
        CGContextFillPath(ctx);
        CGContextRestoreGState(ctx);
        LRDrawStitchRoundRect(ctx, CGRectInset(card, -9, -9), 12);
    }
    if (_code) {
        CGFloat side = MIN(card.size.width, card.size.height) - 24;
        NSRect r = NSMakeRect(round(CGRectGetMidX(card) - side / 2), round(CGRectGetMidY(card) - side / 2), side, side);
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationNone];
        [_code drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1 respectFlipped:YES hints:nil];
    }
}
@end

@implementation LRShareWindowController
@synthesize subtitle = _subtitle, fileName = _fileName;

- (id)initWithTitle:(NSString *)title payload:(NSString *)payload {
    NSWindow *w = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 520)
                                               styleMask:NSTitledWindowMask | NSClosableWindowMask
                                                 backing:NSBackingStoreBuffered defer:YES] autorelease];
    [w setTitle:[NSString stringWithFormat:L(@"Share “%@”"), title]];
    [w setReleasedWhenClosed:NO];
    if ((self = [super initWithWindow:w])) {
        _title = [title copy];
        _payload = [payload copy];
    }
    return self;
}

- (void)dealloc {
    [_title release];
    [_payload release];
    [_subtitle release];
    [_fileName release];
    [super dealloc];
}

- (void)showWindow:(id)sender {
    if (!_built) {
        _built = YES;
        [self build];
        [[self window] center];
    }
    [super showWindow:sender];
}

- (void)saveQR {
    NSImage *big = LRQRImage(_payload, 1024);
    if (!big) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:[NSString stringWithFormat:@"%@ QR.png", _title]];
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"png"]];
    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton) return;
        CGImageRef cg = [big CGImageForProposedRect:NULL context:nil hints:nil];
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithCGImage:cg] autorelease];
        NSData *png = [rep representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]];
        [png writeToURL:[panel URL] atomically:YES];
    }];
}

- (void)saveFile {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:_fileName];
    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton) return;
        [_payload writeToURL:[panel URL] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }];
}

- (void)build {
    __block LRShareWindowController *me = self;
    NSImage *code = LRQRImage(_payload, 300);
    LRInfoHeader *header = [[[LRInfoHeader alloc] initWithFrame:NSZeroRect] autorelease];
    header.title = _title;
    header.subtitle = _subtitle ? _subtitle : L(@"Scan with the phone, or copy the link");
    NSView *body = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 420)] autorelease];
    LRQRCard *card = [[[LRQRCard alloc] initWithFrame:NSMakeRect(0, 66, 420, 354)] autorelease];
    card.code = code;
    [body addSubview:card];
    NSTextField *note = LRWrappingLabel(code ? LRStealth(_payload) : L(@"Too long for a QR code: copy the link instead."),
                                        [NSFont userFixedPitchFontOfSize:10], [NSColor disabledControlTextColor], 380);
    [[note cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [[note cell] setWraps:NO];
    [note setFrame:NSMakeRect(20, 38, 380, 16)];
    [note setSelectable:![LRPrefs stealthMode]];
    [body addSubview:note];
    NSTextField *hint = LRWrappingLabel(L(@"Whoever has this link can use the server. Share it only with people you trust."),
                                        [NSFont systemFontOfSize:11], [NSColor disabledControlTextColor], 380);
    [hint setFrame:NSMakeRect(20, 2, 380, 30)];
    [hint setAlignment:NSCenterTextAlignment];
    [body addSubview:hint];
    /* the body is laid out bottom up: flip it into place */
    NSMutableArray *buttons = [NSMutableArray array];
    [buttons addObject:LRPushButton(L(@"Copy Link"), ^(id s) {
        LRSetPasteboardString(me->_payload);
        [LRToast showSuccess:L(@"Link copied")];
        [[me window] close];
    })];
    if (code) [buttons addObject:LRPushButton(L(@"Save QR Code…"), ^(id s) { [me saveQR]; })];
    if (_fileName) [buttons addObject:LRPushButton(L(@"Save…"), ^(id s) { [me saveFile]; })];
    LRBuildInfoContent([self window], header, body, buttons);
}
@end
