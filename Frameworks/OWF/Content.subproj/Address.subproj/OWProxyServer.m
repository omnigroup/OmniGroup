// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWProxyServer.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWNetLocation.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@interface OWProxyServer (Private)
+ (void)_startMonitoringProxySettings;
+ (void)_updateProxySettingsFromDictionary:(NSDictionary *)dictionary;
+ (void)_setProxySettingsDictionary:(NSDictionary *)newDictionary;
+ (NSDictionary *)_proxySettingsDictionary;
+ (OWURL *)_proxyURLWithHost:(NSString *)proxyHost port:(unsigned int)proxyPort;
@end

static NSLock *_proxySettingsDictionaryLock = nil;
static NSDictionary *_proxySettingsDictionary = nil;
static NSString *OWProxiesExceptionsListKey = @"ExceptionsList";
static NSString *OWProxiesFTPPassiveModeKey = @"PassiveFTP";

@implementation OWProxyServer

+ (void)initialize;
{
    OBINITIALIZE;

    _proxySettingsDictionaryLock = [[NSLock alloc] init];
    [self mainThreadPerformSelector:@selector(_startMonitoringProxySettings)];
}

+ (OWURL *)proxyURLForURL:(OWURL *)aURL;
{
    NSDictionary *proxySettingsDictionary;
    OWURL *proxyURL;
    NSArray *proxyExceptions;
    OWNetLocation *urlNetLocation;
    NSString *urlHostname;

    // Look up the proxy server for the URL's scheme
    proxySettingsDictionary = [self _proxySettingsDictionary];
    proxyURL = [proxySettingsDictionary objectForKey:[aURL scheme]];
    if (proxyURL == nil)
        return aURL; // No proxy server for this scheme

    // Check whether we should bypass the proxy settings for this URL's hostname
    urlNetLocation = [aURL parsedNetLocation];
    urlHostname = [[urlNetLocation hostname] lowercaseString];

    if ([urlHostname isEqualToString:@"localhost"])
        return aURL; // Never proxy localhost, as it always means something different to the proxy server

    // Is this host listed in the proxy exception list?
    proxyExceptions = [proxySettingsDictionary objectForKey:OWProxiesExceptionsListKey];
    if (proxyExceptions != nil && [proxyExceptions count] != 0) {
        for (NSString *proxyException in proxyExceptions) {
            if ([urlHostname hasSuffix:proxyException])
                return aURL; // The hostname matches the proxy exception list, so don't proxy it
        }
    }

    // Return the proxy server's URL
    return proxyURL;
}

+ (BOOL)usePassiveFTP
{
    NSDictionary *settings = [self _proxySettingsDictionary];

    return [settings boolForKey:OWProxiesFTPPassiveModeKey defaultValue:YES];
}

@end

#define SCSTR(s) (NSString *)CFSTR(s)
#import <SystemConfiguration/SystemConfiguration.h>

@implementation OWProxyServer (Private)

static void OWProxyServerDynamicStoreCallBack(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info);

+ (void)_startMonitoringProxySettings;
{
    OBPRECONDITION([NSThread isMainThread]);

    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, (CFStringRef)[[NSProcessInfo processInfo] processName], OWProxyServerDynamicStoreCallBack, NULL);
    NSString *proxiesKey = CFBridgingRelease(SCDynamicStoreKeyCreateProxies(NULL));
    if (!SCDynamicStoreSetNotificationKeys(store, (CFArrayRef)@[proxiesKey], nil))
        NSLog(@"SCDynamicStoreSetNotificationKeys() failed: %s", SCErrorString(SCError()));

    NSDictionary *proxySettingsDictionary = CFBridgingRelease(SCDynamicStoreCopyValue(store, (__bridge CFStringRef)proxiesKey));
    [self _updateProxySettingsFromDictionary:proxySettingsDictionary];

    CFRunLoopSourceRef runLoopSource = SCDynamicStoreCreateRunLoopSource(NULL, store, 0);
    CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();
#ifdef DEBUG_kc0
    NSLog(@"+[%@ %s], runLoopSource=%@, currentRunLoop=%@", OBShortObjectDescription(self), _cmd, runLoopSource, currentRunLoop);
#endif
    if (runLoopSource != NULL && currentRunLoop != NULL)
        CFRunLoopAddSource(currentRunLoop, runLoopSource, kCFRunLoopDefaultMode);
    if (runLoopSource)
        CFRelease(runLoopSource);
}

