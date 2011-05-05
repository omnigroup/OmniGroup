// Copyright 1997-2005, 2008-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSDictionary.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>

@interface NSMutableDictionary (OFExtensions)
- (void)setObject:(id)anObject forKeys:(NSArray *)keys;

// These are nice for ease of use
- (void)setFloatValue:(float)value forKey:(id)key;
- (void)setDoubleValue:(double)value forKey:(id)key;
- (void)setIntValue:(int)value forKey:(id)key;
- (void)setUnsignedIntValue:(unsigned int)value forKey:(id)key;
- (void)setIntegerValue:(NSInteger)value forKey:(id)key;
- (void)setUnsignedIntegerValue:(NSUInteger)value forKey:(id)key;
- (void)setUnsignedLongLongValue:(unsigned long long)value forKey:(id)key;
- (void)setBoolValue:(BOOL)value forKey:(id)key;
- (void)setPointValue:(CGPoint)value forKey:(id)key;
- (void)setSizeValue:(CGSize)value forKey:(id)key;
- (void)setRectValue:(CGRect)value forKey:(id)key;

// Setting with default values
- (void)setObject:(id)object forKey:(id)key defaultObject:(id)defaultObject;
- (void)setFloatValue:(float)value forKey:(id)key defaultValue:(float)defaultValue;
- (void)setDoubleValue:(double)value forKey:(id)key defaultValue:(double)defaultValue;
- (void)setIntValue:(int)value forKey:(id)key defaultValue:(int)defaultValue;
- (void)setUnsignedIntValue:(unsigned int)value forKey:(id)key defaultValue:(unsigned int)defaultValue;
- (void)setIntegerValue:(NSInteger)value forKey:(id)key defaultValue:(NSInteger)defaultValue;
- (void)setUnsignedIntegerValue:(NSUInteger)value forKey:(id)key defaultValue:(NSUInteger)defaultValue;
- (void)setUnsignedLongLongValue:(unsigned long long)value forKey:(id)key defaultValue:(unsigned long long)defaultValue;
- (void)setBoolValue:(BOOL)value forKey:(id)key defaultValue:(BOOL)defaultValue;
- (void)setPointValue:(CGPoint)value forKey:(id)key defaultValue:(CGPoint)defaultValue;
- (void)setSizeValue:(CGSize)value forKey:(id)key defaultValue:(CGSize)defaultValue;
- (void)setRectValue:(CGRect)value forKey:(id)key defaultValue:(CGRect)defaultValue;

@end
