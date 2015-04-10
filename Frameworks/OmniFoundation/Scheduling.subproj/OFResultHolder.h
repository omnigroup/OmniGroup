// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSConditionLock;

/*!
 @summary OFResultHolder is a convenience class for use with asynchronous code to load a result. Callers can create a result holder, begin work to calculate and set the result, then request the result on another thread. The result holder will block on requests for the result before it's loaded.
 */
@interface OFResultHolder : OFObject
{
    id result;
    NSConditionLock *resultLock;
}

/// Call with a computed result. The receiver will retain the result and immediately return it to any callers. If there are blocked calls to -result outstanding, the new result will be returned to each of them.
- (void)setResult:(id)newResult;

/// Returns the computed result stored in the receiver. If no result has been set, calls to this method will block until a result is set.
- (id)result;

@end
