// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <CoreFoundation/CFDictionary.h>
#import <OmniFoundation/OFUtilities.h>

@class NSArray, NSEnumerator, NSMutableDictionary;

@interface OFMultiValueDictionary <__covariant KeyType, __covariant ObjectType> : NSObject </*NSCoding,*/ NSCopying>

- init;
- initWithCaseInsensitiveKeys:(BOOL)caseInsensitivity;
- initWithKeyCallBacks:(const CFDictionaryKeyCallBacks *)keyBehavior;

- (NSArray<ObjectType> *)arrayForKey:(KeyType)aKey;
- (ObjectType)firstObjectForKey:(KeyType)aKey;
- (ObjectType)lastObjectForKey:(KeyType)aKey;
- (void)addObject:(ObjectType)anObject forKey:(KeyType)aKey;
- (void)addObjects:(NSArray<ObjectType> *)moreObjects forKey:(KeyType)aKey;
- (void)addObjects:(NSArray<ObjectType> *)manyObjects keyedByBlock:(KeyType (^)(ObjectType object))keyBlock;
- (void)setObjects:(NSArray<ObjectType> *)replacementObjects forKey:(KeyType)aKey;
- (void)insertObject:(ObjectType)anObject forKey:(KeyType)aKey atIndex:(unsigned int)anIndex;
- (BOOL)removeObject:(ObjectType)anObject forKey:(KeyType)aKey;
- (BOOL)removeObjectIdenticalTo:(ObjectType)anObject forKey:(KeyType)aKey;
- (void)removeAllObjects;
- (NSEnumerator<KeyType> *)keyEnumerator;
- (NSArray<KeyType> *)allKeys;
- (NSArray<ObjectType> *)allValues;

- (NSMutableDictionary<KeyType, NSArray<ObjectType> *> *)dictionary;

@end

#import <Foundation/NSArray.h>
@interface NSArray (OFMultiValueDictionary)
- (OFMultiValueDictionary *)groupByKeyBlock:(OFObjectToObjectBlock)keyBlock;
- (OFMultiValueDictionary *)groupByKeyBlock:(id (^)(id object, id arg))keyBlock withObject:(id)argument;
@end

@interface NSString (OFMultiValueDictionary)
- (void)parseQueryString:(void (^)(NSString *decodedName, NSString *decodedValue, BOOL *stop))handlePair;
- (OFMultiValueDictionary *)parametersFromQueryString;
@end
