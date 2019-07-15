// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSDictionary.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>

@interface NSMutableDictionary<KeyType, ObjectType> (OFExtensions)
- (void)setObject:(ObjectType)anObject forKeys:(NSArray<KeyType> *)keys;

// These are nice for ease of use
- (void)setFloatValue:(float)value forKey:(KeyType)key;
- (void)setDoubleValue:(double)value forKey:(KeyType)key;
- (void)setIntValue:(int)value forKey:(KeyType)key;
- (void)setUnsignedIntValue:(unsigned int)value forKey:(KeyType)key;
- (void)setIntegerValue:(NSInteger)value forKey:(KeyType)key;
- (void)setUnsignedIntegerValue:(NSUInteger)value forKey:(KeyType)key;
- (void)setUnsignedLongLongValue:(unsigned long long)value forKey:(KeyType)key;
- (void)setBoolValue:(BOOL)value forKey:(KeyType)key;
- (void)setPointValue:(CGPoint)value forKey:(KeyType)key;
- (void)setSizeValue:(CGSize)value forKey:(KeyType)key;
- (void)setRectValue:(CGRect)value forKey:(KeyType)key;

// Setting with default values
- (void)setObject:(ObjectType)object forKey:(KeyType)key defaultObject:(ObjectType)defaultObject;
- (void)setFloatValue:(float)value forKey:(KeyType)key defaultValue:(float)defaultValue;
- (void)setDoubleValue:(double)value forKey:(KeyType)key defaultValue:(double)defaultValue;
- (void)setIntValue:(int)value forKey:(KeyType)key defaultValue:(int)defaultValue;
- (void)setUnsignedIntValue:(unsigned int)value forKey:(KeyType)key defaultValue:(unsigned int)defaultValue;
- (void)setIntegerValue:(NSInteger)value forKey:(KeyType)key defaultValue:(NSInteger)defaultValue;
- (void)setUnsignedIntegerValue:(NSUInteger)value forKey:(KeyType)key defaultValue:(NSUInteger)defaultValue;
- (void)setUnsignedLongLongValue:(unsigned long long)value forKey:(KeyType)key defaultValue:(unsigned long long)defaultValue;
- (void)setBoolValue:(BOOL)value forKey:(KeyType)key defaultValue:(BOOL)defaultValue;
- (void)setPointValue:(CGPoint)value forKey:(KeyType)key defaultValue:(CGPoint)defaultValue;
- (void)setSizeValue:(CGSize)value forKey:(KeyType)key defaultValue:(CGSize)defaultValue;
- (void)setRectValue:(CGRect)value forKey:(KeyType)key defaultValue:(CGRect)defaultValue;

@end
