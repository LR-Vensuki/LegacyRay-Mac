/* the os x side of what app/Sources/Core expects from its platform, and the
   few differences between os x 10.8 and the systems after it that the app has
   to care about. the app is built against the 10.8 sdk with a 10.8 minimum;
   everything newer (vibrancy, full size content views, the yosemite fonts) is
   looked up at run time */
#import <Cocoa/Cocoa.h>

/* the running os x, 10.8 -> (10, 8); 10.10 is the first flat one */
BOOL LRMacSystemAtLeast(NSInteger major, NSInteger minor);
NSString *LRMacSystemVersion(void);
/* yosemite and later: vibrancy, full size content views, flat controls */
BOOL LRMacIsYosemite(void);

/* the styleMask bit and window properties yosemite added */
#define LRFullSizeContentViewWindowMask (1 << 15)
void LRWindowHideTitlebar(NSWindow *window);

/* an NSVisualEffectView on 10.10+, nil before. material: 0 appearance based,
   1 light, 2 dark, 3 titlebar; blending: 0 behind window, 1 within window */
NSView *LRMakeVibrantView(NSRect frame, NSInteger material, NSInteger blending);

/* one device pixel, in points, for the window's screen */
CGFloat LRHairlineFor(NSView *view);
CGFloat LRBackingScale(NSView *view);

/* a resolution independent image from core graphics drawing: the block runs
   again for every backing scale it is drawn at, in a flipped context when
   flipped is YES (top left origin, like the ios drawing code) */
NSImage *LRImageWithSize(NSSize size, BOOL flipped, void (^draw)(CGContextRef ctx, CGRect rect));

/* trimmed string or nil */
NSString *LRTrim(NSString *s);
/* "12.4 MB" */
NSString *LRBytes(unsigned long long bytes);
/* "340 KB/s" */
NSString *LRSpeed(double bytesPerSecond);
/* "01:24:07" or "3d 04:10" */
NSString *LRDuration(long seconds);

/* the window alerts and sheets attach to: the main window when it is on
   screen, else nil (app modal) */
NSWindow *LRHostWindow(void);
/* bring the app forward, it may be a menu bar app at that moment */
void LRActivateApp(void);

/* the clipboard as text */
NSString *LRPasteboardString(void);
void LRSetPasteboardString(NSString *text);
