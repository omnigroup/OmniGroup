// Copyright 2003-2005, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWSitePreference.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWAddress.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$");

NSString *OWSitePreferenceDidChangeNotification = @"OWSitePreferenceDidChangeNotification";

@interface OWSitePreference (Private)
+ (NSMutableDictionary *)_lockedPreferenceCacheForDomain:(NSString *)domain;
- (id)_initWithKey:(NSString *)key domain:(NSString *)domain;
- (OFPreference *)_preferenceForReading;
- (OFPreference *)_preferenceForWriting;
@end

@implementation OWSitePreference

static NSMutableDictionary *domainCache = nil;
static NSLock *domainLock = nil;
static NSNotificationCenter *sitePreferenceNotificationCenter;

//#define DEBUG_SITE_PREFERENCES

+ (void)initialize;
{
    OBINITIALIZE;

    domainCache = [[NSMutableDictionary alloc] init];
    domainLock = [[NSLock alloc] init];
    
    sitePreferenceNotificationCenter = [[NSNotificationCenter alloc] init];
    
    NSDictionary *defaultsDictionary = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    
    for (NSString *key in defaultsDictionary) {
        // The key should be in the format SiteSpecific:www.domain.com:PreferenceKey
        NSArray *components = [key componentsSeparatedByString:@":"];
        NSUInteger componentCount = [components count];
        if (componentCount < 3)
            continue; // Three colon-delimited components is the minimum.  There can be more in the case where the customized page had no domain, and so the full URL was used instead

        if (![[components objectAtIndex:0] isEqualToString:@"SiteSpecific"])
            continue;

        NSString *domain;
        NSString *defaultKey;
        if (componentCount == 3) {
            domain = [components objectAtIndex:1];
            defaultKey = [components objectAtIndex:2];
        } else {
            OBASSERT(componentCount > 3); // <= 3 is already handled above
            domain = [[components subarrayWithRange:NSMakeRange(1, componentCount - 2)] componentsJoinedByString:@":"];
            defaultKey = [components lastObject];
        }
                
        // Ensure that this default is in the cache
        [self preferenceForKey:defaultKey domain:domain];
    }
}

+ (void)addObserver:(id)anObserver selector:(SEL)aSelector forSitePreference:(OWSitePreference *)aSitePreference;
{
    [sitePreferenceNotificationCenter addObserver:anObserver selector:aSelector name:OWSitePreferenceDidChangeNotification object:aSitePreference];
}

+ (void)removeObserver:(id)anObserver forSitePreference:(OWSitePreference *)aSitePreference;
{
    [sitePreferenceNotificationCenter removeObserver:anObserver name:OWSitePreferenceDidChangeNotification object:aSitePreference];
}

+ (NSString *)domainForAddress:(OWAddress *)address;
{
    return [self domainForURL:[address url]];
}

+ (NSString *)domainForURL:(OWURL *)url;
{
    if (url == nil)
        return @"";
    
    // Get the domain.  If there is no domain (as on a synthetic URL such as omniweb:/StartPage/), just use the scheme
    NSString *domain = [url domain];
    if ([NSString isEmptyString:domain])
        domain = [url scheme];
    
    return domain;
}

+ (OWSitePreference *)preferenceForKey:(NSString *)key domain:(NSString *)domain;
{
    NSMutableDictionary *preferenceCache;
    OWSitePreference *preference;
    
    OBASSERT(domain != nil);

    [domainLock lock];
    preferenceCache = [self _lockedPreferenceCacheForDomain:domain];
    preference = [[preferenceCache objectForKey:key] retain];
    if (preference == nil) {
        preference = [[OWSitePreference alloc] _initWithKey:key domain:domain];
        [preferenceCache setObject:preference forKey:key];
    }
    [domainLock unlock];

    return [preference autorelease];
}

+ (OWSitePreference *)preferenceForKey:(NSString *)key address:(OWAddress *)address;
{
    return [self preferenceForKey:key domain:[self domainForAddress:address]];
}

+ (NSDictionary *)domainCache;
{
    NSDictionary *domainCacheSnapshot;
    
    [domainLock lock];
    domainCacheSnapshot = [NSDictionary dictionaryWithDictionary:domainCache];
    [domainLock unlock];
    
    return domainCacheSnapshot;
}

+ (BOOL)siteHasPreferences:(OWAddress *)address;
{
    NSString *domain;
    NSDictionary *preferenceCache;
    NSArray *allValues;
    NSUInteger valueCount, valueIndex;
    
    domain = [self domainForAddress:address];
    if (domain == nil) {
#ifdef DEBUG_SITE_PREFERENCES
        NSLog(@"%s, address=<%@>, no domain!", _cmd, [address addressString]);
#endif        
        return NO;
    }
        
    [domainLock lock];
    preferenceCache = [self _lockedPreferenceCacheForDomain:domain];
    allValues = [preferenceCache allValues];
    [domainLock unlock];
    valueCount = [allValues count];

#ifdef DEBUG_SITE_PREFERENCES
    NSLog(@"%s, domain=\"%@\", %d preferences set", _cmd, domain, valueCount);
#endif    

    for (valueIndex = 0; valueIndex < valueCount; valueIndex++) {
        OWSitePreference *preference;

        preference = [allValues objectAtIndex:valueIndex];
        if ([preference hasNonDefaultValue])
            return YES;
    }

#ifdef DEBUG_SITE_PREFERENCES
    NSLog(@"%s, domain=\"%@\", all preferences have default values", _cmd, domain);
#endif

    return NO;
}

