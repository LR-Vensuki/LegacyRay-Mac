#import "LRAWGProfiles.h"
#include "senko_paths.h"
#import "LRDaemonClient.h"
#import "LRPrefs.h"

NSString * const LRAWGProfilesDidChangeNotification = @"LRAWGProfilesDidChangeNotification";

#define LR_AWG_BASE    @SENKO_DATA_DIR
#define LR_AWG_LEGACY  LR_AWG_BASE @"/amneziawg.conf"
#define LR_AWG_NAMES   @"names.plist"
#define LR_AWG_ACTIVE  @"LRAWGActive"

static NSArray *LRAWGObfuscationKeys(void) {
    static NSArray *keys = nil;
    if (!keys) keys = [[NSArray alloc] initWithObjects:@"jc", @"jmin", @"jmax", @"s1", @"s2", @"s3",
                       @"s4", @"h1", @"h2", @"h3", @"h4", @"i1", @"i2", @"i3", @"i4", @"i5", nil];
    return keys;
}

@implementation LRAWGProfile
@synthesize path = _path, name = _name;

- (void)dealloc {
    [_path release];
    [_name release];
    [super dealloc];
}

- (NSString *)fileName {
    return [_path lastPathComponent];
}

- (NSString *)config {
    return [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:NULL];
}

- (NSDictionary *)fields {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *raw in [[self config] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = LRTrim(raw);
        if (!line || [line hasPrefix:@"#"] || [line hasPrefix:@";"] || [line hasPrefix:@"["]) continue;
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *key = [LRTrim([line substringToIndex:eq.location]) lowercaseString];
        NSString *value = LRTrim([line substringFromIndex:eq.location + 1]);
        if (key && value && ![d objectForKey:key]) [d setObject:value forKey:key];
    }
    return d;
}

- (NSString *)endpoint {
    return [[self fields] objectForKey:@"endpoint"];
}

- (BOOL)isAmnezia {
    NSDictionary *f = [self fields];
    for (NSString *k in LRAWGObfuscationKeys()) {
        NSString *v = [f objectForKey:k];
        if ([v length] && ![v isEqualToString:@"0"]) return YES;
    }
    return NO;
}

- (NSString *)summary {
    NSString *kind = [self isAmnezia] ? @"AmneziaWG" : @"WireGuard";
    NSString *ep = [self endpoint];
    return ep ? [NSString stringWithFormat:@"%@ · %@", kind, LRStealth(ep)] : kind;
}
@end

@implementation LRAWGProfiles

+ (NSString *)directory {
    return [LR_AWG_BASE stringByAppendingPathComponent:@"awg"];
}

+ (NSMutableDictionary *)names {
    NSString *p = [[self directory] stringByAppendingPathComponent:LR_AWG_NAMES];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:p];
    return d ? d : [NSMutableDictionary dictionary];
}

+ (void)saveNames:(NSDictionary *)names {
    [names writeToFile:[[self directory] stringByAppendingPathComponent:LR_AWG_NAMES] atomically:YES];
}

+ (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:LRAWGProfilesDidChangeNotification object:nil];
}

+ (void)migrate {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[self directory] withIntermediateDirectories:YES attributes:nil error:NULL];
    if (![fm fileExistsAtPath:LR_AWG_LEGACY]) return;
    NSString *dest = [[self directory] stringByAppendingPathComponent:@"profile-1.conf"];
    if ([fm fileExistsAtPath:dest] || ![fm moveItemAtPath:LR_AWG_LEGACY toPath:dest error:NULL]) return;
    NSMutableDictionary *names = [self names];
    [names setObject:@"AmneziaWG" forKey:@"profile-1.conf"];
    [self saveNames:names];
    [[NSUserDefaults standardUserDefaults] setObject:@"profile-1.conf" forKey:LR_AWG_ACTIVE];
}

+ (NSArray *)profiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:[self directory] error:NULL];
    NSDictionary *names = [self names];
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *f in files) {
        if (![[f pathExtension] isEqualToString:@"conf"]) continue;
        LRAWGProfile *p = [[[LRAWGProfile alloc] init] autorelease];
        p.path = [[self directory] stringByAppendingPathComponent:f];
        NSString *n = [names objectForKey:f];
        p.name = [n length] ? n : [f stringByDeletingPathExtension];
        [list addObject:p];
    }
    /* profile-N.conf: creation order is the number */
    [list sortUsingComparator:^NSComparisonResult(LRAWGProfile *a, LRAWGProfile *b) {
        return [[a fileName] compare:[b fileName] options:NSNumericSearch];
    }];
    return list;
}

+ (LRAWGProfile *)profileAtPath:(NSString *)path {
    for (LRAWGProfile *p in [self profiles]) if ([p.path isEqualToString:path]) return p;
    return nil;
}

+ (BOOL)hasProfiles {
    return [[self profiles] count] > 0;
}

