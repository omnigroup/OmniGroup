// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSArray, NSDictionary, NSScriptObjectSpecifier;

@interface NSObject (OFAppleScriptExtensions) 

+ (void)registerConversionFromRecord;
+ (id)coerceRecord:(NSDictionary *)dictionary toClass:(Class)aClass;
+ (id)coerceObject:(id)object toRecordClass:(Class)aClass;


- (BOOL)ignoreAppleScriptValueForKey:(NSString *)key; // implement for keys to ignore for 'make' and record coercion
// or implement -(BOOL)ignoreAppleScriptValueFor<KeyName>
- (NSDictionary *)appleScriptAsRecord;
- (void)appleScriptTakeAttributesFromRecord:(NSDictionary *)record;
- (NSArray *)appleScriptExtraAttributeKeys; // implement to add extra keys for -appleScriptMakeProperties
- (NSString *)appleScriptMakeProperties;
- (NSString *)appleScriptMakeCommandAt:(NSString *)aLocationSpecifier;
- (NSString *)appleScriptMakeCommandAt:(NSString *)aLocationSpecifier withIndent:(int)indent;

- (NSScriptObjectSpecifier *)objectSpecifierByProperty:(NSString *)propertyKey inRelation:(NSString *)myLocation toContainer:(NSObject *)myContainer;

@end
