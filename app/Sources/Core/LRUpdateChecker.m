#import "LRUpdateChecker.h"
#import "LRDaemonClient.h"
#import "LRPrefs.h"
#import "LRActivityLog.h"
#import "LRVersion.h"
#include "cJSON.h"

NSComparisonResult LRCompareVersions(NSString *a, NSString *b) {
    NSCharacterSet *strip = [NSCharacterSet characterSetWithCharactersInString:@"vV "];
    NSArray *pa = [[a stringByTrimmingCharactersInSet:strip] componentsSeparatedByString:@"."];
    NSArray *pb = [[b stringByTrimmingCharactersInSet:strip] componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX([pa count], [pb count]); ++i) {
        NSInteger x = i < [pa count] ? [[pa objectAtIndex:i] integerValue] : 0;
        NSInteger y = i < [pb count] ? [[pb objectAtIndex:i] integerValue] : 0;
        if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

@implementation LRRelease
@synthesize version = _version, pageURL = _pageURL, debURL = _debURL, notes = _notes;
- (void)dealloc {
    [_version release];
    [_pageURL release];
    [_debURL release];
    [_notes release];
    [super dealloc];
}
- (BOOL)isNewer {
    return [_version length] && LRCompareVersions(_version, @LR_VERSION) == NSOrderedDescending;
}
@end

@implementation LRUpdateChecker

+ (void)checkNow:(void (^)(LRRelease *, NSString *))done {
    void (^callback)(LRRelease *, NSString *) = [[done copy] autorelease];
    NSString *url = [NSString stringWithFormat:@"https://api.github.com/repos/%s/releases/latest", LR_GITHUB_REPO];
    [[LRDaemonClient shared] fetchURL:url reply:^(NSData *body, NSString *error) {
        [LRPrefs setLastUpdateCheck:[NSDate date]];
        if (!body) {
            LRLogFail(@"update", @"update check failed: %@", error);
            if (callback) callback(nil, error ? error : @"Unable to reach GitHub");
            return;
        }
        NSMutableData *text = [NSMutableData dataWithData:body];
        [text appendBytes:"\0" length:1];
        cJSON *root = cJSON_Parse([text bytes]);
        cJSON *tag = root ? cJSON_GetObjectItemCaseSensitive(root, "tag_name") : NULL;
        if (!tag || !cJSON_IsString(tag) || !tag->valuestring) {
            if (root) cJSON_Delete(root);
            if (callback) callback(nil, @"Invalid update response");
            return;
        }
        LRRelease *r = [[[LRRelease alloc] init] autorelease];
        r.version = [NSString stringWithUTF8String:tag->valuestring];
        cJSON *page = cJSON_GetObjectItemCaseSensitive(root, "html_url");
        if (cJSON_IsString(page)) r.pageURL = [NSString stringWithUTF8String:page->valuestring];
        cJSON *notes = cJSON_GetObjectItemCaseSensitive(root, "body");
        if (cJSON_IsString(notes)) r.notes = [NSString stringWithUTF8String:notes->valuestring];
        cJSON *assets = cJSON_GetObjectItemCaseSensitive(root, "assets");
        cJSON *asset = NULL;
        cJSON_ArrayForEach(asset, assets) {
            cJSON *u = cJSON_GetObjectItemCaseSensitive(asset, "browser_download_url");
            if (!cJSON_IsString(u)) continue;
            NSString *link = [NSString stringWithUTF8String:u->valuestring];
#if defined(LR_MACOS)
            /* the mac build ships as LegacyRay-<version>-mac.zip */
            NSString *file = [[link lastPathComponent] lowercaseString];
            if (([file hasSuffix:@".zip"] || [file hasSuffix:@".dmg"]) &&
                ([file rangeOfString:@"mac"].location != NSNotFound ||
                 [file rangeOfString:@"osx"].location != NSNotFound)) {
                r.debURL = link;
                break;
            }
#else
            if ([link hasSuffix:@".deb"]) {
                r.debURL = link;
                break;
            }
#endif
        }
        cJSON_Delete(root);
        LRLog(@"update", @"latest release %@", r.version);
        if (callback) callback(r, nil);
    }];
}

+ (void)checkIfDue:(void (^)(LRRelease *))found {
    if (![LRPrefs automaticUpdateChecks]) return;
    NSDate *last = [LRPrefs lastUpdateCheck];
    if (last && [[NSDate date] timeIntervalSinceDate:last] < 86400) return;
    void (^callback)(LRRelease *) = [[found copy] autorelease];
    [self checkNow:^(LRRelease *release, NSString *error) {
        if ([release isNewer] && callback) callback(release);
    }];
}

+ (void)openURLString:(NSString *)s {
    NSURL *u = [NSURL URLWithString:s];
#if defined(LR_MACOS)
    if (u) [[NSWorkspace sharedWorkspace] openURL:u];
#else
    if (u) [[UIApplication sharedApplication] openURL:u];
#endif
}

+ (void)openRelease:(LRRelease *)release {
#if !defined(LR_MACOS)
    if ([LRPrefs preferGitHubLegacy]) {
        NSURL *legacy = [NSURL URLWithString:[NSString stringWithFormat:@"githublegacy://release/%s/latest",
                                               LR_GITHUB_REPO]];
        if ([[UIApplication sharedApplication] canOpenURL:legacy]) {
            [[UIApplication sharedApplication] openURL:legacy];
            return;
        }
    }
#endif
    [self openURLString:release.pageURL ? release.pageURL
        : [NSString stringWithFormat:@"https://github.com/%s/releases/latest", LR_GITHUB_REPO]];
}

+ (void)openProjectPage {
#if !defined(LR_MACOS)
    if ([LRPrefs preferGitHubLegacy]) {
        NSURL *legacy = [NSURL URLWithString:[NSString stringWithFormat:@"githublegacy://repo/%s", LR_GITHUB_REPO]];
        if ([[UIApplication sharedApplication] canOpenURL:legacy]) {
            [[UIApplication sharedApplication] openURL:legacy];
            return;
        }
    }
#endif
    [self openURLString:[NSString stringWithFormat:@"https://github.com/%s", LR_GITHUB_REPO]];
}
@end
