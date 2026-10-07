#import "LRHelperInstaller.h"
#import "LRAlert.h"
#import "LRActivityLog.h"
#include "senko_paths.h"
#import <Security/Security.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

@implementation LRHelperInstaller

+ (NSString *)installedVersion {
    return LRTrim([NSString stringWithContentsOfFile:@SENKO_HELPER_VERSION encoding:NSUTF8StringEncoding
                                               error:NULL]);
}

+ (NSString *)bundledVersion {
    NSString *p = [[[NSBundle mainBundle] bundlePath]
                   stringByAppendingPathComponent:@"Contents/Helpers/VERSION"];
    return LRTrim([NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL]);
}

+ (LRHelperState)state {
    /* development: a legacyrayd started by hand stands in for the installed
       one (defaults write com.legacyray.mac LRDeveloperNoHelper -bool YES) */
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"LRDeveloperNoHelper"]) return LRHelperReady;
    if (access(SENKO_USR_BIN "/legacyrayd", X_OK) != 0 ||
        access(SENKO_LAUNCH_DAEMONS "/com.legacyray.daemon.plist", R_OK) != 0)
        return LRHelperMissing;
    NSString *have = [self installedVersion], *want = [self bundledVersion];
    if (want && ![want isEqualToString:have]) return LRHelperOutdated;
    /* the data folder belongs to whoever installed; another account cannot
       drive the daemon until it is handed over */
    struct stat st;
    if (stat(SENKO_DATA_DIR, &st) != 0 || st.st_uid != getuid()) return LRHelperOutdated;
    /* setuid lost (a copy by hand, a restore) */
    if (stat(SENKO_USR_BIN "/legacyray-kick", &st) != 0 || !(st.st_mode & S_ISUID) || st.st_uid != 0)
        return LRHelperOutdated;
    return LRHelperReady;
}

/* runs Contents/Helpers/legacyray-install as root with the arguments; the
   output is the script's, the answer comes on the main thread */
+ (void)runPrivileged:(NSArray *)arguments prompt:(NSString *)prompt
                 done:(void (^)(BOOL ok, NSString *error))done {
    void (^callback)(BOOL, NSString *) = [[done copy] autorelease];
    NSString *tool = [[[NSBundle mainBundle] bundlePath]
                      stringByAppendingPathComponent:@"Contents/Helpers/legacyray-install"];
    if (access([tool fileSystemRepresentation], X_OK) != 0) {
        if (callback) callback(NO, L(@"The app bundle is incomplete: legacyray-install is missing."));
        return;
    }
    AuthorizationRef auth = NULL;
    OSStatus st = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (st != errAuthorizationSuccess) {
        if (callback) callback(NO, [NSString stringWithFormat:@"AuthorizationCreate %d", (int)st]);
        return;
    }
    const char *toolPath = [tool fileSystemRepresentation];
    AuthorizationItem right = { kAuthorizationRightExecute, strlen(toolPath), (void *)toolPath, 0 };
    AuthorizationRights rights = { 1, &right };
    const char *promptText = [prompt UTF8String];
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"LegacyRay" ofType:@"icns"];
    const char *icon = iconPath ? [iconPath fileSystemRepresentation] : NULL;
    AuthorizationItem envItems[2];
    UInt32 envCount = 0;
    if (promptText) {
        envItems[envCount].name = kAuthorizationEnvironmentPrompt;
        envItems[envCount].valueLength = strlen(promptText);
        envItems[envCount].value = (void *)promptText;
        envItems[envCount].flags = 0;
        envCount++;
    }
    if (icon) {
        envItems[envCount].name = kAuthorizationEnvironmentIcon;
        envItems[envCount].valueLength = strlen(icon);
        envItems[envCount].value = (void *)icon;
        envItems[envCount].flags = 0;
        envCount++;
    }
    AuthorizationEnvironment env = { envCount, envItems };
    LRActivateApp();
    st = AuthorizationCopyRights(auth, &rights, &env,
                                 kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights |
                                 kAuthorizationFlagPreAuthorize, NULL);
    if (st == errAuthorizationCanceled) {
        AuthorizationFree(auth, kAuthorizationFlagDefaults);
        if (callback) callback(NO, nil);
        return;
    }
    if (st != errAuthorizationSuccess) {
        AuthorizationFree(auth, kAuthorizationFlagDefaults);
        if (callback) callback(NO, [NSString stringWithFormat:L(@"Authorization failed (%d)."), (int)st]);
        return;
    }
    NSArray *args = [[arguments copy] autorelease];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        char *argv[8] = { NULL };
        NSUInteger n = MIN([args count], (NSUInteger)7);
        for (NSUInteger i = 0; i < n; ++i) argv[i] = (char *)[[args objectAtIndex:i] UTF8String];
        FILE *pipe = NULL;
        OSStatus run = AuthorizationExecuteWithPrivileges(auth, toolPath, kAuthorizationFlagDefaults,
                                                          argv, &pipe);
        NSMutableString *output = [NSMutableString string];
        if (run == errAuthorizationSuccess && pipe) {
            char line[512];
            while (fgets(line, sizeof line, pipe)) {
                NSString *s = [NSString stringWithUTF8String:line];
                if (s) [output appendString:s];
            }
            /* the trampoline stays a zombie until the app quits: reaping it
               with wait() could take a child another part of the app (an
               ssh job, legacyray-kick) is waiting for by pid */
            fclose(pipe);
        }
        AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
        BOOL ok = run == errAuthorizationSuccess && [output rangeOfString:@"legacyray-install: ok"].location != NSNotFound;
        if (!ok && run == errAuthorizationSuccess &&
            ([output rangeOfString:@"still starting"].location != NSNotFound ||
             [output rangeOfString:@"legacyray-install: removed"].location != NSNotFound))
            ok = YES;
        NSString *err = nil;
        if (!ok) {
            NSArray *lines = [LRTrim(output) componentsSeparatedByString:@"\n"];
            err = [lines count] && LRTrim([lines lastObject]) ? [lines lastObject]
                : [NSString stringWithFormat:L(@"The installer did not finish (%d)."), (int)run];
            err = [err stringByReplacingOccurrencesOfString:@"legacyray-install: " withString:@""];
        }
        [err retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (callback) callback(ok, err);
            [err release];
        });
        [pool drain];
    });
}

