// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCookie.h>

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/NSDate-OWExtensions.h>
#import <OWF/OWAddress.h>
#import <OWF/OWCookieDomain.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWHTTPProcessor.h>
#import <OWF/OWHTTPSession.h>
#import <OWF/OWNetLocation.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

NSString * const OWCookieGlobalPath = @"/";

@implementation OWCookie

// Init and dealloc

- (id)initWithDomain:(NSString *)aDomain path:(NSString *)aPath name:(NSString *)aName value:(NSString *)aValue expirationDate:(NSDate *)aDate secure:(BOOL)isSecure;
{
    if (aDomain == nil)
        aDomain = @""; // Cookie from a file URL, perhaps?
    if (aPath == nil)
        aPath = @"/";
    OBASSERT(aDomain != nil);
    OBASSERT(aPath != nil);
    OBASSERT(aName != nil);
    OBASSERT(aValue != nil);

    _domain = [[aDomain lowercaseString] copy];
    _path = [aPath copy];
    _name = [aName copy];
    _value = [aValue copy];
    _expirationDate = aDate;
    _secure = isSecure;

    return self;
}

// API

- (NSString *)domain;
{
    return _domain;
}

- (NSString *)path;
{
    return _path;
}

- (NSString *)name;
{
    return _name;
}

- (NSString *)value;
{
    return _value;
}

- (NSDate *)expirationDate;
{
    return _expirationDate;
}

- (BOOL)isExpired;
{
    // Cookies with no expiration date don't expire until the end of the
    // session.  That is, we should not write the cookie to disk.
    if (!_expirationDate)
        return NO;
        
    return [_expirationDate timeIntervalSinceNow] < 0.0;
}

- (BOOL)secure;
{
    return _secure;
}

- (NSString *)site;
{
    return _site;
}

- (void)setSite:(NSString *)aURL;
{
    if (aURL != _site) {
        _site = [aURL copy];
        _siteDomain = nil;
    }
}

- (NSString *)siteDomain;
{
    if (_siteDomain == nil) {
        if ([NSString isEmptyString:_site])
            _siteDomain = [NSString string];
        else
            _siteDomain = [[OWURL urlFromString:_site] domain];
    }

    return _siteDomain;
}

- (OWCookieStatus)status;
{
    return _status;
}

// This is the only mutability method on OWCookie.
- (void)setStatus:(OWCookieStatus)status;
{
    [self setStatus:status andNotify:YES];
}

- (void)setStatus:(OWCookieStatus)status andNotify:(BOOL)shouldNotify;
{
    _status = status;
    if (shouldNotify)
        [OWCookieDomain didChange];
}

- (BOOL)appliesToAddress:(OWAddress *)anAddress;
{
    if (_status == OWCookieRejectedStatus || [self isExpired])
        return NO;

    if ([anAddress isKindOfClass:[OWAddress class]]) {
        OWURL *url;
        OWNetLocation *netLocation;

        url = [(OWAddress *)anAddress url];
        netLocation = [url parsedNetLocation];
        if (netLocation != nil && [[netLocation hostname] hasSuffix:_domain]) {
            if ([self appliesToPath:[url fetchPath]])
                return YES;
        }
    }
    return NO;
}

- (BOOL)appliesToHostname:(NSString *)aHostname;
{
    return [aHostname hasSuffix:_domain];
}

- (BOOL)appliesToHostname:(NSString *)aHostname path:(NSString *)aPath;
{
    return [self appliesToHostname:aHostname] && [self appliesToPath:aPath];
}

- (BOOL)appliesToPath:(NSString *)aPath;
{
    BOOL applies;

    applies = [aPath hasPrefix:_path];
    
    if (OWCookiesDebug)
        NSLog(@"COOKIES: Path %@ applies to path %@ --> %d", _path, aPath, applies);

    return applies;
}

//
// Saving
//

