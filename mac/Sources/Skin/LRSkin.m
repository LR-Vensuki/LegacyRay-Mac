#import "LRSkin.h"
#import "LRPrefs.h"
#import <objc/message.h>

NSString * const LRSkinDidChangeNotification = @"LRSkinDidChangeNotification";

static LRSkin *gSkin = nil;

static NSColor *H(unsigned rgb, CGFloat a) {
    return [NSColor colorWithCalibratedRed:((rgb >> 16) & 0xff) / 255.0f green:((rgb >> 8) & 0xff) / 255.0f
                                      blue:(rgb & 0xff) / 255.0f alpha:a];
}

@implementation LRSkin

- (void)dealloc {
    NSColor **all[] = {
        &tint, &background, &separator, &barInk, &barMuted, &barShadow, &stitch, &pageInk, &pageMuted,
        &pageShadow, &groupTop, &groupBottom, &groupInk, &groupMuted, &groupDetail, &groupLine,
        &groupEdge, &groupPressed, &groupPressedBottom, &listHeader, &listHeaderShadow, &listInk,
        &listMuted, &ledGreen, &ledAmber, &ledRed, &ledOff, &good, &warn, &bad, &link };
    for (size_t i = 0; i < sizeof all / sizeof all[0]; ++i) [*all[i] release];
    [super dealloc];
}

#define SET(field, value) do { [field release]; field = [(value) retain]; } while (0)

- (void)configureFlat {
    flat = YES;
    NSColor *white = H(0xFFFFFF, 1), *ink = H(0x1D1D1F, 1), *clear = [NSColor clearColor];
    NSColor *muted = H(0x8E8E93, 1), *line = H(0xD8D8DC, 1), *blue = H(0x0A84FF, 1);
    SET(tint, blue);
    SET(background, H(0xF7F7F7, 1));
    SET(separator, line);
    SET(barInk, ink);
    SET(barMuted, muted);
    SET(barShadow, clear);
    SET(stitch, clear);
    SET(pageInk, ink);
    SET(pageMuted, muted);
    SET(pageShadow, clear);
    SET(groupTop, white);
    SET(groupBottom, white);
    SET(groupInk, ink);
    SET(groupMuted, muted);
    SET(groupDetail, muted);
    SET(groupLine, line);
    SET(groupEdge, line);
    SET(groupPressed, H(0xEBEBEB, 1));
    SET(groupPressedBottom, H(0xEBEBEB, 1));
    SET(listHeader, H(0x8A8A8E, 1));
    SET(listHeaderShadow, clear);
    SET(listInk, ink);
    SET(listMuted, muted);
    SET(ledGreen, H(0x34C759, 1));
    SET(ledAmber, H(0xFF9500, 1));
    SET(ledRed, H(0xFF3B30, 1));
    SET(ledOff, H(0xC7C7CC, 1));
    SET(good, H(0x28A745, 1));
    SET(warn, H(0xE08600, 1));
    SET(bad, H(0xFF3B30, 1));
    SET(link, blue);
}

/* the values of scripts/design/classic.py, with the source list of 10.8 */
- (void)configureClassic {
    flat = NO;
    NSColor *detail = H(0x385487, 1);
    SET(tint, detail);
    SET(background, H(0xC5CCD4, 1));
    SET(separator, H(0xB8BEC6, 1));
    SET(barInk, H(0xFFFFFF, 1));
    SET(barMuted, H(0xC9CCD1, 1));
    SET(barShadow, H(0x000000, 0.6f));
    SET(stitch, H(0xB8966F, 1));
    SET(pageInk, H(0xFFFFFF, 1));
    SET(pageMuted, H(0xA4A8AE, 1));
    SET(pageShadow, H(0x000000, 0.8f));
    SET(groupTop, H(0xFFFFFF, 1));
    SET(groupBottom, H(0xEFEFEF, 1));
    SET(groupInk, H(0x000000, 1));
    SET(groupMuted, H(0x7F7F7F, 1));
    SET(groupDetail, detail);
    SET(groupLine, H(0xE0E0E0, 1));
    SET(groupEdge, H(0xABABAB, 1));
    SET(groupPressed, H(0x058CF5, 1));
    SET(groupPressedBottom, H(0x015EE6, 1));
    /* mail's MAILBOXES, finder's FAVORITES */
    SET(listHeader, H(0x707E8B, 1));
    SET(listHeaderShadow, H(0xFFFFFF, 0.75f));
    SET(listInk, H(0x000000, 1));
    SET(listMuted, H(0x6E7781, 1));
    SET(ledGreen, H(0x4DB853, 1));
    SET(ledAmber, H(0xE3A437, 1));
    SET(ledRed, H(0xD5483B, 1));
    SET(ledOff, H(0xA2A5A9, 1));
    SET(good, H(0x3E8E41, 1));
    SET(warn, H(0xC07A12, 1));
    SET(bad, H(0xC4372B, 1));
    SET(link, detail);
}

