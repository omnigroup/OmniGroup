// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCookieDomain.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/NSDate-OWExtensions.h>
#import <OWF/OWAddress.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWCookiePath.h>
#import <OWF/OWCookie.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWHTTPSession.h>
#import <OWF/OWNetLocation.h>
#import <OWF/OWProcessor.h>
#import <OWF/OWSitePreference.h>
#import <OWF/OWURL.h>
#import <OWF/OWWebPipeline.h>


RCS_ID("$Id$")


static NSRecursiveLock *domainLock;
static NSMutableDictionary *domainsByName;
static OFScheduledEvent *saveEvent;

static NSCharacterSet *endNameSet, *endNameValueSet, *endValueSet, *endDateSet, *endKeySet;
static NSTimeInterval distantPastInterval;

static id classDelegate;

static NSString * const OW5CookieFileName = @"Cookies.xml";
NSString * const OWCookiesChangedNotification = @"OWCookiesChangedNotification";

NSString * const OWAcceptCookiePreferenceKey = @"OWAcceptCookies";
NSString * const OWRejectThirdPartyCookiesPreferenceKey = @"OWRejectThirdPartyCookies";
NSString * const OWExpireCookiesAtEndOfSessionPreferenceKey = @"OWExpireCookiesAtEndOfSession";

#ifdef DEBUG_len0
BOOL OWCookiesDebug = YES;
#else
BOOL OWCookiesDebug = NO;
#endif

NSString * const OWSetCookieHeader = @"set-cookie";


static inline void _locked_checkCookiesLoaded()
{
    if (!domainsByName) {
        [domainLock unlock];
        [NSException raise:NSInternalInconsistencyException format:@"Attempted to access cookies before they had been loaded."];
    }
}

@interface OWCookieDomain (PrivateAPI)
+ (void)saveCookies;
+ (NSString *)cookiePath:(NSString *)fileName;
+ (void)locked_didChange;
+ (void)notifyCookiesChanged;
- (void)addCookie:(OWCookie *)cookie andNotify:(BOOL)shouldNotify;
+ (OWCookieDomain *)domainNamed:(NSString *)name andNotify:(BOOL)shouldNotify;
- (OWCookiePath *)locked_pathNamed:(NSString *)pathName shouldCreate:(BOOL)shouldCreate;
+ (NSArray *)searchDomainsForDomain:(NSString *)aDomain;
+ (OWCookie *)cookieFromHeaderValue:(NSString *)headerValue defaultDomain:(NSString *)defaultDomain defaultPath:(NSString *)defaultPath;
- (void)locked_addApplicableCookies:(NSMutableArray *)cookies forPath:(NSString *)aPath urlIsSecure:(BOOL)secure includeRejected:(BOOL)includeRejected;
+ (BOOL)locked_readOW5Cookies;
- (id)initWithDomain:(NSString *)domain;
@end


@implementation OWCookieDomain

+ (void)initialize;
{
    OBINITIALIZE;

    domainLock = [[NSRecursiveLock alloc] init];
    
    endNameSet = [NSCharacterSet characterSetWithCharactersInString:@"=;, \t\r\n"];
    endDateSet = [NSCharacterSet characterSetWithCharactersInString:@";\r\n"];
    endNameValueSet = [NSCharacterSet characterSetWithCharactersInString:@";\r\n"];
    endValueSet = [NSCharacterSet characterSetWithCharactersInString:@"; \t\r\n"];
    endKeySet = [NSCharacterSet characterSetWithCharactersInString:@"=;, \t\r\n"];
    
    distantPastInterval = [[NSDate distantPast] timeIntervalSinceReferenceDate];
}

+ (void)didLoad;
{
    [[OFController sharedController] queueSelector:@selector(_loadCookies) forObject:(id)self whenStatus:OFControllerStatusInitialized];
    [[OFController sharedController] queueSelector:@selector(saveCookies) forObject:(id)self whenStatus:OFControllerStatusTerminating];
}

