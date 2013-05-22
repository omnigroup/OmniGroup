// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSFileManager.h>

@interface OFSDAVFileManager : OFSFileManager <OFSConcreteFileManager>

// Takes an infinite-depth exclusive write lock on the URL, returning the lock token. No support right now for refreshing locks.
- (NSString *)lockURL:(NSURL *)url error:(NSError **)outError;

// Removes the lock.
- (BOOL)unlockURL:(NSURL *)url token:(NSString *)lockToken error:(NSError **)outError;

- (NSURL *)copyURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite error:(NSError **)outError;

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceLock:(NSString *)lock overwrite:(BOOL)overwrite error:(NSError **)outError;
- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationLock:(NSString *)lock overwrite:(BOOL)overwrite error:(NSError **)outError;

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite error:(NSError **)outError;
- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationETag:(NSString *)ETag overwrite:(BOOL)overwrite error:(NSError **)outError;

- (NSURL *)moveURL:(NSURL *)sourceURL toMissingURL:(NSURL *)destURL error:(NSError **)outError;
- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL ifURLExists:(NSURL *)tagURL error:(NSError **)outError;

- (NSData *)dataWithContentsOfURL:(NSURL *)url withETag:(NSString *)ETag error:(NSError **)outError;

- (OFSFileInfo *)fileInfoAtURL:(NSURL *)url serverDate:(NSDate **)outServerDate error:(NSError **)outError;
- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url withETag:(NSString *)ETag collectingRedirects:(NSMutableArray *)redirections options:(OFSDirectoryEnumerationOptions)options serverDate:(NSDate **)outServerDate error:(NSError **)outError;

- (BOOL)deleteURL:(NSURL *)url withETag:(NSString *)ETag error:(NSError **)outError;

@end