+ (LRSkin *)current {
    if (!gSkin) {
        gSkin = [[LRSkin alloc] init];
        if ([LRPrefs flatSkinActive]) [gSkin configureFlat];
        else [gSkin configureClassic];
    }
    return gSkin;
}

+ (void)reload {
    LRSkin *skin = [[LRSkin alloc] init];
    if ([LRPrefs flatSkinActive]) [skin configureFlat];
    else [skin configureClassic];
    [gSkin release];
    gSkin = skin;
    [[NSNotificationCenter defaultCenter] postNotificationName:LRSkinDidChangeNotification object:nil];
}

+ (NSFont *)font:(NSString *)name size:(CGFloat)size fallbackBold:(BOOL)bold {
    NSFont *f = [NSFont fontWithName:name size:size];
    if (f) return f;
    return bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
}

/* yosemite's own face: helvetica neue there, san francisco from 10.11 on,
   with the weight api from 10.11 (NSFontWeightLight is -0.4, thin -0.6) */
+ (NSFont *)systemFont:(CGFloat)size weight:(CGFloat)weight fallback:(NSString *)name {
    SEL sel = NSSelectorFromString(@"systemFontOfSize:weight:");
    if ([NSFont respondsToSelector:sel])
        return ((NSFont *(*)(id, SEL, CGFloat, CGFloat))objc_msgSend)([NSFont class], sel, size, weight);
    NSFont *f = name ? [NSFont fontWithName:name size:size] : nil;
    return f ? f : [NSFont systemFontOfSize:size];
}

+ (BOOL)flatFonts {
    return [self current]->flat;
}

+ (NSFont *)titleFont:(CGFloat)size {
    if ([self flatFonts]) return [self systemFont:size weight:0.23f fallback:@"HelveticaNeue-Medium"];
    return [self font:@"HelveticaNeue-Bold" size:size fallbackBold:YES];
}
+ (NSFont *)labelFont:(CGFloat)size {
    if ([self flatFonts]) return [self systemFont:size weight:0.23f fallback:@"HelveticaNeue-Medium"];
    return [NSFont boldSystemFontOfSize:size];
}
+ (NSFont *)bodyFont:(CGFloat)size {
    if ([self flatFonts]) return [self systemFont:size weight:0 fallback:@"HelveticaNeue"];
    return [NSFont systemFontOfSize:size];
}
+ (NSFont *)boldFont:(CGFloat)size {
    if ([self flatFonts]) return [self systemFont:size weight:0.23f fallback:@"HelveticaNeue-Medium"];
    return [NSFont boldSystemFontOfSize:size];
}
+ (NSFont *)monoFont:(CGFloat)size {
    NSFont *f = [NSFont fontWithName:@"Menlo-Regular" size:size];
    return f ? f : [NSFont userFixedPitchFontOfSize:size];
}
+ (NSFont *)thinFont:(CGFloat)size {
    if ([self flatFonts]) {
        NSFont *f = [self systemFont:size weight:-0.6f fallback:@"HelveticaNeue-Thin"];
        if (f && ![[f fontName] isEqualToString:[[NSFont systemFontOfSize:size] fontName]]) return f;
        f = [NSFont fontWithName:@"HelveticaNeue-UltraLight" size:size];
        if (f) return f;
    }
    return [self lightFont:size];
}
+ (NSFont *)lightFont:(CGFloat)size {
    if ([self flatFonts]) return [self systemFont:size weight:-0.4f fallback:@"HelveticaNeue-Light"];
    NSFont *f = [NSFont fontWithName:@"HelveticaNeue-Light" size:size];
    return f ? f : [NSFont systemFontOfSize:size];
}
@end