+ (void)registerCookie:(OWCookie *)newCookie fromURL:(OWURL *)url siteURL:(OWURL *)siteURL;
{
    if (newCookie == nil)
        return;

    NSString *cookieDomain = [OWSitePreference domainForURL:url];
    NSString *siteDomain = [OWSitePreference domainForURL:siteURL];
    OWCookieStatus proposedStatus;
    
    BOOL isAlienCookie = ([cookieDomain caseInsensitiveCompare:siteDomain] != NSOrderedSame);
    
    if (![[OWSitePreference preferenceForKey:OWAcceptCookiePreferenceKey domain:siteDomain] boolValue])
        proposedStatus = OWCookieRejectedStatus;
    else if (isAlienCookie && [[OWSitePreference preferenceForKey:OWRejectThirdPartyCookiesPreferenceKey domain:siteDomain] boolValue])
        proposedStatus = OWCookieRejectedStatus;
    else if ([newCookie expirationDate] == nil || [[OWSitePreference preferenceForKey:OWExpireCookiesAtEndOfSessionPreferenceKey domain:siteDomain] boolValue])
        proposedStatus = OWCookieTemporaryStatus;
    else
        proposedStatus = OWCookieSavedStatus;
    
    [newCookie setStatus:proposedStatus andNotify:NO];
    [newCookie setSite:[siteURL compositeString]];

    // The cookie itself can specify a domain, so get the domain that ends up in the actual cookie instance.
    OWCookieDomain *domain = [self domainNamed:[newCookie domain]];        
    [domain addCookie:newCookie];
}

+ (void)registerCookiesFromURL:(OWURL *)url outerContentInfos:(NSArray *)outerContentInfos headerValue:(NSString *)headerValue;
{
    NSString *defaultDomain, *defaultPath;
    OWCookie *cookie;
    OWCookieDomain *domain;
    
    if (url == nil)
        return;

    defaultDomain = [[url parsedNetLocation] hostname];
    defaultPath = @"/";

    // defaultDomain could easily be nil:  for example, this might be a file: URL
    // OBASSERT(defaultDomain != nil);

    if (OWCookiesDebug)
        NSLog(@"COOKIES: Register url=%@ domain=%@ path=%@ header=%@", [url shortDescription], defaultDomain, defaultPath, headerValue);

    cookie = [self cookieFromHeaderValue:headerValue defaultDomain:defaultDomain defaultPath:defaultPath];
    if (cookie == nil)
        return;

    NSString *cookieSite = [OWURL domainForHostname:[cookie domain]];
    
    NSUInteger contentInfoIndex = [outerContentInfos count];
    if (contentInfoIndex > 0) {
        
        while (contentInfoIndex-- > 0) {
            OWContentInfo *contentInfo = [outerContentInfos objectAtIndex:contentInfoIndex];
            OWAddress *contentInfoAddress = [contentInfo address];
            NSString *contentInfoSite = [OWSitePreference domainForAddress:contentInfoAddress];
            OWCookieStatus proposedStatus;
            
            OBASSERT(contentInfoAddress != nil);

            BOOL isAlienCookie = ([cookieSite caseInsensitiveCompare:contentInfoSite] != NSOrderedSame);

            if (![[OWSitePreference preferenceForKey:OWAcceptCookiePreferenceKey domain:contentInfoSite] boolValue])
                proposedStatus = OWCookieRejectedStatus;
            else if (isAlienCookie && [[OWSitePreference preferenceForKey:OWRejectThirdPartyCookiesPreferenceKey domain:contentInfoSite] boolValue])
                proposedStatus = OWCookieRejectedStatus;
            else if ([cookie expirationDate] == nil || [[OWSitePreference preferenceForKey:OWExpireCookiesAtEndOfSessionPreferenceKey domain:contentInfoSite] boolValue])
                proposedStatus = OWCookieTemporaryStatus;
            else
                proposedStatus = OWCookieSavedStatus;

            if ([cookie status] > proposedStatus || [cookie status] == OWCookieUnsetStatus) {
                [cookie setStatus:proposedStatus andNotify:NO];
                [cookie setSite:[contentInfoAddress addressString]];
            }
        }
    } else {
        NSString *urlSite = [OWSitePreference domainForAddress:[OWAddress addressWithURL:url]];
        OWCookieStatus proposedStatus;

        if (OWCookiesDebug)
            NSLog(@"COOKIES: url=%@, NO OUTER CONTENT INFO", [url shortDescription]);

        BOOL isAlienCookie = ([cookieSite caseInsensitiveCompare:urlSite] != NSOrderedSame);

        if (![[OWSitePreference preferenceForKey:OWAcceptCookiePreferenceKey domain:urlSite] boolValue])
            proposedStatus = OWCookieRejectedStatus;
        else if (isAlienCookie && [[OWSitePreference preferenceForKey:OWRejectThirdPartyCookiesPreferenceKey domain:urlSite] boolValue])
            proposedStatus = OWCookieRejectedStatus;
        else if ([cookie expirationDate] == nil || [[OWSitePreference preferenceForKey:OWExpireCookiesAtEndOfSessionPreferenceKey domain:urlSite] boolValue])
            proposedStatus = OWCookieTemporaryStatus;
        else
            proposedStatus = OWCookieSavedStatus;

        [cookie setStatus:proposedStatus andNotify:NO];
        [cookie setSite:[url compositeString]];
    }
    
    // The cookie itself can specify a domain, so get the domain that ends up in the actual cookie instance.
    if (OWCookiesDebug)
        NSLog(@"COOKIES: url=%@, adding cookie = %@", [url shortDescription], cookie);
        
    domain = [self domainNamed:[cookie domain]];        

    [domain addCookie:cookie];
        
    if (OWCookiesDebug)
        NSLog(@"COOKIES: Notify target of new cookie %@", cookie);
}

