#import "LRSSH.h"
#include "senko_paths.h"
#import "LRActivityLog.h"
#import <spawn.h>
#import <sys/wait.h>
#import <signal.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>
#include "b64.h"

extern char **environ;

NSString * const LRServerHostsDidChangeNotification = @"LRServerHostsDidChangeNotification";

#define LR_SSH_BIN   SENKO_USR_BIN "/legacyray-ssh"
#define LR_HOSTS     @SENKO_SSH_HOSTS

static NSString *LRB64(NSString *text) {
    NSData *d = [text dataUsingEncoding:NSUTF8StringEncoding];
    size_t cap = b64_encoded_maxlen([d length]) + 1;
    char *out = malloc(cap);
    size_t n = 0;
    NSString *s = nil;
    if (out && b64_encode([d bytes], [d length], out, cap, &n) == 0)
        s = [[[NSString alloc] initWithBytes:out length:n encoding:NSASCIIStringEncoding] autorelease];
    free(out);
    return s ? s : @"";
}

NSString *LRSSHFingerprint(NSString *hash) {
    NSString *h = hash;
    while ([h hasSuffix:@"="]) h = [h substringToIndex:[h length] - 1];
    return [@"SHA256:" stringByAppendingString:h ? h : @""];
}

@implementation LRServerHost
@synthesize ident = _ident, name = _name, host = _host, port = _port, user = _user, auth = _auth,
            secret = _secret, passphrase = _passphrase, hostKey = _hostKey, hostKeyType = _hostKeyType,
            hasXray = _hasXray, hasAWG = _hasAWG;

- (void)dealloc {
    [_ident release]; [_name release]; [_host release]; [_user release];
    [_secret release]; [_passphrase release]; [_hostKey release]; [_hostKeyType release];
    [super dealloc];
}

- (NSString *)displayName {
    return [_name length] ? _name : [NSString stringWithFormat:@"%@@%@", _user, _host];
}

- (NSDictionary *)dictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (_ident) [d setObject:_ident forKey:@"id"];
    if (_name) [d setObject:_name forKey:@"name"];
    if (_host) [d setObject:_host forKey:@"host"];
    [d setObject:[NSNumber numberWithInteger:_port] forKey:@"port"];
    if (_user) [d setObject:_user forKey:@"user"];
    [d setObject:[NSNumber numberWithInt:_auth] forKey:@"auth"];
    if (_secret) [d setObject:_secret forKey:@"secret"];
    if (_passphrase) [d setObject:_passphrase forKey:@"passphrase"];
    if (_hostKey) [d setObject:_hostKey forKey:@"hostkey"];
    if (_hostKeyType) [d setObject:_hostKeyType forKey:@"hostkeytype"];
    [d setObject:[NSNumber numberWithBool:_hasXray] forKey:@"xray"];
    [d setObject:[NSNumber numberWithBool:_hasAWG] forKey:@"awg"];
    return d;
}

+ (LRServerHost *)hostWithDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    LRServerHost *h = [[[LRServerHost alloc] init] autorelease];
    h.ident = [d objectForKey:@"id"];
    h.name = [d objectForKey:@"name"];
    h.host = [d objectForKey:@"host"];
    h.port = [[d objectForKey:@"port"] integerValue] ?: 22;
    h.user = [d objectForKey:@"user"];
    h.auth = (LRSSHAuth)[[d objectForKey:@"auth"] intValue];
    h.secret = [d objectForKey:@"secret"];
    h.passphrase = [d objectForKey:@"passphrase"];
    h.hostKey = [d objectForKey:@"hostkey"];
    h.hostKeyType = [d objectForKey:@"hostkeytype"];
    h.hasXray = [[d objectForKey:@"xray"] boolValue];
    h.hasAWG = [[d objectForKey:@"awg"] boolValue];
    return h.host ? h : nil;
}
@end

@implementation LRServerHosts

+ (NSArray *)hosts {
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *d in [NSArray arrayWithContentsOfFile:LR_HOSTS]) {
        LRServerHost *h = [LRServerHost hostWithDictionary:d];
        if (h) [list addObject:h];
    }
    return list;
}

