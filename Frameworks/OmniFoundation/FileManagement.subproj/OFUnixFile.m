// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUnixFile.h>

#import <Foundation/NSLock.h>
#import <OmniBase/system.h> /* For readlink() */
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/FileManagement.subproj/OFUnixFile.m 103776 2008-08-06 01:00:30Z wiml $")

@implementation OFUnixFile

- initWithDirectory:(OFDirectory *)aDirectory name:(NSString *)aName
{
    if (![super initWithDirectory:aDirectory name:aName])
	return nil;

    hasInfo = NO;

    return self;
}

- (void)dealloc;
{
    [size release];
    [lastChanged release];
    [super dealloc];
}

- (void)getInfo;
{
    NSString *unixPath, *fileTypeString;
    NSDictionary *attributes;
    NSFileManager *manager;

    if (hasInfo)
	return;

    OFLockRegion_Begin(fileOpsLock);
    
    unixPath = [[self path] stringByExpandingTildeInPath];
    manager = [NSFileManager defaultManager];
    NSError *errBuf;
    
    
    attributes = [manager attributesOfItemAtPath:unixPath error:&errBuf];
    if (!attributes) {
        [NSException raise:OFUnixFileGenericFailureException format:@"Cannot get attributes for %@: %@", unixPath, errBuf];
    }

    fileTypeString = [attributes fileType];
    symLink = [fileTypeString isEqualToString:NSFileTypeSymbolicLink];
    if (symLink) {
        attributes = [manager attributesOfItemAtPath:unixPath traverseLink:YES error:NULL];
        fileTypeString = [attributes fileType];
    }

    if ([fileTypeString isEqualToString:NSFileTypeDirectory])
	fileType = OFFILETYPE_DIRECTORY;
    else if ([fileTypeString isEqualToString:NSFileTypeRegular])
        fileType = OFFILETYPE_REGULAR;
    else if ([fileTypeString isEqualToString:NSFileTypeSocket])
        fileType = OFFILETYPE_SOCKET;
    else if ([fileTypeString isEqualToString:NSFileTypeCharacterSpecial])
        fileType = OFFILETYPE_CHARACTER;
    else if ([fileTypeString isEqualToString:NSFileTypeBlockSpecial])
        fileType = OFFILETYPE_BLOCK;

    size = [[NSNumber alloc] initWithUnsignedLongLong:[attributes fileSize]];
    lastChanged = [[attributes fileModificationDate] retain];	
    hasInfo = YES;

    OFLockRegion_End(fileOpsLock);
}

- (BOOL)isDirectory;
{
    [self getInfo];
    return fileType == OFFILETYPE_DIRECTORY;
}

- (BOOL)isShortcut;
{
    [self getInfo];
    return symLink;
}

- (NSNumber *)size;
{
    [self getInfo];
    return size;
}

- (NSCalendarDate *)lastChanged
{
    [self getInfo];
    return lastChanged;
}

- (NSString *)shortcutDestination;
{
    NSString *retval = nil;
    NSError *errbuf = nil;

    OFLockRegion_Begin(fileOpsLock);
    retval = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:[[self path] stringByExpandingTildeInPath] error:&errbuf];
    OFLockRegion_End(fileOpsLock);
    
    if (!retval)
        [NSException raise:OFUnixFileGenericFailureException format:@"Cannot read symlink at %@: %@", [self path], errbuf];
    
    return retval;
}

- (BOOL)copyToPath:(NSString *)destinationPath error:(NSError **)outError;
{
    BOOL retval = NO;

    OFLockRegion_Begin(fileOpsLock);
    retval = [[NSFileManager defaultManager] copyItemAtPath:[[self path] stringByExpandingTildeInPath] toPath:destinationPath error:outError];
    OFLockRegion_End(fileOpsLock);
    return retval;
}

@end

NSString * const OFUnixFileGenericFailureException = @"OFUnixFileGenericFailureException";
