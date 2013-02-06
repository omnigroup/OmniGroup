// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFSDAVFileManager;

@interface OFSDAVConformanceTest : NSObject

typedef BOOL (*OFSDAVConformanceTestImp)(OFSDAVConformanceTest *self, SEL _cmd, __autoreleasing NSError **outError);

+ (void)eachTest:(void (^)(SEL sel, OFSDAVConformanceTestImp imp))applier;

- initWithFileManager:(OFSDAVFileManager *)fileManager;

@property(nonatomic,readonly) OFSDAVFileManager *fileManager;
@property(nonatomic,readonly) NSUInteger numberOfTestsAvailable;

@property(nonatomic,copy) void (^statusChanged)(NSString *status);
@property(nonatomic,copy) void (^finished)(NSError *errorOrNil); // On failure, the error passed will wrap up all the failing errors.
@property(nonatomic,readonly) NSUInteger numberOfTestsRun;

// Runs all the tests once and then calls the finished block, if set. Clears the finished block afterward to clean up any possible retain cycles.
- (void)start;

@end

extern NSString * const OFSDAVConformanceFailureErrors; // User info key wrapping array of all failures
