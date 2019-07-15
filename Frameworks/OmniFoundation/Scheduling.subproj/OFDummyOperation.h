// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSOperation.h>
#import <OmniFoundation/OFAsynchronousOperation.h>

/// OFDummyOperation is a convenience class for APIs which return a future result via an operation, but which in some cases may have an immediately available result.
///
/// Note that the operation returned from init is unstarted, in case the API requires further configuration. Callers may simply call -start to immediately put the operation into the finished state.
@interface OFDummyOperation<ResultType> : NSOperation <OFErrorable>

- (instancetype __nonnull)init NS_UNAVAILABLE;
- (instancetype __nonnull)initWithResult:(ResultType __nonnull)obj NS_DESIGNATED_INITIALIZER;
- (instancetype __nonnull)initWithError:(NSError * __nonnull)obj NS_DESIGNATED_INITIALIZER;

@property(atomic,readonly,strong,nullable) NSError *error;
@property(atomic,readonly,strong,nullable) ResultType result;

@end
