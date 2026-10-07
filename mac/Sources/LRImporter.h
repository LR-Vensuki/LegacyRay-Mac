/* everything that brings servers in: the import menu, pasted, typed or
   dropped text, files, qr codes on the screen or in pictures, legacyray://
   and proxy links the system hands over, karing backups. classifies the
   input, confirms what needs confirming and hands the rest to the daemon */
#import <Cocoa/Cocoa.h>

@interface LRImporter : NSObject
/* the menu behind every "+" */
+ (NSMenu *)menu;
+ (void)importText:(NSString *)text;
+ (void)importFileAtPath:(NSString *)path;
+ (void)importData:(NSData *)data filename:(NSString *)filename;
/* url schemes: legacyray://import?url=..., legacyray://add/<link>, vless://... */
+ (BOOL)handleOpenURL:(NSURL *)url;
+ (void)pasteFromClipboard;
+ (void)promptSubscription;
+ (void)promptManual;
+ (void)chooseFile;
+ (void)scanScreen;
@end
