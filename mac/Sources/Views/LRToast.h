/* transient messages: the 10.8 bezel (a dark glass panel with a rim of
   light, like the volume and caps lock huds) that drops in under the bar of
   the main window; a pill on yosemite. errors and successes tint it. with
   the window away, errors and successes go to notification center instead */
#import <Cocoa/Cocoa.h>

@interface LRToast : NSView {
    NSString *_text;
    NSColor *_tape;
    BOOL _settled;
}
+ (void)show:(NSString *)text;
+ (void)showError:(NSString *)text;
+ (void)showSuccess:(NSString *)text;
@end

/* where toasts land: the app delegate answers with the main window's
   dashboard and how far down the bar reaches into it */
@protocol LRToastHost <NSObject>
- (NSView *)toastHostView;
- (CGFloat)toastTopInset;
@end
