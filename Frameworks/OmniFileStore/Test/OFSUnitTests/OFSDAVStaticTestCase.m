// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFSDAVTestCase.h"

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSFileInfo.h>

@interface OFSDAVStaticTestCase : OFSDAVTestCase
@end

@implementation OFSDAVStaticTestCase

// Are allowed to LOCK missing files before they are created.
- (void)testLockMissingFile;
{
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    
    __autoreleasing NSError *error;
    NSString *lock = [self.fileManager lockURL:file error:&error];
    OBShouldNotError(lock);
}

- (void)testDoubleLockingFile;
{
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    
    __autoreleasing NSError *error;
    NSString *lock1 = [self.fileManager lockURL:file error:&error];
    OBShouldNotError(lock1);
    
    error = nil;
    NSString *lock2 = [self.fileManager lockURL:file error:&error];
    STAssertNil(lock2, nil);
    STAssertTrue([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_LOCKED], nil);
}

- (void)testLockUnlockAndRelock;
{
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    
    __autoreleasing NSError *error;
    NSString *lock1 = [self.fileManager lockURL:file error:&error];
    OBShouldNotError(lock1);
    
    error = nil;
    OBShouldNotError([self.fileManager unlockURL:file token:lock1 error:&error]);
    
    error = nil;
    NSString *lock2 = [self.fileManager lockURL:file error:&error];
    OBShouldNotError(lock2);
    
    STAssertFalse([lock1 isEqualToString:lock2], @"Lock tokens should be globally unique");
}

- (void)testUnlockWithoutLock;
{
    // Make a file (so we don't get a 'Not Found' error when unlocking, but whatever the 'hey there is no matching lock' error would be).
    __autoreleasing NSError *error;
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    OBShouldNotError([self.fileManager writeData:[NSData data] toURL:file atomically:NO error:&error]);
    
    error = nil;
    STAssertFalse([self.fileManager unlockURL:file token:@"xxx" error:&error], @"Shouldn't be able to remove unknown lock");
    
    // We'd kind of expect to get back OFS_HTTP_CONFLICT, but Apache 2.4.3 returns OFS_HTTP_BAD_REQUEST. This should only be returned when the "Lock-Token" header was missing from the UNLOCK request.
    STAssertTrue([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_BAD_REQUEST], nil);
}

- (void)testLockAndThenDoubleUnlock;
{
    __autoreleasing NSError *error;
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    OBShouldNotError([self.fileManager writeData:[NSData data] toURL:file atomically:NO error:&error]);
    
    NSString *lock = [self.fileManager lockURL:file error:&error];
    OBShouldNotError(lock);
    
    error = nil;
    OBShouldNotError([self.fileManager unlockURL:file token:lock error:&error]);
    
    error = nil;
    STAssertFalse([self.fileManager unlockURL:file token:lock error:&error], @"Second lock should fail");
    
    // We'd kind of expect to get back OFS_HTTP_CONFLICT, but Apache 2.4.3 returns OFS_HTTP_BAD_REQUEST. This should only be returned when the "Lock-Token" header was missing from the UNLOCK request.
    STAssertTrue([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_BAD_REQUEST], nil);
}

- (void)testReplaceLockedCollection;
{
    __autoreleasing NSError *error;
    NSURL *dir1 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir1" isDirectory:YES];
    NSURL *dir2 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir2" isDirectory:YES];
    
    OBShouldNotError([self.fileManager createDirectoryAtURL:dir1 attributes:nil error:&error]);
    OBShouldNotError([self.fileManager createDirectoryAtURL:dir2 attributes:nil error:&error]);
    
    NSString *lock = [self.fileManager lockURL:dir1 error:&error];
    OBShouldNotError(lock);
    
    OBShouldNotError([self.fileManager moveURL:dir2 toURL:dir1 withDestinationLock:lock overwrite:YES error:&error]);
    
    OBShouldNotError([self.fileManager unlockURL:dir1 token:lock error:&error]);
}

- (void)testMoveWithLock;
{
    NSURL *dir1 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    __autoreleasing NSError *error;
    dir1 = [self.fileManager createDirectoryAtURLIfNeeded:dir1 error:&error];
    OBShouldNotError(dir1);
    
    error = nil;
    NSString *lock = [self.fileManager lockURL:dir1 error:&error];
    OBShouldNotError(lock);
    
    error = nil;
    OBShouldNotError([self.fileManager moveURL:dir1 toURL:dir2 withSourceLock:lock overwrite:NO error:&error]);
}

- (void)testMoveWithMissingLock;
{
    NSURL *dir1 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir-1" isDirectory:YES];
    NSURL *dir2 = [self.remoteBaseURL URLByAppendingPathComponent:@"dir-2" isDirectory:YES];
    
    __autoreleasing NSError *error;
    dir1 = [self.fileManager createDirectoryAtURLIfNeeded:dir1 error:&error];
    OBShouldNotError(dir1);
    
    error = nil;
    NSString *lock = [self.fileManager lockURL:dir1 error:&error];
    OBShouldNotError(lock);
    
    error = nil;
    STAssertNil([self.fileManager moveURL:dir1 toURL:dir2 withSourceLock:nil overwrite:NO error:&error], nil);
    STAssertTrue([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_LOCKED], nil);
}

@end
