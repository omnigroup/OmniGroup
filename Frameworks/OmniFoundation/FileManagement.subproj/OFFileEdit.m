// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFileEdit.h>

#import <OmniFoundation/NSDate-OFExtensions.h>

RCS_ID("$Id$");

@implementation OFFileEdit

// Here we assume the caller is either looking at a file that shouldn't be edited by anyone else while we are looking (in a tmp directory), or that the caller is in the midst of file coordination on this fileURL.
- (instancetype)initWithFileURL:(NSURL *)fileURL error:(NSError **)outError;
{
#ifdef DEBUG_bungi
    OBPRECONDITION([NSThread isMainThread] == NO, "Are we inside file coordination?");
#endif
    
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path]  error:outError];
    if (!attributes)
        return nil;
    
    BOOL isDirectory = [attributes[NSFileType] isEqual:NSFileTypeDirectory];
    
    return [self initWithFileURL:fileURL fileModificationDate:attributes.fileModificationDate inode:attributes.fileSystemFileNumber isDirectory:isDirectory];
}

// Here we assume that the inputs were previously read under file coordination and so are consistent.
- (instancetype)initWithFileURL:(NSURL *)fileURL fileModificationDate:(NSDate *)fileModificationDate inode:(NSUInteger)inode isDirectory:(BOOL)isDirectory;
{
    OBPRECONDITION(fileURL);
    OBPRECONDITION(fileModificationDate);
    OBPRECONDITION(inode);
    
    if (!(self = [super init]))
        return nil;
    
    _originalFileURL = [fileURL copy];
    _fileModificationDate = [fileModificationDate copy];
    _inode = inode;
    _directory = isDirectory;
    
    return self;
}

@synthesize uniqueEditIdentifier = _uniqueEditIdentifier;
- (NSString *)uniqueEditIdentifier;
{
    // The globally unique edit identifier for local files is their inode + filesystem modification date. This will be valid across moves w/o any extra work (in particular, this is used for the preview cache key on iOS).
    
    // Not using NSURLGenerationIdentifierKey for now, though it sounds almost perfect. We expect documents to be saved using new file wrappers, so the inode/timestamp should change with a high level of confidence. The main issue with NSURLGenerationIdentifierKey isn't really an issue right now, but it doesn't get updated when xattrs are changed. We should sync some xattrs later, so let's not depend on this...
    // NSURLDocumentIdentifierKey is unique w/in a filesystem, persists across safe saves. We actually don't *want* it to persist across safe-saves since we want to detect edits, so not using that either.
    // NSURLFileResourceIdentifierKey is for comparing whether two resources are the same, but it doesn't persist across system restarts.
    
    // So, we just use the combination of the modification date and inode.
    if (!_uniqueEditIdentifier) {
        _uniqueEditIdentifier = [[NSString alloc] initWithFormat:@"%ld-%@", _inode, _fileModificationDate.xmlString];
    }
    return _uniqueEditIdentifier;
}

#pragma mark - NSCopying

// We (and our subclass) are immutable.
- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

#pragma mark - Debugging

- (NSString *)debugDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@ date:%@, inode:%lu, directory:%d", NSStringFromClass([self class]), self, _originalFileURL, _fileModificationDate, _inode, _directory];
}

@end

