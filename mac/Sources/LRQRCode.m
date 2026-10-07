#import "LRQRCode.h"
#include "lr_qr.h"
#include "zbar.h"

static lr_qr_t *LRQREncode(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (![data length] || [data length] > LR_QR_MAX_BYTES) return NULL;
    lr_qr_t *q = (lr_qr_t *)malloc(sizeof *q);
    if (!q) return NULL;
    lr_qr_ecc_t ecc = [data length] > 600 ? LR_QR_ECC_L : LR_QR_ECC_M;
    if (lr_qr_encode([data bytes], [data length], ecc, q) != 0) {
        free(q);
        return NULL;
    }
    return q;
}

int LRQRVersionForText(NSString *text) {
    lr_qr_t *q = LRQREncode(text);
    int v = q ? q->version : 0;
    free(q);
    return v;
}

static CGImageRef LRQRBitmap(lr_qr_t *q, int px) CF_RETURNS_RETAINED;
static CGImageRef LRQRBitmap(lr_qr_t *q, int px) {
    int quiet = 4;
    int total = q->size + quiet * 2;
    int w = total * px;
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)w, (size_t)w, 8, (size_t)w, gray,
                                             (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!ctx) return NULL;
    CGContextSetGrayFillColor(ctx, 1, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, w, w));
    CGContextSetGrayFillColor(ctx, 0, 1);
    for (int y = 0; y < q->size; ++y)
        for (int x = 0; x < q->size; ++x)
            if (lr_qr_dark(q, x, y))
                CGContextFillRect(ctx, CGRectMake((x + quiet) * px, w - (y + quiet + 1) * px, px, px));
    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return cg;
}

NSImage *LRQRImage(NSString *text, CGFloat side) {
    lr_qr_t *q = LRQREncode(text);
    if (!q) return nil;
    int total = q->size + 8;
    /* one bitmap per scale, whole pixels per module in each */
    NSImage *img = [[[NSImage alloc] initWithSize:NSMakeSize(side, side)] autorelease];
    for (int scale = 1; scale <= 2; ++scale) {
        int px = (int)floor(side * scale / total);
        if (px < 1) px = 1;
        CGImageRef cg = LRQRBitmap(q, px);
        if (!cg) continue;
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithCGImage:cg] autorelease];
        CGImageRelease(cg);
        [rep setSize:NSMakeSize((CGFloat)total * px / scale, (CGFloat)total * px / scale)];
        [img addRepresentation:rep];
    }
    free(q);
    return img;
}

NSArray *LRQRDecodeCGImage(CGImageRef image) {
    NSMutableArray *found = [NSMutableArray array];
    if (!image) return found;
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    if (w < 21 || h < 21) return found;
    /* zbar wants 8 bit luma */
    unsigned char *luma = malloc(w * h);
    if (!luma) return found;
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(luma, w, h, 8, w, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!ctx) {
        free(luma);
        return found;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image);
    CGContextRelease(ctx);
    zbar_image_scanner_t *scanner = zbar_image_scanner_create();
    zbar_image_scanner_set_config(scanner, ZBAR_NONE, ZBAR_CFG_ENABLE, 0);
    zbar_image_scanner_set_config(scanner, ZBAR_QRCODE, ZBAR_CFG_ENABLE, 1);
    zbar_image_t *zimg = zbar_image_create();
    zbar_image_set_format(zimg, zbar_fourcc('Y', '8', '0', '0'));
    zbar_image_set_size(zimg, (unsigned)w, (unsigned)h);
    zbar_image_set_data(zimg, luma, w * h, NULL);
    if (zbar_scan_image(scanner, zimg) > 0) {
        for (const zbar_symbol_t *sym = zbar_image_first_symbol(zimg); sym; sym = zbar_symbol_next(sym)) {
            const char *data = zbar_symbol_get_data(sym);
            unsigned len = zbar_symbol_get_data_length(sym);
            if (!data || !len) continue;
            NSString *s = [[[NSString alloc] initWithBytes:data length:len encoding:NSUTF8StringEncoding] autorelease];
            if (!s) s = [[[NSString alloc] initWithBytes:data length:len encoding:NSISOLatin1StringEncoding] autorelease];
            if (s && ![found containsObject:s]) [found addObject:s];
        }
    }
    zbar_image_destroy(zimg);
    zbar_image_scanner_destroy(scanner);
    free(luma);
    return found;
}

NSArray *LRQRDecodeFile(NSString *path) {
    NSImage *img = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
    if (!img) return [NSArray array];
    CGImageRef cg = [img CGImageForProposedRect:NULL context:nil hints:nil];
    return LRQRDecodeCGImage(cg);
}

NSArray *LRQRDecodeScreen(void) {
    NSMutableArray *found = [NSMutableArray array];
    for (NSScreen *screen in [NSScreen screens]) {
        NSNumber *num = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
        CGDirectDisplayID display = (CGDirectDisplayID)[num unsignedIntValue];
        CGImageRef shot = CGDisplayCreateImage(display);
        if (!shot) continue;
        for (NSString *s in LRQRDecodeCGImage(shot))
            if (![found containsObject:s]) [found addObject:s];
        CGImageRelease(shot);
    }
    return found;
}