+ (LRAWGProfile *)active {
    NSArray *all = [self profiles];
    NSString *want = [[NSUserDefaults standardUserDefaults] stringForKey:LR_AWG_ACTIVE];
    for (LRAWGProfile *p in all) if ([[p fileName] isEqualToString:want]) return p;
    return [all count] ? [all objectAtIndex:0] : nil;
}

+ (void)setActive:(LRAWGProfile *)profile {
    [[NSUserDefaults standardUserDefaults] setObject:[profile fileName] forKey:LR_AWG_ACTIVE];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self changed];
}

+ (NSString *)nextPath {
    NSUInteger n = 1;
    for (LRAWGProfile *p in [self profiles]) {
        NSString *stem = [[p fileName] stringByDeletingPathExtension];
        if ([stem hasPrefix:@"profile-"]) n = MAX(n, (NSUInteger)[[stem substringFromIndex:8] integerValue] + 1);
    }
    return [[self directory] stringByAppendingPathComponent:
            [NSString stringWithFormat:@"profile-%lu.conf", (unsigned long)n]];
}

+ (NSString *)suggestedNameForConfig:(NSString *)text {
    NSString *base = nil;
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = LRTrim(raw);
        if ([[line lowercaseString] hasPrefix:@"endpoint"]) {
            NSRange eq = [line rangeOfString:@"="];
            if (eq.location == NSNotFound) continue;
            NSString *ep = LRTrim([line substringFromIndex:eq.location + 1]);
            NSRange colon = [ep rangeOfString:@":" options:NSBackwardsSearch];
            base = colon.location != NSNotFound ? [ep substringToIndex:colon.location] : ep;
            break;
        }
    }
    if (![base length] || [LRPrefs stealthMode]) base = @"AmneziaWG";
    NSMutableSet *taken = [NSMutableSet set];
    for (LRAWGProfile *p in [self profiles]) [taken addObject:p.name];
    NSString *name = base;
    for (NSUInteger i = 2; [taken containsObject:name]; ++i)
        name = [NSString stringWithFormat:@"%@ %lu", base, (unsigned long)i];
    return name;
}

+ (void)validatePath:(NSString *)path done:(void (^)(BOOL ok, NSString *error))done {
    void (^callback)(BOOL, NSString *) = [[done copy] autorelease];
    [[LRDaemonClient shared] validateAWGAtPath:path reply:^(NSString *reply) {
        NSString *result = LRTrim(reply);
        if ([result hasPrefix:@"VALID"]) callback(YES, nil);
        else callback(NO, result ? result : L(@"Invalid AmneziaWG profile"));
    }];
}

+ (void)addConfig:(NSString *)text name:(NSString *)name
             done:(void (^)(LRAWGProfile *profile, NSString *error))done {
    void (^callback)(LRAWGProfile *, NSString *) = [[done copy] autorelease];
    [self migrate];
    NSString *path = [self nextPath];
    NSString *config = [text hasSuffix:@"\n"] ? text : [text stringByAppendingString:@"\n"];
    if (![config writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
        callback(nil, L(@"Could not save the AmneziaWG profile"));
        return;
    }
    NSString *title = [name length] ? name : [self suggestedNameForConfig:config];
    [self validatePath:path done:^(BOOL ok, NSString *error) {
        if (!ok) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            callback(nil, error);
            return;
        }
        NSMutableDictionary *names = [self names];
        [names setObject:title forKey:[path lastPathComponent]];
        [self saveNames:names];
        LRAWGProfile *p = [self profileAtPath:path];
        [self changed];
        callback(p, nil);
    }];
}

+ (void)updateProfile:(LRAWGProfile *)profile config:(NSString *)text
                 done:(void (^)(BOOL ok, NSString *error))done {
    void (^callback)(BOOL, NSString *) = [[done copy] autorelease];
    NSString *old = [profile config];
    NSString *path = [[profile.path copy] autorelease];
    NSString *config = [text hasSuffix:@"\n"] ? text : [text stringByAppendingString:@"\n"];
    if (![config writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
        callback(NO, L(@"Could not save the AmneziaWG profile"));
        return;
    }
    [self validatePath:path done:^(BOOL ok, NSString *error) {
        if (!ok && old) [old writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        if (ok) [self changed];
        callback(ok, error);
    }];
}

+ (void)renameProfile:(LRAWGProfile *)profile to:(NSString *)name {
    NSString *n = LRTrim(name);
    if (![n length]) return;
    NSMutableDictionary *names = [self names];
    [names setObject:n forKey:[profile fileName]];
    [self saveNames:names];
    profile.name = n;
    [self changed];
}

+ (void)deleteProfile:(LRAWGProfile *)profile {
    [[NSFileManager defaultManager] removeItemAtPath:profile.path error:NULL];
    NSMutableDictionary *names = [self names];
    [names removeObjectForKey:[profile fileName]];
    [self saveNames:names];
    [self changed];
}
@end
