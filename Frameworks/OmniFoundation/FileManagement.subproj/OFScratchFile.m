// Copyright 1997-2005, 2007-2008, 2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFScratchFile.h>

#import <OmniFoundation/NSFileManager-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFScratchFile
{
    NSURL *_fileURL;
    NSData *contentData;
    NSString *contentString;
    NSMutableArray *retainedObjects;
}

+ (OFScratchFile *)scratchFileNamed:(NSString *)aName error:(NSError **)outError;
{
    NSString *fileName = [[NSFileManager defaultManager] scratchFilenameNamed:aName error:outError];
    if (!fileName)
        return nil;
    return [[[self alloc] initWithFileURL:[NSURL fileURLWithPath:fileName isDirectory:NO]] autorelease];
}

+ (OFScratchFile *)scratchDirectoryNamed:(NSString *)aName error:(NSError **)outError;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *scratchFilename = [fileManager scratchFilenameNamed:aName error:outError];
    if (!scratchFilename)
        return nil;
    
    [fileManager removeItemAtPath:scratchFilename error:NULL];
    if (![fileManager createDirectoryAtPath:scratchFilename withIntermediateDirectories:YES attributes:nil error:outError])
        return nil;
    
    return [[[self alloc] initWithFileURL:[NSURL fileURLWithPath:scratchFilename isDirectory:YES]] autorelease];
}

- initWithFileURL:(NSURL *)fileURL;
{
    if (!(self = [super init]))
        return nil;

    _fileURL = [fileURL retain];
    
    retainedObjects = [[NSMutableArray alloc] init];

    return self;
}

- (void)dealloc;
{
    if (_fileURL)
        [[NSFileManager defaultManager] removeItemAtURL:_fileURL error:NULL];
    
    [_fileURL release];
    [contentData release];
    [contentString release];
    [retainedObjects release];
    [super dealloc];
}

- (NSData *)contentData;
{
    if (contentData)
	return contentData;
    
    contentData = [[NSData alloc] initWithContentsOfURL:_fileURL options:NSDataReadingMappedIfSafe error:NULL];

    return contentData;
}

- (NSString *)contentString;
{
    if (contentString)
	return contentString;
    contentString = [[NSString alloc] initWithData:[self contentData] encoding:NSISOLatin1StringEncoding];
    return contentString;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];

    if (_fileURL)
        dict[@"_fileURL"] = _fileURL;

    return dict;
}

@end