+ (void)registerCookiesFromURL:(OWURL *)url context:(id <OWProcessorContext>)procContext headerDictionary:(OWHeaderDictionary *)headerDictionary;
{
    NSArray *valueArray;
    NSUInteger valueIndex, valueCount;

    valueArray = [headerDictionary stringArrayForKey:OWSetCookieHeader];
    if (valueArray == nil)
	return;

    valueCount = [valueArray count];
    if (valueCount == 0)
        return;

    // These lookups are potentially expensive, so we only do them after we've found that we do actually have some cookies to register
    for (valueIndex = 0; valueIndex < valueCount; valueIndex++) {
        [self registerCookiesFromURL:url outerContentInfos:[procContext outerContentInfos] headerValue:[valueArray objectAtIndex:valueIndex]];
    }
}

+ (NSArray *)cookiesForURL:(OWURL *)url;
{
    NSString *path = [url path];
    if (path == nil)
        path = @"";
    path = [@"/" stringByAppendingString:path];

    NSString *hostname = [[[url parsedNetLocation] hostname] lowercaseString];
    NSArray *searchDomains = [self searchDomainsForDomain:hostname];

    if (OWCookiesDebug)
        NSLog(@"COOKIES: url=%@ hostname=%@, path=%@ --> domains=%@", url, hostname, path, searchDomains);

    NSMutableArray *cookies = [NSMutableArray array];
    
    [domainLock lock];
    _locked_checkCookiesLoaded();
    
    NSUInteger domainIndex, domainCount = [searchDomains count];
    for (domainIndex = 0; domainIndex < domainCount; domainIndex++) {
        NSString *searchDomain = [searchDomains objectAtIndex:domainIndex];
        OWCookieDomain *domain = [domainsByName objectForKey:searchDomain];
        [domain locked_addApplicableCookies:cookies forPath:path urlIsSecure:[url isSecure] includeRejected:NO];
    }
    
    [domainLock unlock];

    if (OWCookiesDebug)
        NSLog(@"COOKIES: -cookiesForURL:%@ --> %@", [url shortDescription], [cookies description]);

    return cookies;
}

+ (NSString *)cookieHeaderStringForURL:(OWURL *)url;
{    
    NSArray *cookies = [self cookiesForURL:url];
    if (cookies == nil)
        return nil;

    NSMutableString *cookieString = nil;
    NSUInteger cookieCount = [cookies count];
    
    for (NSUInteger cookieIndex = 0; cookieIndex < cookieCount; cookieIndex++) {
        OWCookie *cookie = [cookies objectAtIndex:cookieIndex];

        if (cookieString == nil)
            cookieString = [NSMutableString string];
        else
            [cookieString appendString:@"; "];

        NSString *cookieName = [cookie name];
        if (![NSString isEmptyString:cookieName]) {
            [cookieString appendString:cookieName];
            [cookieString appendString:@"="];
        }
        [cookieString appendString:[cookie value]];
    }
    
    return cookieString;
}

