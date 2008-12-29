// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSFileManager.h>

@interface NSFileManager (OFTemporaryPath)

- (NSString *)temporaryPathForWritingToPath:(NSString *)path allowOriginalDirectory:(BOOL)allowOriginalDirectory error:(NSError **)outError;
- (NSString *)temporaryPathForWritingToPath:(NSString *)path allowOriginalDirectory:(BOOL)allowOriginalDirectory create:(BOOL)create error:(NSError **)outError;
- (NSString *)temporaryDirectoryForFileSystemContainingPath:(NSString *)path error:(NSError **)outError;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSURL *)specialDirectory:(OSType)whatDirectoryType forFileSystemContainingPath:(NSString *)path create:(BOOL)createIfMissing error:(NSError **)outError;
#endif

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

- (NSString *)uniqueFilenameFromName:(NSString *)filename error:(NSError **)outError;
- (NSString *)uniqueFilenameFromName:(NSString *)filename allowOriginal:(BOOL)allowOriginal create:(BOOL)create error:(NSError **)outError;
// Generate a unique filename based on a suggested name


@end
