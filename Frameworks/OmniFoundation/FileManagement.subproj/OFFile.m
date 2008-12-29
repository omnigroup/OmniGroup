// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFile.h>

#import <OmniFoundation/NSCalendarDate-OFExtensions.h>
#import <OmniFoundation/OFDirectory.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/FileManagement.subproj/OFFile.m 93428 2007-10-25 16:36:11Z kc $")

NSLock *fileOpsLock;

@implementation OFFile

+ (void)initialize
{
    OBINITIALIZE;

    fileOpsLock = [[NSRecursiveLock alloc] init];
}

+ fileWithDirectory:(OFDirectory *)aDirectory name:(NSString *)aName;
{
    return [[[self alloc] initWithDirectory:aDirectory name:aName] autorelease];
}

+ fileWithPath:(NSString *)aPath;
{
    return [[[self alloc] initWithPath:aPath] autorelease];
}

- initWithDirectory:(OFDirectory *)aDirectory name:(NSString *)aName;
{
    if (![super init])
	return nil;

    directory = [aDirectory retain];
    name = [aName retain];

    return self;
}

- initWithPath:(NSString *)aPath;
{
    return [self initWithDirectory:[OFDirectory directoryWithPath:[aPath stringByDeletingLastPathComponent]] name:[aPath lastPathComponent]];
}

- (void)dealloc;
{
    [directory release];
    [name release];
    [path release];
    [super dealloc];
}

- (NSString *)name;
{
    return name;
}

- (NSString *)path;
{
    if (!path)
	path = [[[directory path] stringByAppendingPathComponent:name] retain];
    return path;
}

- (BOOL)isDirectory;
{
    return NO;
}

- (BOOL)isShortcut;
{
    return NO;
}

- (NSNumber *)size;
{
    return nil;
}

- (NSCalendarDate *)lastChanged
{
    return nil;
}

- (NSComparisonResult)compare:(OFFile *)aFile;
{
    return [name compare:[aFile name] options:NSCaseInsensitiveSearch];
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(unsigned)level;
{
    return [[self path] description];
}

@end

@implementation OFMutableFile

- initWithDirectory:(OFDirectory *)aDirectory name:(NSString *)aName;
{
    if (![super initWithDirectory:aDirectory name:aName])
	return nil;

    flags.isDirectory = NO;
    flags.isShortcut = NO;
    size = nil;

    return self;
}

- (void)dealloc;
{
    [size release];
    [lastChanged release];
    [super dealloc];
}

- (BOOL)isDirectory;
{
    return flags.isDirectory;
}

- (BOOL)isShortcut;
{
    return flags.isShortcut;
}

- (NSNumber *)size;
{
    return size;
}

- (NSCalendarDate *)lastChanged
{
    return lastChanged;
}

- (void)setIsDirectory:(BOOL)shouldBeDirectory;
{
    flags.isDirectory = shouldBeDirectory;
}

- (void)setIsShortcut:(BOOL)shouldBeShortcut;
{
    flags.isShortcut = shouldBeShortcut;
}

- (void)setSize:(NSNumber *)aSize;
{
    if (size == aSize)
	return;
    [size release];
    size = [aSize retain];
}

- (void)setLastChanged:(NSCalendarDate *)aDate;
{
    if (lastChanged == aDate)
	return;
    [lastChanged release];
    lastChanged = [aDate retain];
    [lastChanged setToUnixDateFormat];
}

- (void)setPath:(NSString *)aPath;
{
    if (path == aPath)
	return;
    [path release];
    path = [aPath retain];
}

@end