+ (BOOL)hasCookiesForSiteDomain:(NSString *)site;
{
    site = [site lowercaseString];
    NSString *dottedSite = [@"." stringByAppendingString:site];
    
    [domainLock lock];
    @try {
        NSArray *allDomains = [self allDomains];
        NSUInteger domainCount = [allDomains count];
        NSUInteger domainIndex;
        
        for (domainIndex = 0; domainIndex < domainCount; domainIndex++) {
            OWCookieDomain *domain = [allDomains objectAtIndex:domainIndex];
            NSArray *cookies = [domain cookies];
            NSUInteger cookieCount = [cookies count];
            NSUInteger cookieIndex;
            
            for (cookieIndex = 0; cookieIndex < cookieCount; cookieIndex++) {
                OWCookie *cookie = [cookies objectAtIndex:cookieIndex];
                
                if ([[cookie domain] hasSuffix:dottedSite] || [[cookie domain] isEqual:site] || [[cookie siteDomain] isEqual:site])
                    return YES;
            }
        }
    } @finally {
        [domainLock unlock];
    }
    return NO;
}

+ (NSArray *)cookiesForSiteDomain:(NSString *)site;
{
    site = [site lowercaseString];
    NSString *dottedSite = [@"." stringByAppendingString:site];
    BOOL emptySiteDomain = [NSString isEmptyString:site];
    
    NSMutableArray *cookiesForSite = [NSMutableArray array];
    NSArray *allDomains = [self sortedDomains];
    NSUInteger domainCount = [allDomains count];
    NSUInteger domainIndex;
    
    for (domainIndex = 0; domainIndex < domainCount; domainIndex++) {
        OWCookieDomain *domain = [allDomains objectAtIndex:domainIndex];
        NSArray *cookies = [domain cookies];
        NSUInteger cookieCount = [cookies count];
        NSUInteger cookieIndex;
        
        if (emptySiteDomain)
            [cookiesForSite addObjectsFromArray:cookies];
        else {
            for (cookieIndex = 0; cookieIndex < cookieCount; cookieIndex++) {
                OWCookie *cookie = [cookies objectAtIndex:cookieIndex];
                
                if ([[cookie domain] hasSuffix:dottedSite] || [[cookie domain] isEqual:site] || [[cookie siteDomain] isEqual:site])
                    [cookiesForSite addObject:cookie];
            }
        }
    }
    
    return cookiesForSite;
}

+ (void)didChange;
{
    [domainLock lock];
    [self locked_didChange];
    [domainLock unlock];
}

+ (NSArray *)allDomains;
{
    NSArray *domains;
    
    [domainLock lock];
    _locked_checkCookiesLoaded();
    
    domains = [NSArray arrayWithArray:[domainsByName allValues]];
    
    [domainLock unlock];
    
    return domains;
}

+ (NSArray *)sortedDomains;
{
    NSArray *domains;
    
    [domainLock lock];
    _locked_checkCookiesLoaded();
    
    domains = [[domainsByName allValues] sortedArrayUsingSelector:@selector(compare:)];
    
    [domainLock unlock];
    
    return domains;
}

+ (OWCookieDomain *)domainNamed:(NSString *)name;
{
    return [self domainNamed:name andNotify:YES];
}

+ (void)deleteDomain:(OWCookieDomain *)domain;
{
    [domainLock lock];
    _locked_checkCookiesLoaded();
    
    [domainsByName removeObjectForKey:[domain name]];
    [self locked_didChange];
    
    [domainLock unlock];
}

+ (void)deleteCookie:(OWCookie *)cookie;
{
    OWCookieDomain *domain;
    
    [domainLock lock];
    _locked_checkCookiesLoaded();
    
    // Its domain might have been deleted already which is why this method exists -- the caller can't call +domainNamed: and delete the cookie from there since that might recreate a deleted domain.

    domain = [domainsByName objectForKey:[cookie domain]];
    [domain removeCookie:cookie];
    
    [domainLock unlock];
}

+ (void)setDelegate:(id)delegate;
{
    classDelegate = delegate;
}

+ (id)delegate;
{
    return classDelegate;
}

- (NSString *)name;
{
    return _name;
}

- (NSString *)nameDomain;
{
    return _nameDomain;
}

- (NSString *)stringValue;
{
    return _name;
}

- (NSArray *)paths;
{
    [domainLock lock];
    NSArray *paths = [[NSArray alloc] initWithArray:_cookiePaths];
    [domainLock unlock];
    
    return paths;
}

- (OWCookiePath *)pathNamed:(NSString *)pathName;
{
    [domainLock lock];
    OWCookiePath *path = [self locked_pathNamed:pathName shouldCreate:YES];
    [domainLock unlock];
    
    return path;
}

