#import "LRCompat.h"
#import "LRLocalization.h"
#import <objc/message.h>

static NSInteger gMajor = -1, gMinor = 0;

static void LRLoadVersion(void) {
    if (gMajor >= 0) return;
    gMajor = 10;
    gMinor = 8;
    /* NSProcessInfo learned operatingSystemVersion in 10.10; the plist is
       there on every release, and a binary linked against an old sdk is told
       10.16 on big sur and later, which still orders right */
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:
                           @"/System/Library/CoreServices/SystemVersion.plist"];
    NSArray *parts = [[plist objectForKey:@"ProductVersion"] componentsSeparatedByString:@"."];
    if ([parts count] >= 2) {
        gMajor = [[parts objectAtIndex:0] integerValue];
        gMinor = [[parts objectAtIndex:1] integerValue];
    }
}

BOOL LRMacSystemAtLeast(NSInteger major, NSInteger minor) {
    LRLoadVersion();
    return gMajor > major || (gMajor == major && gMinor >= minor);
}

NSString *LRMacSystemVersion(void) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:
                           @"/System/Library/CoreServices/SystemVersion.plist"];
    NSString *v = [plist objectForKey:@"ProductVersion"];
    return v ? v : @"10.8";
}

BOOL LRMacIsYosemite(void) {
    return LRMacSystemAtLeast(10, 10) && NSClassFromString(@"NSVisualEffectView") != nil;
}

void LRWindowHideTitlebar(NSWindow *window) {
    if (!LRMacIsYosemite()) return;
    [window setStyleMask:[window styleMask] | LRFullSizeContentViewWindowMask];
    /* titlebarAppearsTransparent and titleVisibility (1 = hidden) */
    if ([window respondsToSelector:NSSelectorFromString(@"setTitlebarAppearsTransparent:")])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(window, NSSelectorFromString(@"setTitlebarAppearsTransparent:"), YES);
    if ([window respondsToSelector:NSSelectorFromString(@"setTitleVisibility:")])
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(window, NSSelectorFromString(@"setTitleVisibility:"), 1);
}

NSView *LRMakeVibrantView(NSRect frame, NSInteger material, NSInteger blending) {
    Class cls = NSClassFromString(@"NSVisualEffectView");
    if (!cls) return nil;
    NSView *v = [[[cls alloc] initWithFrame:frame] autorelease];
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(v, NSSelectorFromString(@"setMaterial:"), material);
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(v, NSSelectorFromString(@"setBlendingMode:"), blending);
    /* NSVisualEffectStateFollowsWindowActiveState */
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(v, NSSelectorFromString(@"setState:"), 0);
    return v;
}

CGFloat LRBackingScale(NSView *view) {
    NSWindow *w = [view window];
    if (w && [w respondsToSelector:@selector(backingScaleFactor)]) return [w backingScaleFactor];
    NSScreen *s = [NSScreen mainScreen];
    return [s respondsToSelector:@selector(backingScaleFactor)] ? [s backingScaleFactor] : 1;
}

CGFloat LRHairlineFor(NSView *view) {
    return 1.0f / LRBackingScale(view);
}

/* one bitmap per scale (1x and retina), drawn through core graphics with an
   NSGraphicsContext around it so NSColor and NSString drawing work too */
static NSBitmapImageRep *LRRenderRep(NSSize size, CGFloat scale, BOOL flipped,
                                     void (^draw)(CGContextRef, CGRect)) {
    size_t w = (size_t)ceil(size.width * scale), h = (size_t)ceil(size.height * scale);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    CGContextScaleCTM(ctx, scale, scale);
    if (flipped) {
        CGContextTranslateCTM(ctx, 0, size.height);
        CGContextScaleCTM(ctx, 1, -1);
    }
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:ctx flipped:flipped]];
    draw(ctx, CGRectMake(0, 0, size.width, size.height));
    [NSGraphicsContext restoreGraphicsState];
    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!cg) return nil;
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithCGImage:cg] autorelease];
    CGImageRelease(cg);
    [rep setSize:size];
    return rep;
}

NSImage *LRImageWithSize(NSSize size, BOOL flipped, void (^draw)(CGContextRef ctx, CGRect rect)) {
    if (size.width <= 0 || size.height <= 0 || !draw) return nil;
    NSImage *img = [[[NSImage alloc] initWithSize:size] autorelease];
    for (int scale = 1; scale <= 2; ++scale) {
        NSBitmapImageRep *rep = LRRenderRep(size, scale, flipped, draw);
        if (rep) [img addRepresentation:rep];
    }
    return img;
}

NSString *LRTrim(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return nil;
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [t length] ? t : nil;
}

NSString *LRBytes(unsigned long long bytes) {
    if (bytes < 1024ULL) return [NSString stringWithFormat:@"%llu %@", bytes, L(@"B")];
    double v = (double)bytes / 1024.0;
    NSArray *units = [NSArray arrayWithObjects:L(@"KB"), L(@"MB"), L(@"GB"), L(@"TB"), nil];
    NSUInteger u = 0;
    while (v >= 1024.0 && u + 1 < [units count]) {
        v /= 1024.0;
        ++u;
    }
    NSString *fmt = v >= 100.0 ? @"%.0f %@" : (v >= 10.0 ? @"%.1f %@" : @"%.2f %@");
    NSString *text = [NSString stringWithFormat:fmt, v, [units objectAtIndex:u]];
    if (LRCurrentLanguage() == LRLanguageRussian)
        text = [text stringByReplacingOccurrencesOfString:@"." withString:@","];
    return text;
}

NSString *LRSpeed(double bps) {
    if (bps < 0) bps = 0;
    if (bps < 1024.0) return [NSString stringWithFormat:@"%.0f %@", bps, L(@"B/s")];
    if (bps < 1024.0 * 1024.0) return [NSString stringWithFormat:@"%.0f %@", bps / 1024.0, L(@"KB/s")];
    NSString *text = [NSString stringWithFormat:@"%.1f %@", bps / (1024.0 * 1024.0), L(@"MB/s")];
    if (LRCurrentLanguage() == LRLanguageRussian)
        text = [text stringByReplacingOccurrencesOfString:@"." withString:@","];
    return text;
}

NSString *LRDuration(long seconds) {
    if (seconds < 0) seconds = 0;
    long d = seconds / 86400;
    long h = (seconds / 3600) % 24;
    long m = (seconds / 60) % 60;
    long s = seconds % 60;
    if (d > 0) return [NSString stringWithFormat:@"%ld%@ %02ld:%02ld", d, L(@"d"), h, m];
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", h, m, s];
}

NSWindow *LRHostWindow(void) {
    id delegate = [NSApp delegate];
    NSWindow *w = [delegate respondsToSelector:@selector(mainWindow)]
        ? [delegate performSelector:@selector(mainWindow)] : nil;
    if (w && [w isVisible] && ![w attachedSheet] && ![w isMiniaturized]) return w;
    return nil;
}

void LRActivateApp(void) {
    [NSApp activateIgnoringOtherApps:YES];
}

NSString *LRPasteboardString(void) {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *s = [pb stringForType:NSPasteboardTypeString];
    if (!s) {
        NSArray *urls = [pb readObjectsForClasses:[NSArray arrayWithObject:[NSURL class]] options:nil];
        if ([urls count]) s = [[urls objectAtIndex:0] absoluteString];
    }
    return LRTrim(s);
}

void LRSetPasteboardString(NSString *text) {
    if (!text) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
}
