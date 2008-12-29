// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDirectory.h>

#import <OmniFoundation/OFFile.h>

RCS_ID("$Id$")

@implementation OFDirectory

+ directoryWithPath:(NSString *)aDirectoryPath;
{
    return [[[self alloc] initWithPath:aDirectoryPath] autorelease];
}

+ directoryWithFile:(OFFile *)aFile;
{
    return [[[self alloc] initWithFile:aFile] autorelease];
}

- initWithPath:(NSString *)aDirectoryPath;
{
    if (![super init])
	return nil;

    path = [aDirectoryPath retain];

    return self;
}

- initWithFile:(OFFile *)aFile;
{
    return [self initWithPath:[aFile path]];
}

- (void)dealloc;
{
    [path release];
    [sortedFiles release];
    [super dealloc];
}

- (NSString *)path;
{
    return path;
}

- (NSArray *)files;
{
    return nil;
}

- (NSArray *)sortedFiles;
{
    if (sortedFiles)
	return sortedFiles;
    sortedFiles = [[[self files] sortedArrayUsingSelector:@selector(compare:)] retain];
    return sortedFiles;
}

- (BOOL)containsFileNamed:(NSString *)aName;
{
    NSArray                    *files;
    unsigned int                fileIndex, fileCount;
    
    files = [self files];
    fileCount = [files count];
    for (fileIndex = 0; fileIndex < fileCount; fileIndex++)
	if ([[(OFFile *)[files objectAtIndex:fileIndex] name]
	     isEqualToString:aName])
	    return YES;
    return NO;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary        *debugDictionary;
    NSArray                    *files;
    
    debugDictionary = [super debugDictionary];

    files = [self files];
    if (path)
	[debugDictionary setObject:path forKey:@"path"];
    if (files)
	[debugDictionary setObject:files forKey:@"files"];

    return debugDictionary;
}

@end

@implementation OFMutableDirectory

- initWithPath:(NSString *)aDirectoryPath;
{
    if (![super initWithPath:aDirectoryPath])
	return nil;
    files = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc;
{
    [files release];
    [super dealloc];
}

- (NSArray *)files;
{
    return files;
}

- (void)setPath:(NSString *)aPath;
{
    if (path == aPath)
	return;
    [path release];
    path = [aPath retain];
}

- (void)setFiles:(NSMutableArray *)someFiles;
{
    if (files == someFiles)
	return;
    [files release];
    files = [someFiles retain];
}

- (void)addFile:(OFFile *)aFile;
{
    [files addObject:aFile];
}

@end