+ (void)resetPreferencesForDomain:(NSString *)domain;
{
    OBFinishPorting; // 64->32 warnings -- if we even keep this framework
#if 0
    NSDictionary *preferenceCache;
    NSArray *allValues;
    NSUInteger valueCount, valueIndex;

    if (domain == nil)
        return;
        
    [domainLock lock];
    preferenceCache = [self _lockedPreferenceCacheForDomain:domain];
    allValues = [preferenceCache allValues];
    [domainLock unlock];

    valueCount = [allValues count];
    for (valueIndex = 0; valueIndex < valueCount; valueIndex++) {
        OWSitePreference *preference;

        preference = [allValues objectAtIndex:valueIndex];
        [preference restoreDefaultValue];
    }

    [domainLock lock];
    [domainCache removeObjectForKey:domain];
    [domainLock unlock];
#endif
}

// Init and dealloc

- (void)dealloc;
{
    [OFPreference removeObserver:self forPreference:nil];
    [globalPreference release];
    [siteSpecificPreference release];
    
    [super dealloc];
}

// API

- (OFPreference *)siteSpecificPreference;
{
    return siteSpecificPreference;
}

- (NSString *)globalKey;
{
    return [globalPreference key];
}

- (id)defaultObjectValue;
{
    return nil;
}

- (BOOL)hasNonDefaultValue;
{
    return [siteSpecificPreference objectValue] != nil;
}

- (void)restoreDefaultValue;
{
    [siteSpecificPreference setObjectValue:nil];
}

- (id)objectValue;
{
    return [[self _preferenceForReading] objectValue];
}

- (void)setObjectValue:(id)value;
{
    [[self _preferenceForWriting] setObjectValue:value];
}

- (NSString *)stringValue;
{
    return [[self _preferenceForReading] stringValue];
}

- (void)setStringValue:(NSString *)value;
{
    [[self _preferenceForWriting] setStringValue:value];
}

- (BOOL)boolValue;
{
    return [[self _preferenceForReading] boolValue];
}

- (void)setBoolValue:(BOOL)value;
{
    [[self _preferenceForWriting] setBoolValue:value];
}

- (int)intValue;
{
    return [[self _preferenceForReading] intValue];
}

- (void)setIntValue:(int)intValue;
{
    [[self _preferenceForWriting] setIntValue:intValue];
}

- (NSInteger)integerValue;
{
    return [[self _preferenceForReading] integerValue];
}

- (void)setIntegerValue:(NSInteger)value;
{
    [[self _preferenceForWriting] setIntegerValue:value];
}

- (float)floatValue;
{
    return [[self _preferenceForReading] floatValue];
}

- (void)setFloatValue:(float)value;
{
    [[self _preferenceForWriting] setFloatValue:value];
}

- (double)doubleValue;
{
    return [[self _preferenceForReading] doubleValue];
}

- (void)setDoubleValue:(double)value;
{
    [[self _preferenceForWriting] setDoubleValue:value];
}

@end


@implementation OWSitePreference (Private)

+ (NSMutableDictionary *)_lockedPreferenceCacheForDomain:(NSString *)domain;
{
    NSMutableDictionary *preferenceCache;

    preferenceCache = [domainCache objectForKey:domain];
    if (preferenceCache == nil) {
        preferenceCache = [NSMutableDictionary dictionary];
        [domainCache setObject:preferenceCache forKey:domain];
    }
    
    return preferenceCache;
}

- (id)_initWithKey:(NSString *)key domain:(NSString *)domain;
{
    if (!(self = [super init]))
        return nil;
            
    // Global preference (used as a fallback)
    globalPreference = [[OFPreference preferenceForKey:key] retain];
        
    // Site-specific preference
    if (![NSString isEmptyString:domain]) {
        NSString *siteKey;
        
        domain = [domain lowercaseString];
        
        siteKey = [NSString stringWithFormat:@"SiteSpecific:%@:%@", domain, key];
        siteSpecificPreference = [[OFPreference preferenceForKey:siteKey] retain];
    }

    if (globalPreference != nil)
        [OFPreference addObserver:self selector:@selector(_preferenceDidChange:) forPreference:globalPreference];
    if (siteSpecificPreference != nil)
        [OFPreference addObserver:self selector:@selector(_preferenceDidChange:) forPreference:siteSpecificPreference];
        
    OBPOSTCONDITION(globalPreference != nil);
    
    return self;
}

- (OFPreference *)_preferenceForReading;
{
    if (siteSpecificPreference != nil && [siteSpecificPreference objectValue] != nil)
        return siteSpecificPreference;
    else
        return globalPreference;
}

- (OFPreference *)_preferenceForWriting;
{
    if (siteSpecificPreference != nil)
        return siteSpecificPreference;
    else
        return globalPreference;
}

- (void)_preferenceDidChange:(NSNotification *)notification;
{
    if ([notification object] == siteSpecificPreference) {
        id objectValue = [siteSpecificPreference objectValue];
        if (objectValue != nil && [objectValue isEqual:[globalPreference objectValue]]) {
            [siteSpecificPreference setObjectValue:nil];
        }
    }
    
    [sitePreferenceNotificationCenter postNotificationName:OWSitePreferenceDidChangeNotification object:self];
}

@end