//
// Saving
//

- (void)appendXML:(OFDataBuffer *)xmlBuffer;
{
    NSMutableArray *cookies = [NSMutableArray array];
    
    [domainLock lock];

    // The paths are not represented in the XML file (since they are usually the default and there are usually few enough cookies per path that it would be a waste.
    for (OWCookiePath *cookiePath in _cookiePaths) {
        [cookiePath addCookiesToSaveToArray:cookies];
    }
    
    // Don't archive domains with zero cookies
    if ([cookies count]) {
        OFDataBufferAppendCString(xmlBuffer, "<domain name=\"");
        // This *shouldn't* have entities in it, but ...
        OFDataBufferAppendXMLQuotedString(xmlBuffer, (__bridge CFStringRef)_name);
        OFDataBufferAppendCString(xmlBuffer, "\">\n");
        for (OWCookie *cookie in cookies) {
            [cookie appendXML:xmlBuffer];
        }
        OFDataBufferAppendCString(xmlBuffer, "</domain>\n");
    }
    
    [domainLock unlock];
}

//
// Convenience methods that loop over all the paths
//

- (void)addCookie:(OWCookie *)cookie;
{
    [self addCookie:cookie andNotify:YES];
}

- (void)removeCookie:(OWCookie *)cookie;
{
    OWCookiePath *path;
    
    [domainLock lock];
    path = [self locked_pathNamed:[cookie path] shouldCreate:NO];
    [path removeCookie:cookie];
    [domainLock unlock];
}

- (NSArray *)cookies;
{
    NSMutableArray *cookies;
    NSUInteger pathIndex, pathCount;
    
    cookies = [NSMutableArray array];
    [domainLock lock];
    pathCount = [_cookiePaths count];
    for (pathIndex = 0; pathIndex < pathCount; pathIndex++)
        [[_cookiePaths objectAtIndex:pathIndex] addNonExpiredCookiesToArray:cookies usageIsSecure:YES includeRejected:YES];
    [domainLock unlock];
    
    return cookies;
}

- (NSComparisonResult)compare:(id)otherObject;
{
    if ([otherObject class] != [self class])
        return NSOrderedAscending;

    NSString *otherNameDomain = [(OWCookieDomain *)otherObject nameDomain];
    NSComparisonResult domainComparisonResult = [_nameDomain compare:otherNameDomain];
    if (domainComparisonResult == NSOrderedSame)
        return [_name compare:[(OWCookieDomain *)otherObject name]];
    else
        return domainComparisonResult;
}

//
//  NSCopying protocol (so this can go in table view columns like in the OW cookies inspector)
//

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

#pragma mark - OWCookieDomain (PrivateAPI)

+ (void)_loadCookies;
{
    [domainLock lock];
    
    domainsByName = [[NSMutableDictionary alloc] init];
    
    // Read the cookies
    NS_DURING {
        [self locked_readOW5Cookies];
    } NS_HANDLER {
        NSLog(@"Exception raised while reading cookies: %@", localException);
    } NS_ENDHANDLER;
    
    [domainLock unlock];
    
    if (OWCookiesDebug)
        NSLog(@"COOKIES: Read cookies");
}

+ (void)saveCookies;
{
    NSString *cookieFilename;
    NSArray *domains;
    OFDataBuffer xmlBuffer;
    NSUInteger domainIndex, domainCount;
    NSDictionary *attributes;
    
    // This must get executed in the main thread so that the notification gets posted in the main thread (since that is where the cookie preferences panel is listening).
    OBPRECONDITION([NSThread isMainThread]);

    if (OWCookiesDebug)
        NSLog(@"COOKIES: Saving");

    if (!(cookieFilename = [self cookiePath:OW5CookieFileName])) {
        if (OWCookiesDebug)
            NSLog(@"COOKIES: Unable to compute cookie path");
        return;
    }

    [domainLock lock];
    
    saveEvent = nil;
    
    OFDataBufferInit(&xmlBuffer);
#warning TJW -- I still need to write a DTD for this file and put it on our web site
    OFDataBufferAppendCString(&xmlBuffer,
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    "<!DOCTYPE OmniWebCookies SYSTEM \"http://www.omnigroup.com/DTDs/OmniWeb5Cookies.dtd\">\n"
    "<OmniWebCookies>\n");

    domains = [[domainsByName allValues] sortedArrayUsingSelector:@selector(compare:)];
    domainCount = [domains count];
    for (domainIndex = 0; domainIndex < domainCount; domainIndex++)
        [(OWCookieDomain *)[domains objectAtIndex:domainIndex] appendXML:&xmlBuffer];

    OFDataBufferAppendCString(&xmlBuffer, "</OmniWebCookies>\n");

    // Cookies must only be readable by the owner since they can contain
    // security sensitive information
    attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithUnsignedLong:0600], NSFilePosixPermissions,
            nil];
            
    OFDataBufferFlush(&xmlBuffer);
    CFDataRef xmlDataRef;
    OFDataBufferRelease(&xmlBuffer, NULL, &xmlDataRef);
    NSData *xmlData = CFBridgingRelease(xmlDataRef);

    if (![[NSFileManager defaultManager] atomicallyCreateFileAtPath:cookieFilename contents:xmlData attributes:attributes]) {
#warning TJW: There is not currently any good way to pop up a panel telling the user that they need to check the file permissions for a particular path.
        NSLog(@"Unable to save cookies to %@", cookieFilename);
    }

    [domainLock unlock];
}

