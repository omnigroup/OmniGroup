// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "ODAVConcreteTestCase.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>

@interface ODAVStaticTestCase : ODAVConcreteTestCase
@end

@implementation ODAVStaticTestCase

// Are allowed to LOCK missing files before they are created.
- (void)testLockMissingFile;
{
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    
    __autoreleasing NSError *error;
    NSString *lock = [self.connection synchronousLockURL:file error:&error];
    OBShouldNotError(lock);
}

- (void)testDoubleLockingFile;
{
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    
    __autoreleasing NSError *error;
    NSString *lock1 = [self.connection synchronousLockURL:file error:&error];
    OBShouldNotError(lock1);
    
    error = nil;
    NSString *lock2 = [self.connection synchronousLockURL:file error:&error];
    XCTAssertNil(lock2);
    XCTAssertTrue([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_LOCKED]);
}

- (void)testLockUnlockAndRelock;
{
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    
    __autoreleasing NSError *error;
    NSString *lock1 = [self.connection synchronousLockURL:file error:&error];
    OBShouldNotError(lock1);
    
    error = nil;
    OBShouldNotError([self.connection synchronousUnlockURL:file token:lock1 error:&error]);
    
    error = nil;
    NSString *lock2 = [self.connection synchronousLockURL:file error:&error];
    OBShouldNotError(lock2);
    
    XCTAssertFalse([lock1 isEqualToString:lock2], @"Lock tokens should be globally unique");
}

- (void)testUnlockWithoutLock;
{
    // Make a file (so we don't get a 'Not Found' error when unlocking, but whatever the 'hey there is no matching lock' error would be).
    __autoreleasing NSError *error;
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    OBShouldNotError([self.connection synchronousPutData:[NSData data] toURL:file error:&error]);
    
    error = nil;
    XCTAssertFalse([self.connection synchronousUnlockURL:file token:@"xxx" error:&error], @"Shouldn't be able to remove unknown lock");
    
    // We'd kind of expect to get back ODAV_HTTP_CONFLICT, but Apache 2.4.3 returns ODAV_HTTP_BAD_REQUEST. This should only be returned when the "Lock-Token" header was missing from the UNLOCK request.
    XCTAssertTrue([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_BAD_REQUEST]);
}

- (void)testLockAndThenDoubleUnlock;
{
    __autoreleasing NSError *error;
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    OBShouldNotError([self.connection synchronousPutData:[NSData data] toURL:file error:&error]);
    
    NSString *lock = [self.connection synchronousLockURL:file error:&error];
    OBShouldNotError(lock);
    
    error = nil;
    OBShouldNotError([self.connection synchronousUnlockURL:file token:lock error:&error]);
    
    error = nil;
    XCTAssertFalse([self.connection synchronousUnlockURL:file token:lock error:&error], @"Second lock should fail");
    
    // We'd kind of expect to get back ODAV_HTTP_CONFLICT, but Apache 2.4.3 returns ODAV_HTTP_BAD_REQUEST. This should only be returned when the "Lock-Token" header was missing from the UNLOCK request.
    XCTAssertTrue([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_BAD_REQUEST]);
}

- (void)testReplaceLockedCollection;
{
    __autoreleasing NSError *error;
    NSURL *dir1 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir1" isDirectory:YES];
    NSURL *dir2 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir2" isDirectory:YES];
    
    OBShouldNotError([self.connection synchronousMakeCollectionAtURL:dir1 error:&error]);
    OBShouldNotError([self.connection synchronousMakeCollectionAtURL:dir2 error:&error]);
    
    NSString *lock = [self.connection synchronousLockURL:dir1 error:&error];
    OBShouldNotError(lock);
    
    OBShouldNotError([self.connection synchronousMoveURL:dir2 toURL:dir1 withDestinationLock:lock overwrite:YES error:&error]);
    
    OBShouldNotError([self.connection synchronousUnlockURL:dir1 token:lock error:&error]);
}

- (void)testMoveWithLock;
{
    NSURL *dir1 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    __autoreleasing NSError *error;
    dir1 = [self.connection synchronousMakeCollectionAtURL:dir1 error:&error].URL;
    OBShouldNotError(dir1);
    
    error = nil;
    NSString *lock = [self.connection synchronousLockURL:dir1 error:&error];
    OBShouldNotError(lock);
    
    error = nil;
    OBShouldNotError([self.connection synchronousMoveURL:dir1 toURL:dir2 withSourceLock:lock overwrite:NO error:&error]);
}

- (void)testMoveWithMissingLock;
{
    NSURL *dir1 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    __autoreleasing NSError *error;
    dir1 = [self.connection synchronousMakeCollectionAtURL:dir1 error:&error].URL;
    OBShouldNotError(dir1);
    
    error = nil;
    NSString *lock = [self.connection synchronousLockURL:dir1 error:&error];
    OBShouldNotError(lock);
    
    error = nil;
    XCTAssertNil([self.connection synchronousMoveURL:dir1 toURL:dir2 withSourceLock:nil overwrite:NO error:&error]);
    XCTAssertTrue([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_LOCKED]);
}

@end
