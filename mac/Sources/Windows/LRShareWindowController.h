/* a link to hand to another device: a big qr code on a white card stitched
   onto the denim (on its own on yosemite), the link under it, and copy /
   save keys. the iphone app scans it, so do happ and the amnezia client */
#import <Cocoa/Cocoa.h>

@interface LRShareWindowController : NSWindowController {
    NSString *_title;
    NSString *_payload;
    NSString *_subtitle;
    NSString *_fileName;
    BOOL _built;
}
@property (nonatomic, copy) NSString *subtitle;
/* when set, "Save…" writes the payload itself under this name */
@property (nonatomic, copy) NSString *fileName;
- (id)initWithTitle:(NSString *)title payload:(NSString *)payload;
@end