+ (void)_updateProxySettingsFromDictionary:(NSDictionary *)dictionary;
{
    NSMutableDictionary *newProxySettingsDictionary;
    NSArray *exceptionsList;

    if (![dictionary isKindOfClass:[NSDictionary class]])
        return;

    // Build a new proxy settings dictionary
    newProxySettingsDictionary = [[NSMutableDictionary alloc] init];
    if ([dictionary boolForKey:(NSString *)kSCPropNetProxiesFTPEnable defaultValue:NO]) {
        OWURL *proxyURL;

        proxyURL = [self _proxyURLWithHost:[dictionary objectForKey:(NSString *)kSCPropNetProxiesFTPProxy] port:[dictionary intForKey:(NSString *)kSCPropNetProxiesFTPPort defaultValue:80]];
        [newProxySettingsDictionary setObject:proxyURL forKey:@"ftp"];
    }
    if ([dictionary objectForKey:(NSString *)kSCPropNetProxiesFTPPassive] != nil) {
        [newProxySettingsDictionary setBoolValue:[dictionary boolForKey:(NSString *)kSCPropNetProxiesFTPPassive defaultValue:YES] forKey:OWProxiesFTPPassiveModeKey];
    }
    if ([dictionary boolForKey:(NSString *)kSCPropNetProxiesGopherEnable defaultValue:NO]) {
        OWURL *proxyURL;

        proxyURL = [self _proxyURLWithHost:[dictionary objectForKey:(NSString *)kSCPropNetProxiesGopherProxy] port:[dictionary intForKey:(NSString *)kSCPropNetProxiesGopherPort defaultValue:80]];
        [newProxySettingsDictionary setObject:proxyURL forKey:@"gopher"];
    }
    if ([dictionary boolForKey:(NSString *)kSCPropNetProxiesHTTPEnable defaultValue:NO]) {
        OWURL *proxyURL;

        proxyURL = [self _proxyURLWithHost:[dictionary objectForKey:(NSString *)kSCPropNetProxiesHTTPProxy] port:[dictionary intForKey:(NSString *)kSCPropNetProxiesHTTPPort defaultValue:80]];
        [newProxySettingsDictionary setObject:proxyURL forKey:@"http"];
    }
    if ([dictionary boolForKey:(NSString *)kSCPropNetProxiesHTTPSEnable defaultValue:NO]) {
        OWURL *proxyURL;

        proxyURL = [self _proxyURLWithHost:[dictionary objectForKey:(NSString *)kSCPropNetProxiesHTTPSProxy] port:[dictionary intForKey:(NSString *)kSCPropNetProxiesHTTPSPort defaultValue:80]];
        [newProxySettingsDictionary setObject:proxyURL forKey:@"https"];
    }
    exceptionsList = [dictionary objectForKey:(NSString *)kSCPropNetProxiesExceptionsList];
    if (exceptionsList)
        [newProxySettingsDictionary setObject:exceptionsList forKey:OWProxiesExceptionsListKey];

    [self _setProxySettingsDictionary:newProxySettingsDictionary];
}

+ (void)_setProxySettingsDictionary:(NSDictionary *)newDictionary;
{
    [_proxySettingsDictionaryLock lock];
    _proxySettingsDictionary = [[NSDictionary alloc] initWithDictionary:newDictionary];
    [_proxySettingsDictionaryLock unlock];
}

+ (NSDictionary *)_proxySettingsDictionary;
{
    NSDictionary *proxySettingsDictionary;

    [_proxySettingsDictionaryLock lock];
    proxySettingsDictionary = _proxySettingsDictionary;
    [_proxySettingsDictionaryLock unlock];
    return proxySettingsDictionary;
}

+ (OWURL *)_proxyURLWithHost:(NSString *)proxyHost port:(unsigned int)proxyPort;
{
#define HTTPS_PORT 443

    return [OWURL urlWithScheme:proxyPort == HTTPS_PORT ? @"https" : @"http" netLocation:[NSString stringWithFormat:@"%@:%d", proxyHost, proxyPort] path:nil params:nil query:nil fragment:nil];
}

static void OWProxyServerDynamicStoreCallBack(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info)
{
#ifdef DEBUG_kc
    NSLog(@"OWProxyServerDynamicStoreCallBack(): changedKeys=%@", [(__bridge NSArray *)changedKeys description]);
#endif

    NSUInteger changedKeyCount = CFArrayGetCount(changedKeys);
    if (changedKeyCount == 0)
        return; // I'm not sure why they've called us since there are no changed keys, but I have seen this happen

    OBASSERT(changedKeyCount == 1); // We've only registered for one key
    CFStringRef proxiesKey = SCDynamicStoreKeyCreateProxies(NULL);
    NSDictionary *proxySettingsDictionary = CFBridgingRelease(SCDynamicStoreCopyValue(store, proxiesKey));
    CFRelease(proxiesKey);
    [OWProxyServer _updateProxySettingsFromDictionary:proxySettingsDictionary];
}

@end
