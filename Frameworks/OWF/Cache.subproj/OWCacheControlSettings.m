// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCacheControlSettings.h>

#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFMultiValueDictionary.h>

#import <OWF/NSDate-OWExtensions.h>
#import <OWF/OWHeaderDictionary.h>

RCS_ID("$Id$")

@implementation OWCacheControlSettings

+ (OWCacheControlSettings *)cacheSettingsForHeaderDictionary:(OWHeaderDictionary *)headerDictionary;
{
    return [self cacheSettingsForMultiValueDictionary:[headerDictionary dictionarySnapshot]];
}

+ (OWCacheControlSettings *)cacheSettingsForMultiValueDictionary:(OFMultiValueDictionary *)headerDictionary;
{
    OWCacheControlSettings *newSettings = [[self alloc] init];
    [newSettings addHeaders:headerDictionary];
    return newSettings;
}

+ (OWCacheControlSettings *)cacheSettingsWithNoCache;
{
    static OWCacheControlSettings *cachedSettings = nil;

    if (cachedSettings == nil) {
        cachedSettings = [[OWCacheControlSettings alloc] init];
        cachedSettings->noCache = YES;
    }
    return cachedSettings;
}

+ (OWCacheControlSettings *)cacheSettingsWithMaxAgeInterval:(NSTimeInterval)seconds;
{
    OWCacheControlSettings *newSettings = [[OWCacheControlSettings alloc] init];
    [newSettings setMaxAge:[NSNumber numberWithDouble:(double)seconds]];
    return newSettings;
}

- (void)setServerDate:(NSDate *)newDate;
{
    serverDate = newDate;
}

- (void)setAgeAtFetch:(NSNumber *)newNumber;
{
    ageAtFetch = newNumber;
}

- (void)setMaxAge:(NSNumber *)newNumber;
{
    maxAge = newNumber;
}

- (void)setExpirationDate:(NSDate *)newDate;
{
    explicitExpire = newDate;
}

//

- (void)addHeaders:(OFMultiValueDictionary *)headerDictionary;
{
    NSString *headerText;
    NSArray *cacheControl, *pragmata;
    NSUInteger directiveCount, directiveIndex;
    BOOL hasCacheControl;
    //    NSMutableArray *unCachedHeaders;

    [self setServerDate:[NSDate dateWithHTTPDateString:[headerDictionary lastObjectForKey:@"date"]]];
    [self setExpirationDate:[NSDate dateWithHTTPDateString:[headerDictionary lastObjectForKey:@"expires"]]];

    headerText = [headerDictionary lastObjectForKey:@"age"];
    if (![NSString isEmptyString:headerText]) {
        NSNumber *givenAge = [headerText numberValue];
        if (givenAge != nil) {
            [self setAgeAtFetch:givenAge];
        }
    }

    cacheControl = [headerDictionary arrayForKey:@"cache-control"];
    if (!cacheControl || ![cacheControl count])
        hasCacheControl = NO;
    else {
        hasCacheControl = YES;
        cacheControl = [OWHeaderDictionary splitHeaderValues:cacheControl];
    }
    pragmata = [OWHeaderDictionary splitHeaderValues:[headerDictionary arrayForKey:@"pragma"]];
    //    unCachedHeaders = [[NSMutableArray alloc] init];

    directiveCount = [cacheControl count];
    for(directiveIndex = 0; directiveIndex < directiveCount; directiveIndex ++) {
        NSString *cacheDirective = [cacheControl objectAtIndex:directiveIndex];
        NSString *token, *parameter;
        NSRange equalsRange;

        equalsRange = [cacheDirective rangeOfString:@"="];
        if (equalsRange.length == 0) {
            token = cacheDirective;
            parameter = nil;
        } else {
            NSRange openQuote, closeQuote;
            NSRange valueRange;

            // Trim off surrounding whitespace, and optionally the quotes
            token = [cacheDirective substringToIndex:equalsRange.location];
            parameter = [cacheDirective substringFromIndex:NSMaxRange(equalsRange)];
            parameter = [parameter stringByRemovingSurroundingWhitespace];
            openQuote = [parameter rangeOfString:@"\"" options:NSAnchoredSearch];
            closeQuote = [parameter rangeOfString:@"\"" options:NSAnchoredSearch|NSBackwardsSearch];
            if (openQuote.length != 0 && closeQuote.length != 0 &&
                openQuote.length <= closeQuote.location) {
                OBASSERT(openQuote.location == 0);
                OBASSERT(NSMaxRange(closeQuote) == [parameter length]);

                valueRange.location = NSMaxRange(openQuote);
                valueRange.length = closeQuote.location - valueRange.location;
                parameter = [parameter substringWithRange:valueRange];
            }
        }
        token = [token stringByRemovingSurroundingWhitespace];
#define TokenIs(token, value) ([(token) compare:(value) options:NSCaseInsensitiveSearch] == NSOrderedSame)

        if (TokenIs(token, @"max-age")) {
            [self setMaxAge:[parameter numberValue]];
        } else if (TokenIs(token, @"no-cache")) {
            noCache = YES;
            //            if (parameter != nil)
            //                [unCachedHeaders addObject:parameter];
        } else if (TokenIs(token, @"no-store")) {
            noStore = YES;
        } else if (TokenIs(token, @"must-revalidate")) {
            mustRevalidate = YES;
        }

#undef TokenIs
    };

    // The only pragma we recognize is Pragma: no-cache, which we treat identically to Cache-control: no-cache.
    if ([pragmata indexOfString:@"no-cache" options:NSCaseInsensitiveSearch] != NSNotFound) {
        noCache = YES;
    }

    // HTTP/1.0 cache control compatibility hack: see RFC2616 14.9.3 paragraph 3
    if (serverDate != nil && explicitExpire != nil &&
        [serverDate compare:explicitExpire] != NSOrderedAscending &&
        !hasCacheControl) {
        noCache = YES;
    }

#if 0
    if ([unCachedHeaders count] == 0) {
        [unCachedHeaders release];
        unCachedHeaders = nil;
    } else {
        unCachedHeaders = [unCachedHeaders autorelease];
    }
#endif
}

- (void)addSettings:(OWCacheControlSettings *)moreSettings;
{
    if (moreSettings->serverDate != nil)
        [self setServerDate:moreSettings->serverDate];

    if (moreSettings->ageAtFetch != nil)
        [self setAgeAtFetch:moreSettings->ageAtFetch];

    if (moreSettings->maxAge != nil)
        [self setMaxAge:moreSettings->maxAge];

    if (moreSettings->explicitExpire != nil)
        [self setExpirationDate:moreSettings->explicitExpire];
/*
    if (moreSettings->unCachedHeaders != nil)
        [self setUncachedHeaders:moreSettings->unCachedHeaders];
*/

    if (moreSettings->noCache)
        noCache = YES;

    if (moreSettings->noStore)
        noStore = YES;

    if (moreSettings->mustRevalidate)
        mustRevalidate = YES;
}

- (BOOL)mightExpireWithinTimeInterval:(NSTimeInterval)timeInterval;
{
    if (noCache)
        return YES;
    if (noStore)
        return YES;
    if (mustRevalidate)
        return YES;
    if (maxAge != nil && [maxAge floatValue] < timeInterval)
        return YES;
    if (explicitExpire != nil && [explicitExpire timeIntervalSinceNow] < timeInterval)
        return YES;

    return NO;
}

@end
