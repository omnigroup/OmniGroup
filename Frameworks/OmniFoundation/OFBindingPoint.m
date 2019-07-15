// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBindingPoint.h>

#import <OmniFoundation/OFBinding.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OFBindingPoint

- (instancetype)init NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (id)initWithObject:(id)object keyPath:(NSString *)keyPath;
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    _object = [object retain];
    _keyPath = [keyPath copy];
    
    return self;
}

- (void)dealloc;
{
    [_object release];
    [_keyPath release];
    [super dealloc];
}

- (OFBindingPoint *)bindingPointByAppendingKey:(NSString *)key;
{
    return OFBindingPointMake(_object, OFKeyPathForKeys(_keyPath, key, nil));
}

- (BOOL)isEqual:(id)object;
{
    if (![object isKindOfClass:[OFBindingPoint class]]) {
        return NO;
    }

    return OFBindingPointsEqual(self, object);
}

- (NSUInteger)hash;
{
    return [_object hash] ^ [_keyPath hash];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    
    debugDictionary[@"object"] = [_object debugDescription];
    debugDictionary[@"keyPath"] = _keyPath;

    return debugDictionary;
}

BOOL OFBindingPointsEqual(OFBindingPoint *a, OFBindingPoint *b)
{
    // Requires identical objects, not -isEqual:!
    return a->_object == b->_object && [a->_keyPath isEqualToString:b->_keyPath];
}

@end

NS_ASSUME_NONNULL_END
