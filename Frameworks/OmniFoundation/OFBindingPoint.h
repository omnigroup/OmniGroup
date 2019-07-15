// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFBindingPoint : OFObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithObject:(id)object keyPath:(NSString *)keyPath NS_DESIGNATED_INITIALIZER;

@property(nonatomic, readonly) id object;
@property(nonatomic, readonly) NSString *keyPath;

- (OFBindingPoint *)bindingPointByAppendingKey:(NSString *)key;

@end

static inline OFBindingPoint * OFBindingPointMake(id object, NSString *keyPath)
{
    OFBindingPoint *bindingPoint = [[OFBindingPoint alloc] initWithObject:object keyPath:keyPath];
#if defined(__has_feature) && __has_feature(objc_arc)
    return bindingPoint;
#else
    return [bindingPoint autorelease];
#endif
}

#define OFValidateKeyPath(object, keyPath) ((NO && (object).keyPath != 0) ? @#keyPath : @#keyPath)
#define OFKeyPathWithClass(cls, keyPath) OFValidateKeyPath((cls *)nil, keyPath)
#define OFKeyPathWithProtocol(protocol, keyPath) OFValidateKeyPath((id <protocol>)nil, keyPath)
#define OFBindingKeyPath(object, keyPath) OFBindingPointMake(object, OFValidateKeyPath(object, keyPath))

extern BOOL OFBindingPointsEqual(OFBindingPoint *a, OFBindingPoint *b);

NS_ASSUME_NONNULL_END
