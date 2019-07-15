// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFDataBuffer.h>

@class NSArray, NSLock, NSMutableArray;
@class OWAddress, OWContentInfo, OWCookie, OWCookiePath, OWHeaderDictionary, OWURL;
@protocol OWProcessorContext;

extern BOOL OWCookiesDebug;
extern NSString * const OWSetCookieHeader;

extern NSString * const OWAcceptCookiePreferenceKey;
extern NSString * const OWRejectThirdPartyCookiesPreferenceKey;
extern NSString * const OWExpireCookiesAtEndOfSessionPreferenceKey;

@interface OWCookieDomain : OFObject <NSCopying>
{
    NSString *_name;
    NSString *_nameDomain;
    NSMutableArray *_cookiePaths;
}

+ (void)registerCookie:(OWCookie *)aCookie fromURL:(OWURL *)url siteURL:(OWURL *)siteURL;
+ (void)registerCookiesFromURL:(OWURL *)url outerContentInfos:(NSArray *)outerContentInfos headerValue:(NSString *)headerValue;
+ (void)registerCookiesFromURL:(OWURL *)url context:(id <OWProcessorContext>)processorContext headerDictionary:(OWHeaderDictionary *)headerDictionary;

+ (NSArray *)cookiesForURL:(OWURL *)url;
+ (NSString *)cookieHeaderStringForURL:(OWURL *)url;
+ (BOOL)hasCookiesForSiteDomain:(NSString *)site;
+ (NSArray *)cookiesForSiteDomain:(NSString *)site;

+ (void)didChange;

+ (NSArray *)allDomains;
+ (NSArray *)sortedDomains;
+ (OWCookieDomain *)domainNamed:(NSString *)name;
+ (void)deleteDomain:(OWCookieDomain *)domain;
+ (void)deleteCookie:(OWCookie *)cookie;

+ (void)setDelegate:(id)delegate;
+ (id)delegate;

- (NSString *)name;
- (NSString *)stringValue;
    // These two methods return the same thing.

- (NSArray *)paths;
- (OWCookiePath *)pathNamed:(NSString *)name;

//
// Saving
//
- (void)appendXML:(OFDataBuffer *)xmlBuffer;

//
// Convenience methods that find the right path.
//
- (void)addCookie:(OWCookie *)cookie;
- (void)removeCookie:(OWCookie *)cookie;
- (NSArray *)cookies;

@end


extern NSString * const OWCookiesChangedNotification;
    // Posted when cookie data has changed.
