// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFDataBuffer.h>

@class NSConditionLock, NSDate, NSHTTPCookie;
@class OWAddress;

#import <CoreFoundation/CFPropertyList.h>

extern NSString * const OWCookieGlobalPath;

typedef enum _OWCookieStatus {
    OWCookieUnsetStatus = 0,
    OWCookieSavedStatus = 1,
    OWCookieTemporaryStatus = 2,
    OWCookieRejectedStatus = 3,
} OWCookieStatus;

@interface OWCookie : OFObject
{
    NSString *_domain;
    NSString *_path;
    NSString *_name;
    NSString *_value;
    NSDate *_expirationDate;
    BOOL _secure;

    NSString *_site;
    NSString *_siteDomain;
    OWCookieStatus _status;
}

- (id)initWithDomain:(NSString *)aDomain path:(NSString *)aPath name:(NSString *)aName value:(NSString *)aValue expirationDate:(NSDate *)aDate secure:(BOOL)isSecure;

- (NSString *)domain;
- (NSString *)path;
- (NSString *)name;
- (NSString *)value;
- (NSDate *)expirationDate;
- (BOOL)secure;

- (NSString *)site;
- (void)setSite:(NSString *)aURL;
    // Should only call this before registering as it doesn't notify of changes.

- (NSString *)siteDomain;
- (OWCookieStatus)status;
- (void)setStatus:(OWCookieStatus)status;
- (void)setStatus:(OWCookieStatus)status andNotify:(BOOL)shouldNotify;

// Cookies without expiration dates last until the end of the session.
// Cookies with expiration dates in the past expire immediately.
// So expiration is not as simple as it might be expected.
- (BOOL)isExpired;

- (BOOL)appliesToAddress:(OWAddress *)anAddress;
- (BOOL)appliesToHostname:(NSString *)aHostname;
- (BOOL)appliesToHostname:(NSString *)aHostname path:(NSString *)aPath;
- (BOOL)appliesToPath:(NSString *)fetchPath;

//
// Saving
//
- (void)appendXML:(OFDataBuffer *)xmlBuffer;

@end

@interface OWCookie (NSHTTPCookie)
- (id)initWithNSCookie:(NSHTTPCookie *)nsCookie;
- (NSHTTPCookie *)nsCookie;
@end