+ (void)installNow:(void (^)(BOOL, NSString *))done {
    NSString *uid = [NSString stringWithFormat:@"%u", (unsigned)getuid()];
    NSArray *args = [NSArray arrayWithObjects:@"install", [[NSBundle mainBundle] bundlePath], uid, nil];
    void (^callback)(BOOL, NSString *) = [[done copy] autorelease];
    [self runPrivileged:args prompt:L(@"LegacyRay wants to install its network helper.")
                   done:^(BOOL ok, NSString *error) {
        if (ok) LRLog(@"helper", @"helper %@ installed", [self bundledVersion]);
        else if (error) LRLogFail(@"helper", @"helper install failed: %@", error);
        if (callback) callback(ok, error);
    }];
}

+ (void)installExplaining:(BOOL)explain done:(void (^)(BOOL, NSString *))done {
    void (^callback)(BOOL, NSString *) = [[done copy] autorelease];
    if (!explain) {
        [self installNow:callback];
        return;
    }
    LRHelperState state = [self state];
    NSString *title = state == LRHelperMissing ? L(@"Install the Network Helper")
                                               : L(@"Update the Network Helper");
    NSString *message = state == LRHelperMissing
        ? L(@"LegacyRay routes the traffic of this Mac through a small background service that runs as the system. Installing it once needs an administrator password. It goes to /usr/local/legacyray and can be removed from Preferences > Advanced.")
        : L(@"The background service on this Mac belongs to another version of LegacyRay or to another account. Updating it needs an administrator password; servers and settings stay in place.");
    [LRAlert runTitle:title message:message
              buttons:[NSArray arrayWithObjects:state == LRHelperMissing ? L(@"Install") : L(@"Update"),
                       L(@"Cancel"), nil]
            accessory:nil window:nil done:^(NSInteger index) {
        if (index != 0) {
            if (callback) callback(NO, nil);
            return;
        }
        [LRHelperInstaller installNow:callback];
    }];
}

+ (void)uninstallPurging:(BOOL)purge done:(void (^)(BOOL, NSString *))done {
    NSArray *args = purge ? [NSArray arrayWithObjects:@"uninstall", @"--purge", nil]
                          : [NSArray arrayWithObject:@"uninstall"];
    [self runPrivileged:args prompt:L(@"LegacyRay wants to remove its network helper.") done:done];
}
@end
