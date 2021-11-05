// Copyright 2014-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFileEdit.h>

#import <OmniFoundation/NSDate-OFExtensions.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OFFileEdit

// Here we assume the caller is either looking at a file that shouldn't be edited by anyone else while we are looking (in a tmp directory), or that the caller is in the midst of file coordination on this fileURL.
- (nullable instancetype)initWithFileURL:(NSURL *)fileURL error:(NSError **)outError;
{
    return [self initWithFileURL:fileURL withDeepModificationDate:NO error:outError];
}

// This is a slightly better effort for supporting packages where interior members may be edited w/o generating a new inode for the file package (or possilby even modification date).
- (nullable instancetype)initWithFileURL:(NSURL *)fileURL withDeepModificationDate:(BOOL)deepModificationDate error:(NSError **)outError;
{
#ifdef DEBUG_bungi0
    OBPRECONDITION([NSThread isMainThread] == NO, "Are we inside file coordination?");
#endif

    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path]  error:outError];
    if (!attributes)
        return nil;

    BOOL isDirectory = [attributes[NSFileType] isEqual:NSFileTypeDirectory];

    self = [self initWithFileURL:fileURL fileModificationDate:attributes.fileModificationDate inode:attributes.fileSystemFileNumber isDirectory:isDirectory];

    if (deepModificationDate) {
        if (isDirectory) {
            NSDate *newestDate = _fileModificationDate;

            NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:fileURL includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
                [error log:@"Error enumerating at %@", url];
                return YES; // Continue anyway
            }];
            for (NSURL *childURL in enumerator) {
                __autoreleasing NSError *enumError = nil;
                __autoreleasing NSDate *childModificationDate;

                if (![childURL getResourceValue:&childModificationDate forKey:NSURLContentModificationDateKey error:&enumError]) {
                    [enumError log:@"Error getting child modification date at %@", childURL];
                }
                if ([childModificationDate isAfterDate:newestDate]) {
                    newestDate = childModificationDate;
                }
            }
            _deepModificationDate = newestDate;
        } else {
            _deepModificationDate = _fileModificationDate;
        }
    }

    return self;
}

// Here we assume that the inputs were previously read under file coordination and so are consistent.
- (instancetype)initWithFileURL:(NSURL *)fileURL fileModificationDate:(NSDate *)fileModificationDate inode:(NSUInteger)inode isDirectory:(BOOL)isDirectory;
{
    OBPRECONDITION(fileURL);
    OBPRECONDITION(fileModificationDate);
    OBPRECONDITION(inode);
    
    self = [super init];
    
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
- (id)copyWithZone:(NSZone * _Nullable)zone;
{
    return self;
}

#pragma mark - Comparison

- (NSUInteger)hash;
{
    return [_originalFileURL hash] ^ [_fileModificationDate hash] ^ _inode ^ _directory ^ [_deepModificationDate hash];
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[OFFileEdit class]]) {
        return NO;
    }
    OFFileEdit *otherEdit = otherObject;
    if (![_originalFileURL isEqual:otherEdit->_originalFileURL] || ![_fileModificationDate isEqual:otherEdit->_fileModificationDate] || _inode != otherEdit->_inode || _directory != otherEdit->_directory) {
        return NO;
    }
    if (OFNOTEQUAL(_deepModificationDate, otherEdit->_deepModificationDate)) {
        return NO;
    }
    return YES;
}

#pragma mark - Debugging

- (NSString *)debugDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@ date:%@, deep:%@, inode:%lu, directory:%d", NSStringFromClass([self class]), self, _originalFileURL, _fileModificationDate, _deepModificationDate, _inode, _directory];
}

@end

NS_ASSUME_NONNULL_END
