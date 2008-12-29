// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSConditionLock;

@interface OFResultHolder : OFObject
{
    id result;
    NSConditionLock *resultLock;
}

- (void)setResult:(id)newResult;
- (id)result;

@end
