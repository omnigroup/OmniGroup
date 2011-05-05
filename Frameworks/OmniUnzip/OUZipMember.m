// Copyright 2008, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipMember.h>

#import <OmniUnzip/OUZipFileMember.h>
#import <OmniUnzip/OUZipDirectoryMember.h>
#import <OmniUnzip/OUZipLinkMember.h>

RCS_ID("$Id$");

@implementation OUZipMember

- (id)_initWithFileWrapper:(OFFileWrapper *)fileWrapper name:(NSString *)name;
{
    // This shouldn't be called on a concrete class.  That would imply the caller knew the type of the file wrapper, which it shouldn't bother with.
    OBPRECONDITION([self class] == [OUZipMember class]);
    OBPRECONDITION(![NSString isEmptyString:name]);
    
    if ([fileWrapper isRegularFile]) {
        [self release];
        return [[OUZipFileMember alloc] initWithName:name date:[[fileWrapper fileAttributes] fileModificationDate] contents:[fileWrapper regularFileContents]];
    } else if ([fileWrapper isSymbolicLink]) {
        [self release];
        return [[OUZipLinkMember alloc] initWithName:name date:[[fileWrapper fileAttributes] fileModificationDate] destination:[fileWrapper symbolicLinkDestination]];
    } else if ([fileWrapper isDirectory]) {
        [self release];

        OUZipDirectoryMember *directory = [[OUZipDirectoryMember alloc] initWithName:name date:[[fileWrapper fileAttributes] fileModificationDate] children:nil archive:YES];
        NSDictionary *childWrappers = [fileWrapper fileWrappers];
        NSArray *childKeys = [[childWrappers allKeys] sortedArrayUsingSelector:@selector(compare:)];
        
        for (NSString *childKey in childKeys) {
            OFFileWrapper *childWrapper = [childWrappers objectForKey:childKey];
            // Note: this loses the preferred filenames of our children, but zip files don't have a notion of preferred filename vs. actual filename the way file wrappers do
            OUZipMember *child = [[OUZipMember alloc] _initWithFileWrapper:childWrapper name:childKey];
            [directory addChild:child];
            [child release];
        }
        return directory;
    }
    
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- initWithFileWrapper:(OFFileWrapper *)fileWrapper;
{
    return [self _initWithFileWrapper:fileWrapper name:[fileWrapper preferredFilename]];
}

// Returns a new autoreleased file wrapper; won't return the same wrapper on multiple calls
- (OFFileWrapper *)fileWrapperRepresentation;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- initWithPath:(NSString *)path fileManager:(NSFileManager *)fileManager;
{
    // This shouldn't be called on a concrete class.  That would imply the caller knew the type of the file wrapper, which it shouldn't bother with.
    OBPRECONDITION([self class] == [OUZipMember class]);
    OBPRECONDITION(![NSString isEmptyString:[path lastPathComponent]]);

    [self release]; self = nil; // We won't be returning an abstract class
    OB_UNUSED_VALUE(self);
    
    NSString *preferredFilename = [path lastPathComponent];
    
    NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:path error:NULL];
    if (!fileAttributes)
        return nil;
        
    if ([[fileAttributes fileType] isEqualToString:NSFileTypeRegular]) {
        return [[OUZipFileMember alloc] initWithName:preferredFilename date:[fileAttributes fileModificationDate] mappedFilePath:path];
    } else if ([[fileAttributes fileType] isEqualToString:NSFileTypeSymbolicLink]) {
        NSString *destination = [fileManager destinationOfSymbolicLinkAtPath:path error:NULL];
        if (!destination)
            return nil;
        return [[OUZipLinkMember alloc] initWithName:preferredFilename date:[fileAttributes fileModificationDate] destination:destination];
    } else if ([[fileAttributes fileType] isEqualToString:NSFileTypeDirectory]) {
        OUZipDirectoryMember *directory = [[OUZipDirectoryMember alloc] initWithName:preferredFilename date:[fileAttributes fileModificationDate] children:nil archive:YES];
        NSArray *childNames = [fileManager contentsOfDirectoryAtPath:path error:NULL];
        NSUInteger childIndex, childCount = [childNames count];
        for (childIndex = 0; childIndex < childCount; childIndex++) {
            NSString *childName = [childNames objectAtIndex:childIndex];
            NSString *childPath = [path stringByAppendingPathComponent:childName];
            OUZipMember *child = [[OUZipMember alloc] initWithPath:childPath fileManager:fileManager];
            if (child == nil)
                continue;
            [directory addChild:child];
            [child release];
        }
        return directory;
    } else {
        // Silently skip file types we don't know how to archive (sockets, character special, block special, and unknown)
        return nil;
    }
}

- initWithName:(NSString *)name date:(NSDate *)date;
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

- (void)dealloc;
{
    [_name release];
    [_date release];
    [super dealloc];
}

- (NSString *)name;
{
    return _name;
}

- (NSDate *)date;
{
    return _date;
}

- (BOOL)appendToZipArchive:(OUZipArchive *)zip fileNamePrefix:(NSString *)fileNamePrefix error:(NSError **)outError;
{
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}

- (NSComparisonResult)localizedCaseInsensitiveCompareByName:(OUZipMember *)otherMember;
{
    return [_name localizedCaseInsensitiveCompare:[otherMember name]];
}

@end
