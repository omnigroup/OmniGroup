// Copyright 2008, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipFileMember.h>

#import <OmniUnzip/OUZipArchive.h>
#import <OmniUnzip/OUErrors.h>

RCS_ID("$Id$");

@implementation OUZipFileMember

- initWithName:(NSString *)name date:(NSDate *)date contents:(NSData *)contents;
{
    if (!(self = [super initWithName:name date:date]))
        return nil;
    
    _contents = [contents copy];
    
    return self;
}

- initWithName:(NSString *)name date:(NSDate *)date mappedFilePath:(NSString *)filePath;
{
    if (!(self = [super initWithName:name date:date]))
        return nil;
    
    _filePath = [filePath copy];
    
    return self;
}

- (void)dealloc;
{
    [_contents release];
    [_filePath release];
    [super dealloc];
}

- (NSData *)contents;
{
    if (_contents != nil)
        return _contents;
    else
        return [NSData dataWithContentsOfMappedFile:_filePath];
}

#pragma mark -
#pragma mark OUZipMember subclass

- (OFFileWrapper *)fileWrapperRepresentation;
{
    OFFileWrapper *wrapper = [[[OFFileWrapper alloc] initRegularFileWithContents:[self contents]] autorelease];
    [wrapper setFilename:[self name]];
    [wrapper setPreferredFilename:[self name]];
    return wrapper;
}

#pragma mark -
#pragma mark OUZipMember subclass

- (BOOL)appendToZipArchive:(OUZipArchive *)zip fileNamePrefix:(NSString *)fileNamePrefix error:(NSError **)outError;
{
    NSString *name = [self name];
    if (![NSString isEmptyString:fileNamePrefix])
        name = [fileNamePrefix stringByAppendingFormat:@"/%@", name];
    
    return [zip appendEntryNamed:name fileType:NSFileTypeRegular contents:[self contents] date:[self date] error:outError];
}

@end
