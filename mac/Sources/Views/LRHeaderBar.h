/* the top of the main window. classic: black denim from the title bar down
   (on 10.8 / 10.9 the title bar itself is covered by LRTitlebarOverlay, on
   10.10+ the content runs under a transparent one), a copper seam above the
   bottom edge, white engraved type; flat: the yosemite title bar material,
   tint glyphs, a hairline. keys go left (over the sidebar) and right */
#import <Cocoa/Cocoa.h>

@class LRBarKey;

@interface LRHeaderBar : NSView {
    NSString *_title;
    NSMutableArray *_leftKeys;
    NSMutableArray *_rightKeys;
    CGFloat _titleRow;      /* the part under the window's own title bar */
    BOOL _drawsTitle;
    NSView *_vibrancy;
}
@property (nonatomic, copy) NSString *title;
/* how much of the bar sits under a transparent title bar (10.10+), 0 when
   the window draws its own title bar above */
@property (nonatomic, assign) CGFloat titleRow;
/* draw the window title here (when the system does not) */
@property (nonatomic, assign) BOOL drawsTitle;
+ (CGFloat)barHeight;      /* the row of keys, without the title row */
- (void)setLeftKeys:(NSArray *)keys;
- (void)setRightKeys:(NSArray *)keys;
@end

/* the title bar of 10.8 / 10.9 in denim: a view put into the window frame
   under the traffic lights, with the window's rounded top corners */
@interface LRTitlebarOverlay : NSView {
    NSString *_title;
}
@property (nonatomic, copy) NSString *title;
+ (LRTitlebarOverlay *)installInWindow:(NSWindow *)window;
@end

/* drag the window from a bar, double-click to minimize or zoom as the
   system preference says: shared by both views above */
void LRBarMouseDown(NSView *view, NSEvent *event);
