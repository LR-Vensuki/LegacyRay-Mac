/* the two finishes of the mac app. "classic" is os x 10.8 / 10.9 the way
   apple dressed its own apps then (the leather of calendar, the felt of game
   center), here in the icon's black denim: a denim title bar with a copper
   seam, a denim dashboard with one pearl button, and the stock aqua source
   list and controls everywhere else. "flat" is yosemite: vibrant sidebar,
   white dashboard, hairlines, thin type, a ring for a button. every drawing
   routine reads its colours from here, so a theme switch is a rebuild */
#import <Cocoa/Cocoa.h>

@interface LRSkin : NSObject {
@public
    BOOL flat;
    NSColor *tint, *background, *separator;
    /* the chrome: title and keys on the bars, the copper thread */
    NSColor *barInk, *barMuted, *barShadow, *stitch;
    /* text laid straight onto the dashboard */
    NSColor *pageInk, *pageMuted, *pageShadow;
    /* the card and the grouped rows of sheets */
    NSColor *groupTop, *groupBottom, *groupInk, *groupMuted, *groupDetail, *groupLine, *groupEdge,
            *groupPressed, *groupPressedBottom;
    /* the sidebar: section headers and row captions */
    NSColor *listHeader, *listHeaderShadow, *listInk, *listMuted;
    /* status colours: lamps (the power glyph, dots) and text */
    NSColor *ledGreen, *ledAmber, *ledRed, *ledOff, *good, *warn, *bad, *link;
}

+ (LRSkin *)current;
/* recompute from the theme setting */
+ (void)reload;

+ (NSFont *)titleFont:(CGFloat)size;      /* bar titles, engraved */
+ (NSFont *)labelFont:(CGFloat)size;      /* small bold captions */
+ (NSFont *)bodyFont:(CGFloat)size;
+ (NSFont *)boldFont:(CGFloat)size;
+ (NSFont *)monoFont:(CGFloat)size;
/* thin numerals for the flat clock and big figures */
+ (NSFont *)lightFont:(CGFloat)size;
+ (NSFont *)thinFont:(CGFloat)size;
@end

#define SKIN ([LRSkin current])

/* posted after +reload, so every window can rebuild itself */
extern NSString * const LRSkinDidChangeNotification;
