// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipFileMember.h>

#import <OmniUnzip/OUZipArchive.h>
#import <OmniUnzip/OUErrors.h>
#import <Foundation/NSFileWrapper.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OUZipFileMember
{
    NSData *_contents;
    NSString *_filePath;
}

- (instancetype)initWithName:(NSString *)name date:(NSDate *)date contents:(NSData *)contents;
{
    if (!(self = [super initWithName:name date:date]))
        return nil;
    
    _contents = [contents copy];
    
    return self;
}

- (instancetype)initWithName:(NSString *)name date:(NSDate *)date mappedFilePath:(NSString *)filePath;
{
    if (!(self = [super initWithName:name date:date]))
        return nil;
    
    _filePath = [filePath copy];
    
    return self;
}

- (nullable NSData *)contents;
{
    __autoreleasing NSError *error = nil;
    NSData *data = [self contents:&error];
    if (!data) {
        [error log:@"Unable to read contents of \"%@\"", _filePath];
        return nil;
    }
    return data;
}

- (nullable NSData *)contents:(NSError **)outError;
{
    if (_contents != nil) {
        return _contents;
    }

    return [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:_filePath] options:NSDataReadingMappedIfSafe error:outError];
}

#pragma mark - OUZipMember subclass

- (NSFileWrapper *)fileWrapperRepresentation;
{
    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:[self contents]];
    [wrapper setFilename:[self name]];
    [wrapper setPreferredFilename:[self name]];
    return wrapper;
}

#pragma mark - OUZipMember subclass

- (BOOL)appendToZipArchive:(OUZipArchive *)zip fileNamePrefix:(NSString * _Nullable)fileNamePrefix error:(NSError **)outError;
{
    NSString *name = [self name];
    if (![NSString isEmptyString:fileNamePrefix])
        name = [fileNamePrefix stringByAppendingFormat:@"/%@", name];
    
    return [zip appendEntryNamed:name fileType:NSFileTypeRegular contents:[self contents] date:[self date] error:outError];
}

@end

NS_ASSUME_NONNULL_END
