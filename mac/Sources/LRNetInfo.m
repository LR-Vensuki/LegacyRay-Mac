/* the os x face of app/Sources/Core/LRNetInfo.h: the primary interface from
   the system configuration store, wi-fi names through corewlan */
#import "LRNetInfo.h"
#import <SystemConfiguration/SystemConfiguration.h>
#include <dlfcn.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <netinet/in.h>

@implementation LRNetInfo

+ (SCNetworkReachabilityFlags)flags {
    struct sockaddr_in zero;
    memset(&zero, 0, sizeof zero);
    zero.sin_len = sizeof zero;
    zero.sin_family = AF_INET;
    SCNetworkReachabilityRef r = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zero);
    SCNetworkReachabilityFlags flags = 0;
    if (r) {
        SCNetworkReachabilityGetFlags(r, &flags);
        CFRelease(r);
    }
    return flags;
}

+ (BOOL)online {
    SCNetworkReachabilityFlags f = [self flags];
    return (f & kSCNetworkReachabilityFlagsReachable) &&
           !(f & kSCNetworkReachabilityFlagsConnectionRequired);
}

/* "en0", the interface the default route leaves through */
+ (NSString *)primaryInterface {
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("LegacyRay"), NULL, NULL);
    if (!store) return nil;
    NSDictionary *global = [(NSDictionary *)SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"))
                            autorelease];
    CFRelease(store);
    return [global objectForKey:@"PrimaryInterface"];
}

+ (BOOL)isWiFi:(NSString *)bsd {
    if (!bsd) return NO;
    BOOL wifi = NO;
    NSArray *all = [(NSArray *)SCNetworkInterfaceCopyAll() autorelease];
    for (id i in all) {
        SCNetworkInterfaceRef ref = (SCNetworkInterfaceRef)i;
        if (![bsd isEqualToString:(NSString *)SCNetworkInterfaceGetBSDName(ref)]) continue;
        CFStringRef type = SCNetworkInterfaceGetInterfaceType(ref);
        wifi = type && CFEqual(type, kSCNetworkInterfaceTypeIEEE80211);
        break;
    }
    return wifi;
}

+ (NSString *)interfaceKind {
    if (![self online]) return L(@"Offline");
    NSString *primary = [self primaryInterface];
    if ([self isWiFi:primary]) return @"Wi-Fi";
    if ([primary hasPrefix:@"en"]) return @"Ethernet";
    if ([primary hasPrefix:@"ppp"] || [primary hasPrefix:@"utun"] || [primary hasPrefix:@"ipsec"])
        return @"VPN";
    return primary ? primary : L(@"Network");
}

+ (NSString *)localIPv4 {
    NSString *primary = [self primaryInterface];
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return nil;
    NSString *best = nil, *any = nil;
    for (struct ifaddrs *a = list; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET || !(a->ifa_flags & IFF_UP)) continue;
        if (a->ifa_flags & IFF_LOOPBACK) continue;
        char buf[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &((struct sockaddr_in *)a->ifa_addr)->sin_addr, buf, sizeof buf);
        NSString *ip = [NSString stringWithUTF8String:buf];
        if ([ip hasPrefix:@"169.254."]) continue;
        if (primary && strcmp(a->ifa_name, [primary UTF8String]) == 0) best = ip;
        else if (!any && strncmp(a->ifa_name, "en", 2) == 0) any = ip;
    }
    freeifaddrs(list);
    return best ? best : any;
}

+ (NSString *)wifiName {
    static void *handle = NULL;
    if (!handle) handle = dlopen("/System/Library/Frameworks/CoreWLAN.framework/CoreWLAN", RTLD_LAZY);
    Class cls = NSClassFromString(@"CWInterface");
    if (!cls || ![cls respondsToSelector:@selector(interface)]) return nil;
    id wlan = [cls performSelector:@selector(interface)];
    NSString *ssid = [wlan respondsToSelector:@selector(ssid)] ? [wlan performSelector:@selector(ssid)] : nil;
    return [ssid length] ? ssid : nil;
}
@end
