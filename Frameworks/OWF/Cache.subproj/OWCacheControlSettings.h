// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class /* Foundation */ NSDate, NSNumber;
@class /* OmniFoundation */ OFMultiValueDictionary;
@class /* OWF */ OWHeaderDictionary;

#import <Foundation/NSDate.h> // For NSTimeInterval

@interface OWCacheControlSettings : OFObject
{
@public
    // Information from the server (pretty much HTTP-only)
    NSDate *serverDate;      // The server's clock, should be the same as ours (in theory...)
    NSNumber *ageAtFetch;    // Cache's indication of age
    NSNumber *maxAge;        // Maximum age to allow the content to reach
    NSDate *explicitExpire;  // Explicit expiration date provided by server or processor
                             // NSArray *unCachedHeaders;  // parameters of Cache-Control: no-cache="foo"  (currently unused)

    BOOL noCache;            // [2616 14.9.1] Response shouldn't be used without revalidation
    BOOL noStore;            // [2616 14.9.2] Response is "sensitive" and shouldn't be written to disk
    BOOL mustRevalidate;     // [2616 14.9.4] Reusing stale content is extra-bad for this arc.
}

+ (OWCacheControlSettings *)cacheSettingsForHeaderDictionary:(OWHeaderDictionary *)headerDictionary;
+ (OWCacheControlSettings *)cacheSettingsForMultiValueDictionary:(OFMultiValueDictionary *)headerDictionary;
+ (OWCacheControlSettings *)cacheSettingsWithNoCache;
+ (OWCacheControlSettings *)cacheSettingsWithMaxAgeInterval:(NSTimeInterval)seconds;

- (void)setServerDate:(NSDate *)newDate;
- (void)setAgeAtFetch:(NSNumber *)newNumber;
- (void)setMaxAge:(NSNumber *)newNumber;
- (void)setExpirationDate:(NSDate *)newDate;

- (void)addHeaders:(OFMultiValueDictionary *)headerDictionary;
- (void)addSettings:(OWCacheControlSettings *)moreSettings;

- (BOOL)mightExpireWithinTimeInterval:(NSTimeInterval)timeInterval;
    // When we see an HTTP-EQUIV meta tag in HTML, we call this method to determine whether we might need to flush the cached HTML page.

@end
