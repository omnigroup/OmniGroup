// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class ODAVConnection;

typedef struct {
    NSInteger completed;
    NSUInteger total;
} ODAVConformanceTestProgress;

@interface ODAVConformanceTest : NSObject

typedef BOOL (*ODAVConformanceTestImp)(ODAVConformanceTest *self, SEL _cmd, __autoreleasing NSError **outError);

+ (void)eachTest:(void (^)(SEL sel, ODAVConformanceTestImp imp, ODAVConformanceTestProgress progress))applier;

- initWithConnection:(ODAVConnection *)connection baseURL:(NSURL *)baseURL;

@property(nonatomic,readonly) ODAVConnection *connection;
@property(nonatomic,readonly) NSUInteger numberOfTestsAvailable;

@property(nonatomic,copy) void (^statusChanged)(NSString *status, double percentDone);
@property(nonatomic,copy) void (^finished)(NSError *errorOrNil); // On failure, the error passed will wrap up all the failing errors.
@property(nonatomic,readonly) NSUInteger numberOfTestsRun;

// Runs all the tests once and then calls the finished block, if set. Clears the finished block afterward to clean up any possible retain cycles.
- (void)start;

@end

extern NSString * const ODAVConformanceFailureErrors; // User info key wrapping array of all failures
