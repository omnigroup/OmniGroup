// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCookiePath.h>

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWCookie.h>
#import <OWF/OWCookieDomain.h>

RCS_ID("$Id$")


static NSLock *pathLock = nil;

@implementation OWCookiePath

+ (void)initialize;
{
    OBINITIALIZE;        
    pathLock = [[NSLock alloc] init];
}

- initWithPath:(NSString *)aPath;
{
    if (!(self = [super init]))
        return nil;

    _path = [aPath copy];
    _cookies = [[NSMutableArray alloc] init];
    
    return self;
}

- (NSString *)path;
{
    return _path;
}

- (BOOL)appliesToPath:(NSString *)aPath;
{
    BOOL applies;

    applies = [aPath hasPrefix:_path];
    
    if (OWCookiesDebug)
        NSLog(@"COOKIES: Path %@ applies to path %@ --> %d", _path, aPath, applies);

    return applies;
}

- (void)addCookie:(OWCookie *)cookie;
{
    [self addCookie:cookie andNotify:YES];
}

- (void)removeCookie:(OWCookie *)cookie;
{
    NSUInteger index;
    
    [pathLock lock];
    index = [_cookies indexOfObjectIdenticalTo:cookie];
    if (index != NSNotFound)
        [_cookies removeObjectAtIndex:index];
    [pathLock unlock];
    
    if (index != NSNotFound)
        [OWCookieDomain didChange];
}

- (NSArray *)cookies;
{
    [pathLock lock];
    NSArray *cookies = [[NSArray alloc] initWithArray:_cookies];
    [pathLock unlock];
    
    return cookies;
}

- (OWCookie *)cookieNamed:(NSString *)name;
{
    OWCookie *cookie = nil;
    BOOL found = NO;
    
    [pathLock lock];

    NSUInteger cookieIndex = [_cookies count];
    while (cookieIndex--) {
        cookie = [_cookies objectAtIndex:cookieIndex];
        if ([[cookie name] isEqualToString:name]) {
            found = YES;
            break;
        }
    }

    [pathLock unlock];
    
    if (found)
        return cookie;
    return nil;
}

// For use by OWCookieDomain
- (void)addCookie:(OWCookie *)cookie andNotify:(BOOL)shouldNotify;
{
    // We block cookies here instead of marking them rejected in OWCookie domain because we don't want users to have to manually clear out their rejected cookies (or Quit/Restart OmniWeb) -- The whole point of Private Browsing is to prevent that!
    if ([[OFPreference preferenceForKey:@"OWPrivateBrowsingEnabled"] boolValue]) {
        OBRetainAutorelease(cookie); // In case someone adds the cookie with the expectation that it will be retained
        return;
    }
    
    NSString *name = [cookie name];
    BOOL needsAdding = YES;

    [pathLock lock];
    
    // If we have a cookie with the same name, replace it.
    NSUInteger cookieIndex = [_cookies count];
    while (cookieIndex--) {
        OWCookie *oldCookie = [_cookies objectAtIndex:cookieIndex];
        
        // Don't remove and readd the cookie if it is already there
        // since it might get deallocated.
        if (oldCookie == cookie) {
            needsAdding = NO;
            break;
        }
        
        if ([[oldCookie name] isEqualToString:name]) {
            // Replace the old cookie value but preserve the current status
            // if it is more permissive than the new status
            
            OWCookieStatus oldStatus = [oldCookie status];
            
            // If the new cookie has no expirationDate, only promote it to
            // saved if the old cookie also had no expiration date.
            if ([cookie expirationDate] == nil && oldStatus == OWCookieSavedStatus && [oldCookie expirationDate] != nil)
                oldStatus = OWCookieTemporaryStatus;
            
            if ([cookie status] > oldStatus) {
                [cookie setStatus:oldStatus andNotify:NO];
                // When preserving a more permissive old status, also preserve
                // the site that determined that status
                [cookie setSite:[oldCookie site]];
            }
            [_cookies replaceObjectAtIndex:cookieIndex withObject:cookie];
            needsAdding = NO;
            break;
        }
    }
    
    if (needsAdding) {
        [_cookies addObject:cookie];
    }
    
    [pathLock unlock];
    
    if (shouldNotify) {
        [OWCookieDomain didChange];
        // Should become obsolete with new cache arc validation stuff
#warning deal with cache validation of cookie state
        //        [OWContentCache flushCachedContentMatchingCookie:cookie];
    }
}

- (void)addNonExpiredCookiesToArray:(NSMutableArray *)array usageIsSecure:(BOOL)secure includeRejected:(BOOL)includeRejected;
{
    [pathLock lock];
    
    for (OWCookie *cookie in _cookies) {
        if ([cookie isExpired])
            continue;
        if ([cookie secure] && !secure)
            continue;
        if (!includeRejected && [cookie status] == OWCookieRejectedStatus)
            continue;
        [array addObject:cookie];
    }
    
    [pathLock unlock];
}

- (void)addCookiesToSaveToArray:(NSMutableArray *)array;
{
    [pathLock lock];

    for (OWCookie *cookie in _cookies) {
        if ([cookie isExpired])
            continue;
        if ([cookie status] != OWCookieSavedStatus)
            continue;
        [array addObject:cookie];
    }

    [pathLock unlock];
}

- (NSComparisonResult)compare:(id)otherObject;
{
    if (![otherObject isKindOfClass:[self class]])
        return NSOrderedAscending;
    
    return [_path compare:[(OWCookiePath *)otherObject path]];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict;
    
    dict = [super debugDictionary];
    [dict setObject:_path forKey:@"path"];
    [dict setObject:_cookies forKey:@"cookies"];
    
    return dict;
}

@end

