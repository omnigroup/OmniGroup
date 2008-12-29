// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUnixDirectory.h>

#import <OmniFoundation/OFUnixFile.h>
#import <OmniFoundation/OFUtilities.h>

RCS_ID("$Id$")

@implementation OFUnixDirectory

- (void)dealloc;
{
    [files release];
    [super dealloc];
}

- (void)scanDirectory;
{
    NSFileManager *manager;
    NSArray *directoryContents;
    NSEnumerator *filenameEnum;
    NSString *filename;

    [files release];

    OFLockRegion_Begin(fileOpsLock);

    manager = [NSFileManager defaultManager];
    directoryContents = [manager directoryContentsAtPath:[[self path] stringByExpandingTildeInPath]];
    if (!directoryContents)
        [NSException raise:OFUnixDirectoryCannotReadDirectoryException format:@"Cannot read directory at %@", [self path]];

    files = [[NSMutableArray alloc] init];

    filenameEnum = [directoryContents objectEnumerator];
    while ((filename = [filenameEnum nextObject]))
	[files addObject:[OFUnixFile fileWithDirectory:self name:filename]];

    OFLockRegion_End(fileOpsLock);
}

- (NSArray *)files;
{
    if (!files)
        [self scanDirectory];
    return files;
}

- (BOOL)copyToPath:(NSString *)destinationPath error:(NSError **)outError;
{
    BOOL retval = NO;

    OFLockRegion_Begin(fileOpsLock);
    retval = [[NSFileManager defaultManager] copyItemAtPath:[self path] toPath:destinationPath error:outError];
    OFLockRegion_End(fileOpsLock);
    return retval;
}

@end

NSString * const OFUnixDirectoryCannotReadDirectoryException = @"OFUnixDirectoryCannotReadDirectoryException";
