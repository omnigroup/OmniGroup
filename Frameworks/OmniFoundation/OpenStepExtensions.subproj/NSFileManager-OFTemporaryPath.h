// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFileManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSFileManager (OFTemporaryPath)

- (nullable NSURL *)temporaryDirectoryForFileSystemContainingURL:(NSURL *)fileURL error:(NSError **)outError;

// This returns a new URL that does not exist (but that should be relatively race free vs other callers as it contains a random identifier instead of an incrementing number). The path based versions below use a sequence number, checking if the file exists. Two calls in a row that are intended to return two temporary names could then return the same one twice.
- (nullable NSURL *)temporaryURLForWritingToURL:(NSURL *)originalURL allowOriginalDirectory:(BOOL)allowOriginalDirectory error:(NSError **)outError;

- (nullable NSString *)temporaryPathForWritingToPath:(NSString *)path allowOriginalDirectory:(BOOL)allowOriginalDirectory error:(NSError **)outError;
- (nullable NSString *)temporaryPathForWritingToPath:(NSString *)path allowOriginalDirectory:(BOOL)allowOriginalDirectory create:(BOOL)create error:(NSError **)outError;
- (nullable NSString *)temporaryDirectoryForFileSystemContainingPath:(NSString *)path error:(NSError **)outError;

- (NSString *)tempFilenameFromTemplate:(NSString *)inputString
                              andRange:(NSRange)replaceRange;
// Create a unique temp filename from a template filename, given a range within the template filename which identifies where the unique portion of the filename is to lie.

- (NSString *)tempFilenameFromTemplate:(NSString *)inputString
                           andPosition:(int)position;
// Create a unique temp filename from a template string, given a position within the template filename which identifies where the unique portion of the filename is to begin.

- (NSString *)tempFilenameFromTemplate:(NSString *)inputString
                          andSubstring:(NSString *)substring;
// Create a unique temp filename from a template string, given a substring within the template filename which is to be replaced by the unique portion of the filename.

- (NSString *)tempFilenameFromHashesTemplate:(NSString *)inputString;
// Create a unique temp filename from a template string which contains a substring of six hash marks which are to be replaced by the unique portion of the filename.

- (nullable NSString *)uniqueFilenameFromName:(NSString *)filename error:(NSError **)outError;
- (nullable NSString *)uniqueFilenameFromName:(NSString *)filename allowOriginal:(BOOL)allowOriginal create:(BOOL)create error:(NSError **)outError;
// Generate a unique filename based on a suggested name

- (BOOL)replaceFileAtPath:(NSString *)originalFile withFileAtPath:(NSString *)newFile error:(NSError **)outError;
- (BOOL)exchangeFileAtPath:(NSString *)originalFile withFileAtPath:(NSString *)newFile error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
