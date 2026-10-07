/* qr codes both ways: a crisp NSImage for a payload (whole pixels per
   module, a four module quiet zone), and the text of every code found in an
   image or on the screen, through the zbar the ios app scans its camera with */
#import <Cocoa/Cocoa.h>

/* nil when the text does not fit a qr code at all; side in points */
NSImage *LRQRImage(NSString *text, CGFloat side);
/* the version (1..40) the text needs, 0 when it does not fit */
int LRQRVersionForText(NSString *text);
/* the decoded payloads, possibly empty */
NSArray *LRQRDecodeCGImage(CGImageRef image);
NSArray *LRQRDecodeFile(NSString *path);
/* every display, as it is right now (the share sheet of a phone app shown
   in a browser, a picture in a chat) */
NSArray *LRQRDecodeScreen(void);
