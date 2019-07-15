// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

/*!
 @summary OFResultHolder is a convenience class for use with asynchronous code to load a result. Callers can create a result holder, begin work to calculate and set the result, then request the result on another thread. The result holder will block on requests for the result before it's loaded.
 */
@interface OFResultHolder<ResultType> : NSObject

/// When the computed result is set, the receiver will retain it and immediately return it to any callers. Callers will block until there is a result available. If there are blocked calls to -result outstanding, the new result will be returned to each of them. Note, if the value responds to NSCopying, it will be copied instead of just retained (we can't declare that in the interface here).
@property(nonatomic,strong) ResultType result;

@end
