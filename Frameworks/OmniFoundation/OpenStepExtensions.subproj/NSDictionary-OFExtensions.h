// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSDictionary.h>
#import <Foundation/NSSet.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSGeometry.h> // For NSPoint, NSSize, and NSRect
#else
#import <CoreGraphics/CGGeometry.h>
#endif

@class NSMutableArray;

@interface NSDictionary<__covariant KeyType, __covariant ObjectType> (OFExtensions)

- (NSDictionary *)dictionaryWithPossiblyRemovedObject:(ObjectType)anObj forKey:(NSString *)key;
- (NSDictionary *)dictionaryWithObject:(ObjectType)anObj forKey:(NSString *)key;
- (NSDictionary *)dictionaryWithObjectRemovedForKey:(NSString *)key;
- (NSDictionary *)dictionaryByAddingObjectsFromDictionary:(NSDictionary *)otherDictionary;

- (ObjectType)anyObject;
- (NSString *)keyForObjectEqualTo:(id)anObj;

- (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)defaultValue;
- (NSString *)stringForKey:(NSString *)key;

- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key defaultValue:(NSArray<NSString *> *)defaultValue;
- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key;

// ObjC methods to nil have undefined results for non-id values (though ints happen to currently work)
- (float)floatForKey:(NSString *)key defaultValue:(float)defaultValue;
- (float)floatForKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key defaultValue:(double)defaultValue;
- (double)doubleForKey:(NSString *)key;

- (CGPoint)pointForKey:(NSString *)key defaultValue:(CGPoint)defaultValue;
- (CGPoint)pointForKey:(NSString *)key;
- (CGSize)sizeForKey:(NSString *)key defaultValue:(CGSize)defaultValue;
- (CGSize)sizeForKey:(NSString *)key;
- (CGRect)rectForKey:(NSString *)key defaultValue:(CGRect)defaultValue;
- (CGRect)rectForKey:(NSString *)key;

// Returns YES iff the value is YES, Y, yes, y, or 1.
- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
- (BOOL)boolForKey:(NSString *)key;

// Just to make life easier
- (int)intForKey:(NSString *)key defaultValue:(int)defaultValue;
- (int)intForKey:(NSString *)key;
- (unsigned int)unsignedIntForKey:(NSString *)key defaultValue:(unsigned int)defaultValue;
- (unsigned int)unsignedIntForKey:(NSString *)key;

- (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (NSInteger)integerForKey:(NSString *)key;

- (NSUInteger)unsignedIntegerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (NSUInteger)unsignedIntegerForKey:(NSString *)key;

- (unsigned long long int)unsignedLongLongForKey:(NSString *)key defaultValue:(unsigned long long int)defaultValue;
- (unsigned long long int)unsignedLongLongForKey:(NSString *)key;

- (void)makeValuesPerformSelector:(SEL)sel withObject:(id)object;
- (void)makeValuesPerformSelector:(SEL)sel;

    // This seems more convenient than having to write your own if statement a zillion times
- (ObjectType)objectForKey:(KeyType)key defaultObject:(ObjectType)defaultObject;

- (NSMutableDictionary<KeyType,ObjectType> *)deepMutableCopy NS_RETURNS_RETAINED;

- (NSArray<KeyType> *)copyKeys;
- (NSMutableArray<KeyType> *)mutableCopyKeys;

- (NSSet<KeyType> *)copyKeySet;
- (NSMutableSet<KeyType> *)mutableCopyKeySet;

@end