- (void)appendXML:(OFDataBuffer *)xmlBuffer;
{
    OFDataBufferAppendCString(xmlBuffer, "  <cookie name=\"");
    OFDataBufferAppendXMLQuotedString(xmlBuffer, (__bridge CFStringRef)_name);
    
    // Only save the path if it is a non-global value (the most common case).
    if (_path != nil && ![_path isEqualToString:OWCookieGlobalPath]) {
        OFDataBufferAppendCString(xmlBuffer, "\" path=\"");
        OFDataBufferAppendXMLQuotedString(xmlBuffer, (__bridge CFStringRef)_path);
    }
    
    if (_value != nil) {
        OFDataBufferAppendCString(xmlBuffer, "\" value=\"");
        OFDataBufferAppendXMLQuotedString(xmlBuffer, (__bridge CFStringRef)_value);
    }
    if (_expirationDate != nil) {
        char string[13]; // We want to support dates through the year 9999
        NSTimeInterval expirationInterval;
        
        expirationInterval = [_expirationDate timeIntervalSinceReferenceDate];
        if (expirationInterval > 1e12 - 1) // Sep 26, 33689
            expirationInterval = 1e12 - 1; // This fits within our buffer
        snprintf(string, sizeof(string), "%.0f", expirationInterval);
        OBASSERT(strlen(string) < sizeof(string)); // Assert that we haven't overflowed our buffer
        OFDataBufferAppendCString(xmlBuffer, "\" expires=\"");
        OFDataBufferAppendCString(xmlBuffer, string);
    }
    if (_secure != NO) {
        OFDataBufferAppendCString(xmlBuffer, "\" secure=\"YES");
    }
    
    if (_site != nil) {
        OFDataBufferAppendCString(xmlBuffer, "\" receivedBySite=\"");
        OFDataBufferAppendXMLQuotedString(xmlBuffer, (__bridge CFStringRef)_site);
    }
    
    OFDataBufferAppendCString(xmlBuffer, "\" />\n");
}

- (NSComparisonResult)compare:(id)otherObject;
{
    if (![otherObject isKindOfClass:[self class]])
        return NSOrderedAscending;

    return [_name compare:[(OWCookie *)otherObject name]];
}


//
// Debugging
//

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];

    if (_domain)
        [debugDictionary setObject:_domain forKey:@"domain"];
    if (_path)
        [debugDictionary setObject:_path forKey:@"path"];
    if (_name)
        [debugDictionary setObject:_name forKey:@"name"];
    if (_value)
        [debugDictionary setObject:_value forKey:@"value"];
    if (_expirationDate)
        [debugDictionary setObject:_expirationDate forKey:@"expires"];
    [debugDictionary setObject:_secure ? @"YES" : @"NO" forKey:@"secure"];

    if (_site)
        [debugDictionary setObject:_site forKey:@"receivedBySite"];
    switch (_status) {
        case OWCookieSavedStatus:
            [debugDictionary setObject:@"accepted" forKey:@"status"];
            break;
        case OWCookieTemporaryStatus:
            [debugDictionary setObject:@"accepted for session" forKey:@"status"];
            break;
        case OWCookieRejectedStatus:
            [debugDictionary setObject:@"rejected" forKey:@"status"];
            break;
        case OWCookieUnsetStatus:
            [debugDictionary setObject:@"unset" forKey:@"status"];
            break;
    }

    return debugDictionary;
}

@end

@implementation OWCookie (NSHTTPCookie)

- (id)initWithNSCookie:(NSHTTPCookie *)nsCookie;
{
    return [self initWithDomain:[nsCookie domain] path:[nsCookie path] name:[nsCookie name] value:[nsCookie value] expirationDate:[nsCookie expiresDate] secure:[nsCookie isSecure]];
}

- (NSHTTPCookie *)nsCookie;
{
    NSMutableDictionary *cookieProperties = [[NSMutableDictionary alloc] init];
    [cookieProperties setObject:[self domain] forKey:NSHTTPCookieDomain defaultObject:nil];
    [cookieProperties setObject:[self name] forKey:NSHTTPCookieName defaultObject:nil];
    [cookieProperties setObject:[self path] forKey:NSHTTPCookiePath defaultObject:nil];
    [cookieProperties setObject:[self value] forKey:NSHTTPCookieValue defaultObject:nil];
    [cookieProperties setObject:[self expirationDate] forKey:NSHTTPCookieExpires defaultObject:nil];
    [cookieProperties setObject:([self secure] ? @"TRUE" : @"FALSE") forKey:NSHTTPCookieSecure];
    NSHTTPCookie *nsCookie = [NSHTTPCookie cookieWithProperties:cookieProperties];
    if (nsCookie == nil)
        NSLog(@"-[%@ %@]: nsCookie=%@, cookieProperties=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), nsCookie, cookieProperties);
    return nsCookie;
}

@end
