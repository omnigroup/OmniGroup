// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

// Enable this only when needed
#define OF_TRANSIENT_OBJECTS_TRACKER_ENABLED 0

#if OF_TRANSIENT_OBJECTS_TRACKER_ENABLED

@interface OFTransientObjectsTracker : NSObject

+ (OFTransientObjectsTracker *)transientObjectsTrackerForClass:(Class)cls addInitializers:(void (^)(OFTransientObjectsTracker *tracker))addInitializers;

- (void)addInitializerWithSelector:(SEL)sel action:(id)block;
- (void)registerInstance:(id)instance;
- (IMP)originalImplementationForSelector:(SEL)sel;

- (void)trackAllocationsIn:(void (^)(void))block;
- (void)beginTracking;
- (void)endTracking;

@end
#endif