+ (NSString *)cookiePath:(NSString *)fileName;
{
    NSString *directory = [[[NSUserDefaults standardUserDefaults] objectForKey:@"OWLibraryDirectory"] stringByStandardizingPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory;
    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory)
        return nil;

    return [directory stringByAppendingPathComponent:fileName];
}

+ (void)locked_didChange;
{
    OFScheduler *mainScheduler = [OFScheduler mainScheduler];
    
    // Kill the old scheduled event and schedule one for later
    if (saveEvent) {
        [mainScheduler abortEvent:saveEvent];
    }

    saveEvent = [mainScheduler scheduleSelector:@selector(saveCookies) onObject:self withObject:nil afterTime:60.0];

    if (OWCookiesDebug)
        NSLog(@"COOKIES: Did change, saveEvent = %@", saveEvent);
        
    [self queueSelectorOnce:@selector(notifyCookiesChanged)];
}

+ (void)notifyCookiesChanged;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OWCookiesChangedNotification object:nil];
}

+ (OWCookieDomain *)domainNamed:(NSString *)name andNotify:(BOOL)shouldNotify;
{
    [domainLock lock];
    _locked_checkCookiesLoaded();

    OWCookieDomain *domain = [domainsByName objectForKey:name];
    if (domain == nil) {
        domain = [[self alloc] initWithDomain:name];
        [domainsByName setObject:domain forKey:name];
        if (shouldNotify)
            [self locked_didChange];
    }
    
    [domainLock unlock];
    
    return domain;
}

- (void)addCookie:(OWCookie *)cookie andNotify:(BOOL)shouldNotify;
{
    [domainLock lock];
    OWCookiePath *path = [self locked_pathNamed:[cookie path] shouldCreate:YES];
    [path addCookie:cookie andNotify:shouldNotify];
    [domainLock unlock];
}

- (OWCookiePath *)locked_pathNamed:(NSString *)pathName shouldCreate:(BOOL)shouldCreate;
{
    [domainLock lock];

    OWCookiePath *path;

    NSUInteger pathIndex = [_cookiePaths count];
    while (pathIndex--) {
        path = [_cookiePaths objectAtIndex:pathIndex];
        if ([[path path] isEqualToString:pathName]) {
            goto found;
        }
    }

    if (shouldCreate) {
        path = [[OWCookiePath alloc] initWithPath:pathName];
        [_cookiePaths insertObject:path inArraySortedUsingSelector:@selector(compare:)];
    } else
        path = nil;

found:
    [domainLock unlock];
    
    return path;
}

+ (NSArray *)searchDomainsForDomain:(NSString *)aDomain;
{
    if (aDomain == nil)
        return nil;

    NSMutableArray *domainComponents = [[aDomain componentsSeparatedByString:@"."] mutableCopy];
    NSUInteger domainComponentCount = [domainComponents count];
    NSUInteger minimumDomainComponents = [OWURL minimumDomainComponentsForDomainComponents:domainComponents];
    NSMutableArray *searchDomains = [NSMutableArray arrayWithCapacity:domainComponentCount];
    [searchDomains addObject:[@"." stringByAppendingString:aDomain]];
    [searchDomains addObject:aDomain];
    // Apple sets localhost cookie domains to "localhost.local"
    if (domainComponentCount == 1)
        [searchDomains addObject:[NSString stringWithFormat:@"%@.local", aDomain]];
    if (domainComponentCount < minimumDomainComponents) {
	return searchDomains;
    }
    domainComponentCount -= minimumDomainComponents;
    while (domainComponentCount--) {
	[domainComponents removeObjectAtIndex:0];
	NSString *searchDomain = [domainComponents componentsJoinedByString:@"."];
	[searchDomains addObject:[@"." stringByAppendingString:searchDomain]];
    }
    return searchDomains;
}

