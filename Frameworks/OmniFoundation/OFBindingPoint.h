// Copyright 2004-2007, 2010-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@interface OFBindingPoint : OFObject
{
@private
    id _object;
    NSString *_keyPath;
}

- initWithObject:(id)object keyPath:(NSString *)keyPath;

@property(nonatomic,readonly) id object;
@property(nonatomic,readonly) NSString *keyPath;

@end

static inline OFBindingPoint *OFBindingPointMake(id object, NSString *keyPath)
{
    return [[[OFBindingPoint alloc] initWithObject:object keyPath:keyPath] autorelease];
}

extern BOOL OFBindingPointsEqual(OFBindingPoint *a, OFBindingPoint *b);
