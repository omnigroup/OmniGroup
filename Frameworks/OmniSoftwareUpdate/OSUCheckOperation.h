// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniBase/macros.h>

@class OFVersionNumber;

typedef enum {
    OSUCheckOperationHasNotRun,
    OSUCheckOperationRunSynchronously,
    OSUCheckOperationRunAsynchronously,
} OSUCheckOperationRunType;

// This represents a single check operation to the software update server, invoked by OSUChecker.
@interface OSUCheckOperation : NSObject

- initForQuery:(BOOL)doQuery url:(NSURL *)url licenseType:(NSString *)licenseType;

- (NSURL *)url;

- (void)runAsynchronously;
- (NSDictionary *)runSynchronously;

@property(nonatomic,readonly) OSUCheckOperationRunType runType;
@property(nonatomic) BOOL initiatedByUser;

@property(nonatomic,readonly,strong) NSDictionary *output; // KVO observable; will fire on the main thread
@property(nonatomic,readonly,strong) NSError *error; // KVO observable; will fire on the main thread

@end

extern NSString * const OSUCheckOperationCompletedNotification;
