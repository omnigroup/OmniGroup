// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/OWSitePreference.h 71110 2005-12-13 22:45:49Z kc $

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

- (id)objectValue;
- (void)setObjectValue:(id)objectValue;
- (NSString *)stringValue;
- (void)setStringValue:(NSString *)stringValue;
- (BOOL)boolValue;
- (void)setBoolValue:(BOOL)boolValue;
- (int)integerValue;
- (void)setIntegerValue:(int)integerValue;
- (float)floatValue;
- (void)setFloatValue:(float)floatValue;

@end
