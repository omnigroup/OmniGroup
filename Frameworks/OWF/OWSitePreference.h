// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSDictionary;
@class OFPreference;
@class OWAddress, OWURL;

@interface OWSitePreference : OFObject
{
    OFPreference *globalPreference;
    OFPreference *siteSpecificPreference;
}

+ (void)addObserver:(id)anObserver selector:(SEL)aSelector forSitePreference:(OWSitePreference *)aSitePreference;
+ (void)removeObserver:(id)anObserver forSitePreference:(OWSitePreference *)aSitePreference;

+ (NSString *)domainForAddress:(OWAddress *)address;
+ (NSString *)domainForURL:(OWURL *)url;
+ (OWSitePreference *)preferenceForKey:(NSString *)key domain:(NSString *)domain;
+ (OWSitePreference *)preferenceForKey:(NSString *)key address:(OWAddress *)address;
+ (NSDictionary *)domainCache;
+ (BOOL)siteHasPreferences:(OWAddress *)address;
+ (void)resetPreferencesForDomain:(NSString *)domain;

- (OFPreference *)siteSpecificPreference;
- (NSString *)globalKey;

- (id)defaultObjectValue;
- (BOOL)hasNonDefaultValue;
- (void)restoreDefaultValue;

@property(nonatomic,retain) id objectValue;
@property(nonatomic,copy) NSString *stringValue;
@property(nonatomic,copy) NSURL *bookmarkURLValue;
@property(nonatomic,assign) BOOL boolValue;
@property(nonatomic,assign) int intValue;
@property(nonatomic,assign) NSInteger integerValue;
@property(nonatomic,assign) float floatValue;
@property(nonatomic,assign) double doubleValue;

@end
