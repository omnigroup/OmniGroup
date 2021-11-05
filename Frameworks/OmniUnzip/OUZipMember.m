// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipMember.h>

#import <Foundation/NSFileWrapper.h>
#import <OmniUnzip/OUErrors.h>
#import <OmniUnzip/OUZipFileMember.h>
#import <OmniUnzip/OUZipDirectoryMember.h>
#import <OmniUnzip/OUZipLinkMember.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OUZipMember

- (instancetype)_initWithFileWrapper:(NSFileWrapper *)fileWrapper name:(NSString *)name;
{
    // This shouldn't be called on a concrete class.  That would imply the caller knew the type of the file wrapper, which it shouldn't bother with.
    OBPRECONDITION([self class] == [OUZipMember class]);
    OBPRECONDITION(![NSString isEmptyString:name]);
    
    if ([fileWrapper isRegularFile])
        return [[OUZipFileMember alloc] initWithName:name date:[[fileWrapper fileAttributes] fileModificationDate] contents:[fileWrapper regularFileContents]];

    if ([fileWrapper isSymbolicLink])
        return [[OUZipLinkMember alloc] initWithName:name date:[[fileWrapper fileAttributes] fileModificationDate] destination:[[fileWrapper symbolicLinkDestinationURL] path]];
    
    if ([fileWrapper isDirectory]) {
        OUZipDirectoryMember *directory = [[OUZipDirectoryMember alloc] initWithName:name date:[[fileWrapper fileAttributes] fileModificationDate] children:nil archive:YES];
        NSDictionary<NSString *, NSFileWrapper *> *childWrappers = [fileWrapper fileWrappers];
        NSArray <NSString *> *childKeys = [[childWrappers allKeys] sortedArrayUsingSelector:@selector(compare:)];
        
        for (NSString *childKey in childKeys) {
            NSFileWrapper *childWrapper = [childWrappers objectForKey:childKey];
            // Note: this loses the preferred filenames of our children, but zip files don't have a notion of preferred filename vs. actual filename the way file wrappers do
            OUZipMember *child = [[OUZipMember alloc] _initWithFileWrapper:childWrapper name:childKey];
            [directory addChild:child];
        }
        return directory;
    }
    
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (instancetype)initWithFileWrapper:(NSFileWrapper *)fileWrapper;
{
    return [self _initWithFileWrapper:fileWrapper name:[fileWrapper preferredFilename]];
}

// Returns a new autoreleased file wrapper; won't return the same wrapper on multiple calls
- (NSFileWrapper *)fileWrapperRepresentation;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (nullable instancetype)initWithPath:(NSString *)path fileManager:(NSFileManager *)fileManager outError:(NSError **)outError;
{
    // This shouldn't be called on a concrete class.  That would imply the caller knew the type of the file wrapper, which it shouldn't bother with.
    OBPRECONDITION([self class] == [OUZipMember class]);
    OBPRECONDITION(![NSString isEmptyString:[path lastPathComponent]]);

    NSString *preferredFilename = [path lastPathComponent];
    
    NSDictionary <NSString *, id> *fileAttributes = [fileManager attributesOfItemAtPath:path error:outError];
    if (!fileAttributes)
        return nil;
    
    NSString *fileType = [fileAttributes fileType];
    
    if ([fileType isEqualToString:NSFileTypeRegular])
        return [[OUZipFileMember alloc] initWithName:preferredFilename date:[fileAttributes fileModificationDate] mappedFilePath:path];

    if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
        NSString *destination = [fileManager destinationOfSymbolicLinkAtPath:path error:outError];
        if (!destination)
            return nil;
        return [[OUZipLinkMember alloc] initWithName:preferredFilename date:[fileAttributes fileModificationDate] destination:destination];
    }
    
    if ([fileType isEqualToString:NSFileTypeDirectory]) {
        OUZipDirectoryMember *directory = [[OUZipDirectoryMember alloc] initWithName:preferredFilename date:[fileAttributes fileModificationDate] children:nil archive:YES];
        NSArray<NSString *> *childNames = [fileManager contentsOfDirectoryAtPath:path error:outError];
        if (childNames == nil)
            return nil;

        NSUInteger childIndex, childCount = [childNames count];
        for (childIndex = 0; childIndex < childCount; childIndex++) {
            NSString *childName = [childNames objectAtIndex:childIndex];
            NSString *childPath = [path stringByAppendingPathComponent:childName];
            NSError *childError = nil;
            OUZipMember *child = [[OUZipMember alloc] initWithPath:childPath fileManager:fileManager outError:&childError];
            if (child == nil) {
                // Skip any failing children, but don't do it _completely_ silently
                NSLog(@"Unable to archive child path %@: %@", childPath, [childError toPropertyList]);
                continue;
            }
            [directory addChild:child];
        }
        return directory;
    }

    // Skip file types we don't know how to archive (sockets, character special, block special, and unknown)
    NSString *reason = [NSString stringWithFormat:@"%@: Unable to archive files of type %@", path, fileType];
    OmniUnzipError(outError, OmniUnzipUnknownFileType, @"Unable to archive unsupported file type", reason);
    return nil;
}

- (instancetype)initWithName:(NSString *)name date:(NSDate * _Nullable)date;
{
    // TODO: Convert some of these to error/exceptions
    OBPRECONDITION(![NSString isEmptyString:name]);
    OBPRECONDITION([self class] != [OUZipMember class]);
    
    if (!(self = [super init]))
        return nil;

    _name = [name copy];
    _date = [date copy];

    return self;
}

- (BOOL)appendToZipArchive:(OUZipArchive *)zip fileNamePrefix:(NSString * _Nullable)fileNamePrefix error:(NSError **)outError;
{
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}

- (NSComparisonResult)localizedCaseInsensitiveCompareByName:(OUZipMember *)otherMember;
{
    return [_name localizedCaseInsensitiveCompare:[otherMember name]];
}

- (NSString *)debugDescription;
{
    return [NSString stringWithFormat:@"<%@:%p \"%@\">", NSStringFromClass([self class]), self, _name];
}

@end

NS_ASSUME_NONNULL_END