+ (OWCookie *)cookieFromHeaderValue:(NSString *)headerValue defaultDomain:(NSString *)defaultDomain defaultPath:(NSString *)defaultPath;
{
    NSScanner *scanner = [NSScanner scannerWithString:headerValue];

    NSString *aName;
    if (![scanner scanUpToCharactersFromSet:endNameSet intoString:&aName])
        aName = [NSString string];
    
    if (![scanner scanString:@"=" intoString:NULL])
        return nil;

    // Scan the value if possible
    NSString *aValue;
    if ([scanner scanUpToCharactersFromSet:endNameValueSet intoString:&aValue]) {
        NSUInteger valueLength;
        // Remove trailing whitespace
        // This could be more efficient.  (Actually, this whole method could be more efficient:  we should rewrite it using OFStringScanner.)

        valueLength = [aValue length];
        do {
            unichar character;
            
            character = [aValue characterAtIndex:valueLength - 1];
            if (character == ' ' || character == '\t')
                valueLength--;
            else
                break;
        } while (valueLength > 0);
        aValue = [aValue substringToIndex:valueLength];
    } else {
        // If there are no characters, treat it as an empty string.
        aValue = [NSString string];
    }

    [scanner scanCharactersFromSet:endKeySet intoString:NULL];

    NSDate *aDate = nil;
    NSString *aDomain = defaultDomain;
    NSString *aPath = defaultPath;
    BOOL isSecure = NO;
    
    NSString *aKey;
    while ([scanner scanUpToCharactersFromSet:endKeySet intoString:&aKey]) {
        aKey = [aKey lowercaseString];
        [scanner scanString:@"=" intoString:NULL];
        if ([aKey isEqualToString:@"expires"]) {
            NSString *dateString = nil;

            [scanner scanUpToCharactersFromSet:endDateSet intoString:&dateString];
            if (dateString) {
                aDate = [NSDate dateWithHTTPDateString:dateString];
                if (!aDate) {
                    NSCalendarDate *yearFromNowDate;

                    NSLog(@"OWCookie: could not parse expiration date, expiring cookie in one year");
                    yearFromNowDate = [[NSCalendarDate calendarDate] dateByAddingYears:1 months:0 days:0 hours:0 minutes:0 seconds:0];
                    [yearFromNowDate setCalendarFormat:[OWHTTPSession preferredDateFormat]];
                    aDate = yearFromNowDate;
                }
            }
        } else if ([aKey isEqualToString:@"domain"]) {
            [scanner scanUpToCharactersFromSet:endValueSet intoString:&aDomain];
            if (aDomain != nil) {
                NSArray *domainComponents;
                NSUInteger domainComponentCount;
                
                //if the domain and the default domain are not identical(nytimes.com vs www.nytimes.com), there needs to be a '.' at the beginning
                if(defaultDomain != nil && ![aDomain isEqualToString:defaultDomain] && ![aDomain hasPrefix:@"."])
                    aDomain = [NSString stringWithFormat:@".%@",aDomain];
                
                domainComponents = [aDomain componentsSeparatedByString:@"."];
                domainComponentCount = [domainComponents count];
                if (domainComponentCount > 0 && [[domainComponents objectAtIndex:0] isEqualToString:@""]) {
                    // ".co.uk" -> ("", "co", "uk"):  we shouldn't count that initial empty component
                    domainComponentCount--;
                }

                if (OWCookiesDebug)
                    NSLog(@"COOKIES: domainComponents = %@, minimum = %lu", domainComponents, [OWURL minimumDomainComponentsForDomainComponents:domainComponents]);

                if (defaultDomain && (![[@"." stringByAppendingString:defaultDomain] hasSuffix:aDomain] || domainComponentCount < [OWURL minimumDomainComponentsForDomainComponents:domainComponents])) {
                    // Sorry, you can't create cookies for other domains, nor can you create cookies for "com" or "co.uk".  Make sure that we allow for the case where there is no default domain (file: urls, for example).
                    aDomain = defaultDomain;
                }
            }
        } else if ([aKey isEqualToString:@"path"]) {
            if (![scanner scanUpToCharactersFromSet:endValueSet intoString:&aPath]) {
                // Some deranged people specify an empty string for the path. Assume they really meant "/" (not the default path, which is more limiting).
                aPath = @"/";
            }
        } else if ([aKey isEqualToString:@"secure"]) {
            isSecure = YES;
        }
        [scanner scanCharactersFromSet:endKeySet intoString:NULL];
    }
        
    return [[OWCookie alloc] initWithDomain:aDomain path:aPath name:aName value:aValue expirationDate:aDate secure:isSecure];
}

