/* translations: the mac app's own strings first, then the ios tables from
   app/Sources/Core/LRStrings.inc, so a string both apps say reads the same */
#import "LRLocalization.h"

typedef struct {
    const char *en;
    const char *ru;
    const char *zh;
} LRStringEntry;

static const LRStringEntry kMacStrings[] = {
#include "LRMacStrings.inc"
    { NULL, NULL, NULL }
};

static const LRStringEntry kStrings[] = {
#include "LRStrings.inc"
    { NULL, NULL, NULL }
};

static void LRLoadTable(const LRStringEntry *table, NSMutableDictionary *r, NSMutableDictionary *z) {
    for (const LRStringEntry *e = table; e->en; ++e) {
        NSString *key = [NSString stringWithUTF8String:e->en];
        if (!key) continue;
        if (e->ru && e->ru[0] && ![r objectForKey:key]) {
            NSString *v = [NSString stringWithUTF8String:e->ru];
            if (v) [r setObject:v forKey:key];
        }
        if (e->zh && e->zh[0] && ![z objectForKey:key]) {
            NSString *v = [NSString stringWithUTF8String:e->zh];
            if (v) [z setObject:v forKey:key];
        }
    }
}

NSString *LRStringsLookup(NSString *english, LRLanguage language) {
    static NSDictionary *ru = nil, *zh = nil;
    if (!ru) {
        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        NSMutableDictionary *z = [NSMutableDictionary dictionary];
        LRLoadTable(kMacStrings, r, z);
        LRLoadTable(kStrings, r, z);
        ru = [r copy];
        zh = [z copy];
    }
    if (language == LRLanguageRussian) return [ru objectForKey:english];
    if (language == LRLanguageChinese) return [zh objectForKey:english];
    return nil;
}