+ (void)store:(NSArray *)hosts {
    NSMutableArray *out = [NSMutableArray array];
    for (LRServerHost *h in hosts) [out addObject:[h dictionary]];
    [[NSFileManager defaultManager] createDirectoryAtPath:[LR_HOSTS stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [out writeToFile:LR_HOSTS atomically:YES];
    /* sign-in details: readable by this user only */
    chmod([LR_HOSTS fileSystemRepresentation], 0600);
    [[NSNotificationCenter defaultCenter] postNotificationName:LRServerHostsDidChangeNotification object:nil];
}

+ (void)save:(LRServerHost *)host {
    if (!host.ident) host.ident = [NSString stringWithFormat:@"%.0f", [NSDate timeIntervalSinceReferenceDate] * 1000];
    NSMutableArray *list = [NSMutableArray array];
    BOOL replaced = NO;
    for (LRServerHost *h in [self hosts]) {
        if ([h.ident isEqualToString:host.ident]) { [list addObject:host]; replaced = YES; }
        else [list addObject:h];
    }
    if (!replaced) [list addObject:host];
    [self store:list];
}

+ (void)remove:(LRServerHost *)host {
    NSMutableArray *list = [NSMutableArray array];
    for (LRServerHost *h in [self hosts]) if (![h.ident isEqualToString:host.ident]) [list addObject:h];
    [self store:list];
}
@end

@implementation LRSSHJob

- (void)dealloc {
    if (_out >= 0) close(_out);
    [super dealloc];
}

- (void)cancel {
    _cancelled = YES;
    if (_pid > 0) kill(_pid, SIGTERM);
}

/* the values that reach the shell: nothing that could leave a quoted word */
static BOOL LRSafeValue(NSString *v) {
    static NSCharacterSet *bad = nil;
    if (!bad) bad = [[[NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:"] invertedSet] retain];
    return [v length] && [v length] < 128 && [v rangeOfCharacterFromSet:bad].location == NSNotFound;
}

+ (NSString *)scriptFor:(NSString *)command vars:(NSDictionary *)vars {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"lr-server" ofType:@"sh" inDirectory:@"server"];
    NSString *body = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
    if (!body || !LRSafeValue(command)) return nil;
    NSMutableString *s = [NSMutableString stringWithFormat:@"LR_CMD='%@'\n", command];
    for (NSString *k in vars) {
        NSString *v = [[vars objectForKey:k] description];
        if (!LRSafeValue(k) || !LRSafeValue(v)) return nil;
        [s appendFormat:@"%@='%@'\n", k, v];
    }
    [s appendString:body];
    return s;
}

- (BOOL)startWithInput:(NSString *)input host:(LRServerHost *)host {
    int in[2], out[2];
    if (pipe(in) != 0) return NO;
    if (pipe(out) != 0) { close(in[0]); close(in[1]); return NO; }
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, in[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&fa, out[1], STDOUT_FILENO);
    posix_spawn_file_actions_addopen(&fa, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addclose(&fa, in[1]);
    posix_spawn_file_actions_addclose(&fa, out[0]);
    char port[16];
    snprintf(port, sizeof port, "%ld", (long)(host.port > 0 ? host.port : 22));
    char *argv[] = { (char *)LR_SSH_BIN, (char *)[host.host UTF8String], port,
                     (char *)[(host.user ? host.user : @"root") UTF8String], NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, LR_SSH_BIN, &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    close(in[0]);
    close(out[1]);
    if (rc != 0) { close(in[1]); close(out[0]); return NO; }
    _pid = pid;
    _out = out[0];
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    int fd = in[1];
    /* the request can be tens of kilobytes; write it off the main thread */
    [data retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        const char *p = [data bytes];
        size_t left = [data length];
        signal(SIGPIPE, SIG_IGN);
        while (left) {
            ssize_t w = write(fd, p, left);
            if (w < 0 && errno == EINTR) continue;
            if (w <= 0) break;
            p += w; left -= (size_t)w;
        }
        close(fd);
        [data release];
    });
    return YES;
}

/* read the helper's lines until it exits; line and done run on the main queue */
- (void)pumpWithLine:(void (^)(NSString *raw))line done:(void (^)(int status))done {
    int fd = _out;
    _out = -1;
    pid_t pid = _pid;
    void (^onLine)(NSString *) = [[line copy] autorelease];
    void (^onDone)(int) = [[done copy] autorelease];
    [self retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableData *pending = [NSMutableData data];
        char buf[4096];
        for (;;) {
            ssize_t n = read(fd, buf, sizeof buf);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) break;
            [pending appendBytes:buf length:(NSUInteger)n];
            const char *b = [pending bytes];
            NSUInteger len = [pending length], start = 0;
            NSMutableArray *lines = [NSMutableArray array];
            for (NSUInteger i = 0; i < len; ++i) {
                if (b[i] != '\n') continue;
                NSString *s = [[[NSString alloc] initWithBytes:b + start length:i - start
                                                      encoding:NSUTF8StringEncoding] autorelease];
                if (s) [lines addObject:s];
                start = i + 1;
            }
            if (start) [pending replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
            if ([lines count])
                dispatch_async(dispatch_get_main_queue(), ^{ for (NSString *l in lines) onLine(l); });
        }
        close(fd);
        int status = 0;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
        dispatch_async(dispatch_get_main_queue(), ^{
            onDone(code);
            [self release];
        });
    });
}

+ (NSString *)authLineFor:(LRServerHost *)host {
    if (host.auth == LRSSHAuthKey) {
        NSString *line = [NSString stringWithFormat:@"AUTH key %@", LRB64(host.secret ? host.secret : @"")];
        if ([host.passphrase length]) line = [line stringByAppendingFormat:@" %@", LRB64(host.passphrase)];
        return line;
    }
    return [NSString stringWithFormat:@"AUTH password %@", LRB64(host.secret ? host.secret : @"")];
}

+ (void)probeKeyOf:(LRServerHost *)host
              done:(void (^)(NSString *, NSString *, NSString *))done {
    void (^callback)(NSString *, NSString *, NSString *) = [[done copy] autorelease];
    LRSSHJob *job = [[[LRSSHJob alloc] init] autorelease];
    job->_out = -1;
    NSString *input = [NSString stringWithFormat:@"%@\nHOSTKEY -\nRUN -\n", [self authLineFor:host]];
    if (![job startWithInput:input host:host]) {
        callback(nil, nil, L(@"legacyray-ssh is missing: reinstall the package"));
        return;
    }
    __block NSString *type = nil, *hash = nil, *error = nil;
    [job pumpWithLine:^(NSString *raw) {
        if ([raw hasPrefix:@"HOSTKEY "]) {
            NSArray *w = [raw componentsSeparatedByString:@" "];
            if ([w count] >= 3) {
                [type release]; type = [[w objectAtIndex:1] copy];
                [hash release]; hash = [[w objectAtIndex:2] copy];
            }
        } else if ([raw hasPrefix:@"FAIL "]) {
            [error release]; error = [[raw substringFromIndex:5] copy];
        }
    } done:^(int status) {
        callback([type autorelease], [hash autorelease],
                 hash ? nil : ([error autorelease] ?: L(@"The server did not answer")));
    }];
}

+ (LRSSHJob *)run:(NSString *)command vars:(NSDictionary *)vars on:(LRServerHost *)host
             line:(LRSSHLineBlock)line done:(void (^)(BOOL, NSString *))done {
    LRSSHLineBlock onLine = [[line copy] autorelease];
    void (^callback)(BOOL, NSString *) = [[done copy] autorelease];
    NSString *script = [self scriptFor:command vars:vars];
    if (!script || ![host.hostKey length]) {
        callback(NO, script ? L(@"The server's key was never confirmed") : L(@"A name contains characters that are not allowed"));
        return nil;
    }
    LRSSHJob *job = [[[LRSSHJob alloc] init] autorelease];
    job->_out = -1;
    NSString *input = [NSString stringWithFormat:@"%@\nHOSTKEY %@\nRUN %@\n",
                       [self authLineFor:host], host.hostKey, LRB64(script)];
    if (![job startWithInput:input host:host]) {
        callback(NO, L(@"legacyray-ssh is missing: reinstall the package"));
        return nil;
    }
    LRLog(@"server", @"%@ on a saved server", command);
    __block NSString *error = nil;
    __block BOOL finished = NO;
    [job pumpWithLine:^(NSString *raw) {
        if ([raw hasPrefix:@"OUT LR-"] || [raw hasPrefix:@"ERR LR-"]) {
            NSString *rest = [raw substringFromIndex:7];
            NSRange sp = [rest rangeOfString:@" "];
            NSString *kind = sp.location == NSNotFound ? rest : [rest substringToIndex:sp.location];
            NSString *text = sp.location == NSNotFound ? @"" : [rest substringFromIndex:sp.location + 1];
            if ([kind isEqualToString:@"ERROR"]) { [error release]; error = [text copy]; }
            if ([kind isEqualToString:@"DONE"]) finished = YES;
            if (onLine) onLine(kind, text);
        } else if ([raw hasPrefix:@"OUT "] || [raw hasPrefix:@"ERR "]) {
            if (onLine) onLine([raw substringToIndex:3], [raw substringFromIndex:4]);
        } else if ([raw hasPrefix:@"FAIL "]) {
            [error release];
            error = [[raw substringFromIndex:5] copy];
        } else if ([raw hasPrefix:@"STAGE "] && onLine) {
            onLine(@"STAGE", [raw substringFromIndex:6]);
        }
    } done:^(int status) {
        NSString *why = [error autorelease];
        BOOL ok = status == 0 && finished && !why;
        if (!ok && !why) why = status == 3 ? L(@"The server's host key changed. Remove the server and add it again only if you expected this.")
                                          : L(@"The command did not finish");
        if (!ok) LRLogFail(@"server", @"%@ failed", command);
        callback(ok, ok ? nil : why);
    }];
    return job;
}
@end