- (void)locked_addApplicableCookies:(NSMutableArray *)cookies forPath:(NSString *)aPath urlIsSecure:(BOOL)secure includeRejected:(BOOL)includeRejected;
{
    for (OWCookiePath *path in _cookiePaths) {
        if ([path appliesToPath:aPath]) {
            [path addNonExpiredCookiesToArray:cookies usageIsSecure:secure includeRejected:includeRejected];
        }
    }
}

//
// OW5 XML Cookie file parsing
//

static NSString *OWCookiesElementName = @"OmniWebCookies";

+ (BOOL)locked_readOW5Cookies;
{
    @autoreleasepool {
        
        NSString *filename = [self cookiePath:OW5CookieFileName];
        if (filename == nil)
            return NO;
        
        NSData *cookieData = [NSData dataWithContentsOfFile:filename];
        if (cookieData == nil || [cookieData length] == 0)
            return NO;
        
        OFXMLWhitespaceBehavior *whitespaceBehavior = [[OFXMLWhitespaceBehavior alloc] init];
        [whitespaceBehavior setBehavior:OFXMLWhitespaceBehaviorTypeIgnore forElementName:OWCookiesElementName];
        OFXMLDocument *document = [[OFXMLDocument alloc] initWithData:cookieData whitespaceBehavior:whitespaceBehavior error:NULL];
        
        // Read domains
        OFXMLCursor *domainCursor = [document cursor];
        OFXMLElement *domainElement;
        while ((domainElement = [domainCursor nextChild]) != nil) {
            OBASSERT([domainElement isKindOfClass:[OFXMLElement class]]);
            
            // Domain name
            NSString *domainName = [domainElement attributeNamed:@"name"];
            if ([NSString isEmptyString:domainName])
                continue;
            
            // Create domain
            OWCookieDomain *domain = [OWCookieDomain domainNamed:domainName andNotify:NO];
            
            // Read children
            NSArray *children = [domainElement children];
            
            for (OFXMLElement *cookieElement in children) {
                OBASSERT([cookieElement isKindOfClass:[OFXMLElement class]]);
                
                NSString *name = [cookieElement attributeNamed:@"name"];
                NSString *path = [cookieElement attributeNamed:@"path"];
                NSString *value = [cookieElement attributeNamed:@"value"];
                NSString *expiresString = [cookieElement attributeNamed:@"expires"];
                NSDate *expires = expiresString != nil ? [NSDate dateWithTimeIntervalSinceReferenceDate:[expiresString doubleValue]] : nil;
                BOOL secure = [[cookieElement attributeNamed:@"secure"] boolValue];
                NSString *site = [cookieElement attributeNamed:@"receivedBySite"];
                
                OWCookie *cookie = [[OWCookie alloc] initWithDomain:[domain name] path:path name:name value:value expirationDate:expires secure:secure];
                [cookie setStatus:OWCookieSavedStatus andNotify:NO];
                [cookie setSite:site];
                
                [domain addCookie:cookie andNotify:NO];
            }

        }
        
    }
    
    return YES;
}

- (id)initWithDomain:(NSString *)domain;
{
    self = [super init];
    if (self == nil)
        return nil;

    _name = [domain copy];
    _nameDomain = [OWURL domainForHostname:_name];
    _cookiePaths = [[NSMutableArray alloc] init];
    
    return self;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    [debugDictionary setObject:_name forKey:@"name"];
    [debugDictionary setObject:_cookiePaths forKey:@"cookiePaths"];
    return debugDictionary;
}

@end
