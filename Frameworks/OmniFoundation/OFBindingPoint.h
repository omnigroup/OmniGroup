// Copyright 2004-2007, 2010-2012, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@interface OFBindingPoint : OFObject

- (id)initWithObject:(id)object keyPath:(NSString *)keyPath;

@property(nonatomic, readonly) id object;
@property(nonatomic, readonly) NSString *keyPath;

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

#define OFValidateKeyPath(object, keyPath) (NO && (object).keyPath ? @#keyPath : @#keyPath)
#define OFKeyPathWithClass(cls, keyPath) OFValidateKeyPath((cls *)nil, keyPath)
#define OFBindingKeyPath(object, keyPath) OFBindingPointMake(object, OFValidateKeyPath(object, keyPath))

extern BOOL OFBindingPointsEqual(OFBindingPoint *a, OFBindingPoint *b);

