// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

// Enable in local builds when needed.

#define OF_PERFORMANCE_MEASUREMENT_ENABLED 1

#if OF_PERFORMANCE_MEASUREMENT_ENABLED
@interface OFPerformanceMeasurement : NSObject

- (void)addValue:(double)value;
- (void)addValueWithAction:(void (^)(void))action;
- (void)addValues:(NSUInteger)trials withAction:(void (^)(void))action;

@end
#endif
