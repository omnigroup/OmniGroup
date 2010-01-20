// Copyright 2001-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFVersionNumber;

typedef enum {
    OSUCheckOperationHasNotRun,
    OSUCheckOperationRunSynchronously,
    OSUCheckOperationRunAsynchronously,
} OSUCheckOperationRunType;

// This represents a single check operation to the software update server, invoked by OSUChecker.
@interface OSUCheckOperation : NSObject
{
    OSUCheckOperationRunType _runType;
    BOOL _initiatedByUser;
    NSURL *_url;
    NSTask *_task;
    NSPipe *_pipe;
    NSData *_output;
    int _terminationStatus;
}

- initForQuery:(BOOL)doQuery url:(NSURL *)url licenseType:(NSString *)licenseType;

- (NSURL *)url;

- (void)runAsynchronously;
- (NSData *)runSynchronously;

@property(readonly ) OSUCheckOperationRunType runType;
@property(readwrite) BOOL initiatedByUser;

- (void)waitUntilExit;

- (NSData *)output;
@property(readonly ) int terminationStatus;

@end

extern NSString * const OSUCheckOperationCompletedNotification;
