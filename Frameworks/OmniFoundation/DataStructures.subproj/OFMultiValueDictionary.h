// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <CoreFoundation/CFDictionary.h>
#import <OmniFoundation/OFUtilities.h>

@class NSArray, NSEnumerator, NSMutableDictionary;

@interface OFMultiValueDictionary : OFObject </*NSCoding,*/ NSMutableCopying>

- init;
- initWithCaseInsensitiveKeys:(BOOL)caseInsensitivity;
- initWithKeyCallBacks:(const CFDictionaryKeyCallBacks *)keyBehavior;

- (NSArray *)arrayForKey:(id)aKey;
- (id)firstObjectForKey:(id)aKey;
- (id)lastObjectForKey:(id)aKey;
- (void)addObject:(id)anObject forKey:(id)aKey;
- (void)addObjects:(NSArray *)moreObjects forKey:(id)aKey;
- (void)addObjects:(NSArray *)manyObjects keyedByBlock:(OFObjectToObjectBlock)keyBlock;
- (void)setObjects:(NSArray *)replacementObjects forKey:(id)aKey;
- (void)insertObject:(id)anObject forKey:(id)aKey atIndex:(unsigned int)anIndex;
- (BOOL)removeObject:(id)anObject forKey:(id)aKey;
- (BOOL)removeObjectIdenticalTo:(id)anObject forKey:(id)aKey;
- (void)removeAllObjects;
- (NSEnumerator *)keyEnumerator;
- (NSArray *)allKeys;
- (NSArray *)allValues;

- (NSMutableDictionary *)dictionary;

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
