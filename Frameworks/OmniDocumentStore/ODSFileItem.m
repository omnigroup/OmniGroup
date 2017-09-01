// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSFileItem.h>

#import <Foundation/NSFileCoordinator.h>
#import <Foundation/NSOperation.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSScope-Subclass.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFoundation/OFFileEdit.h>
#import <OmniFoundation/OFUTI.h>

#import "ODSFileItem-Internal.h"
#import "ODSItem-Internal.h"
#import "ODSScope-Internal.h"


RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_FILE_ITEM_ENABLED 1
    #define DEBUG_FILE_ITEM(format, ...) NSLog(@"FILE ITEM %@: " format, [self shortDescription], ## __VA_ARGS__)
#else
    #define DEBUG_FILE_ITEM(format, ...)
#endif

OBDEPRECATED_METHOD(-initWithScope:fileURL:isDirectory:fileModificationDate:userModificationDate:);

NSString * const ODSFileItemFileURLBinding = @"fileURL";
NSString * const ODSFileItemFileTypeBinding = @"fileType";
NSString * const ODSFileItemDownloadRequestedBinding = @"downloadRequested";

@interface ODSFileItem ()
@property(nonatomic) BOOL downloadRequested;
@property(readwrite,nonatomic) NSURL *fileURL;
@property(readwrite,nonatomic) NSString *fileType;
@end

NSString * const ODSFileItemContentsChangedNotification = @"ODSFileItemContentsChanged";
NSString * const ODSFileItemFinishedDownloadingNotification = @"ODSFileItemFinishedDownloading";
NSString * const ODSFileItemInfoKey = @"fileItem";

@implementation ODSFileItem
{
    NSURL *_fileURL;
    BOOL _isDirectory;
    
    // ivars for properties in the ODSItem protocol
    BOOL _hasDownloadQueued;
    BOOL _isDownloaded;
    BOOL _isDownloading;
    BOOL _isUploaded;
    BOOL _isUploading;
    
    uint64_t _totalSize;
    uint64_t _downloadedSize;
    uint64_t _uploadedSize;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBASSERT(OBClassImplementingMethod(self, @selector(name)) == [ODSFileItem class]); // Subclass +displayNameForFileURL:fileType: instead.
    OBASSERT(OBClassImplementingMethod(self, @selector(editingName)) == [ODSFileItem class]); // Subclass +editingNameForFileURL:fileType: instead.
}

+ (NSString *)displayNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
{
    return [self editingNameForFileURL:fileURL fileType:fileType];
}

+ (NSString *)editingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
{
    return [[[fileURL path] lastPathComponent] stringByDeletingPathExtension];
}

+ (NSString *)exportingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
{
    return [self displayNameForFileURL:fileURL fileType:fileType];
}

- initWithScope:(ODSScope *)scope fileURL:(NSURL *)fileURL isDirectory:(BOOL)isDirectory fileEdit:(OFFileEdit *)fileEdit userModificationDate:(NSDate *)userModificationDate;
{
    OBPRECONDITION(scope);
    OBPRECONDITION(fileURL);
    OBPRECONDITION([fileURL isFileURL]);
    // OBPRECONDITION(fileEdit); // This is nil for files that haven't been downloaded (since we don't publish stub files any more).
    OBPRECONDITION(userModificationDate);
    OBPRECONDITION(scope.documentStore);
    OBPRECONDITION([scope isFileInContainer:fileURL] || scope.documentsURL == nil);
    // OBPRECONDITION(isDirectory == [[fileURL absoluteString] hasSuffix:@"/"]); // We can't compute isDirectory here based on the filesystem state since the file URL might not currently exist (if it represents a non-downloaded file in a cloud scope). However, it's not clear that we can rely on always having a / suffix in our URLs either, since the URL might be a security scoped resource that we need to preserve in its original form.
    
    if (!fileURL) {
        OBASSERT_NOT_REACHED("Bad caller");
        return nil;
    }
    
    // NOTE: ODSFileItem CANNOT keep a pointer to an OFXFileItem (since when generating conflict versions the URL of the file item doesn't change). See -[OFXFileItem _generateConflictDocumentAndRevertToTemporaryDocumentContentsAtURL:coordinator:error:].

    if (!(self = [super initWithScope:scope]))
        return nil;
    
    _fileURL = [fileURL copy];
    _isDirectory = isDirectory;
    _fileEdit = [fileEdit copy];
    
    OBASSERT(!_fileEdit || _fileEdit.directory == _isDirectory); // Might not be downloaded, but if it is, these should agree.
    
    _userModificationDate = [userModificationDate copy];

    // We might represent a file that isn't downloaded and not locally present, so we can't look up the directory-ness of the file ourselves.
    _fileType = [OFUTIForFileExtensionPreferringNative([_fileURL pathExtension], @(isDirectory)) copy];
    OBASSERT(_fileType);
    OBASSERT([_fileType hasPrefix:@"dyn."] == NO, "We should not be looking at files we don't know the type of");

    // Reasonable values for local documents that will never get updated by a sync container agent.
    _hasDownloadQueued = kODSFileItemDefault_HasDownloadQueued;
    _isDownloaded = kODSFileItemDefault_IsDownloaded;
    _isDownloading = kODSFileItemDefault_IsDownloading;
    _isUploaded = kODSFileItemDefault_IsUploaded;
    _isUploading = kODSFileItemDefault_IsUploading;

    return self;
}

- (NSURL *)fileURL;
{
    // OBPRECONDITION([NSThread isMainThread]); This gets called by the preview generation queue, so we need to make this minimally thread-safe.
    
    NSURL *fileURL;
    @synchronized(self) {
        fileURL = _fileURL;
    }
    OBASSERT(fileURL);
    
    return fileURL;
}
- (void)setFileURL:(NSURL *)fileURL;
{
    OBPRECONDITION([NSThread isMainThread]); // Send KVO on the main thread only
    OBPRECONDITION(fileURL);
    
    // but lock vs. any background reader
    @synchronized(self) {
        if (OFNOTEQUAL(_fileURL, fileURL)) {
            [self willChangeValueForKey:ODSFileItemFileURLBinding];
            _fileURL = fileURL;
            [self didChangeValueForKey:ODSFileItemFileURLBinding];
            
            // OFUTIForFileURLPreferringNative() checks the filesystem, but this might be a not yet downloaded file item. We assume here that a rename doesn't change between flat file and directory.
            OBASSERT(!_fileEdit || _fileEdit.directory == _isDirectory); // Might not be downloaded, but if it is, these should agree.
            NSString *uti = OFUTIForFileExtensionPreferringNative([_fileURL pathExtension], @(_isDirectory));
            OBASSERT(uti);
            if (uti)
                [self setFileType:uti];
        }
    }
}

@synthesize fileType = _fileType; // Just makes the ivar since we implement both accessors.
- (NSString *)fileType;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_fileType);
    return _fileType;
}
- (void)setFileType:(NSString *)fileType;
{
    OBPRECONDITION([NSThread isMainThread]); // Send KVO on the main thread only
    OBPRECONDITION(fileType);
    OBPRECONDITION([fileType hasPrefix:@"dyn."] == NO, "We should not be looking at files we don't know the type of");
    
    @synchronized(self) {
        if (OFNOTEQUAL(_fileType, fileType)) {
            [self willChangeValueForKey:ODSFileItemFileTypeBinding];
            _fileType = fileType;
            [self didChangeValueForKey:ODSFileItemFileTypeBinding];
        }
    }
}

- (NSData *)emailData;
{
    return [NSData dataWithContentsOfURL:self.fileURL];
}

- (NSString *)emailFilename;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    return [[self.fileURL path] lastPathComponent];
}

- (NSData *)dataForWritingToExternalStorage
{
    return nil;
}

- (NSString *)editingName;
{
    OBPRECONDITION([NSThread isMainThread]);

    return [[self class] editingNameForFileURL:self.fileURL fileType:self.fileType];
}

- (NSString *)exportingName;
{
    OBPRECONDITION([NSThread isMainThread]);

    return [[self class] exportingNameForFileURL:self.fileURL fileType:self.fileType];
}

+ (NSSet *)keyPathsForValuesAffectingName;
{
    return [NSSet setWithObjects:ODSFileItemFileURLBinding, nil];
}

- (NSComparisonResult)compare:(ODSFileItem *)otherItem;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // First, compare dates
    NSComparisonResult dateComparison = [self.userModificationDate compare:otherItem.userModificationDate];
    switch (dateComparison) {
        default: case NSOrderedSame:
            break;
        case NSOrderedAscending:
            return NSOrderedDescending; // Newer documents come first
        case NSOrderedDescending:
            return NSOrderedAscending; // Newer documents come first
    }

    // Then compare name and if the names are equal, duplication counters.
    __autoreleasing NSString *name1;
    __autoreleasing NSString *name2;
    NSUInteger counter1, counter2;
    
    [self.name splitName:&name1 andCounter:&counter1];
    [otherItem.name splitName:&name2 andCounter:&counter2];
    
    

    NSComparisonResult caseInsensitiveCompare = [name1 localizedCaseInsensitiveCompare:name2];
    if (caseInsensitiveCompare != NSOrderedSame)
        return caseInsensitiveCompare; // Sort names into alphabetical order

    // Use the duplication counters, in reverse order ("Foo 2" should be to the left of "Foo").
    if (counter1 < counter2)
        return NSOrderedDescending;
    else if (counter1 > counter2)
        return NSOrderedAscending;
    
    // If all else is equal, compare URLs (maybe different extensions?). (If those are equal, so are the items!)
    return [[self.fileURL absoluteString] compare:[otherItem.fileURL absoluteString]];
}

#pragma mark - ODSItem protocol

- (NSString *)name;
{
    return [[self class] displayNameForFileURL:self.fileURL fileType:self.fileType];
}

- (ODSItemType)type;
{
    return ODSItemTypeFile;
}

+ (NSSet *)keyPathsForValuesAffectingFileModificationDate;
{
    NSString *keyPath = OFKeyPathWithClass(ODSFileItem, fileEdit);
    return [NSSet setWithObject:keyPath];
}
- (NSDate *)fileModificationDate;
{
    return _fileEdit.fileModificationDate;
}

- (void)setFileEdit:(OFFileEdit *)fileEdit;
{
    OBPRECONDITION([NSThread isMainThread]); // Ensure we are only firing KVO on the main thread
    
    _fileEdit = [fileEdit copy];
}

- (BOOL)isReady;
{
    return YES;
}

@synthesize hasDownloadQueued = _hasDownloadQueued;
@synthesize isDownloaded = _isDownloaded;
@synthesize isDownloading = _isDownloading;
@synthesize isUploaded = _isUploaded;
@synthesize isUploading = _isUploading;
@synthesize totalSize = _totalSize;

- (void)setIsDownloaded:(BOOL)isDownloaded;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (_isDownloaded == isDownloaded)
        return;
    
    BOOL finishedDownloading = (!_isDownloaded && isDownloaded);
    _isDownloaded = isDownloaded;
    
    if (finishedDownloading) {
        self.downloadRequested = NO;
        
        [self _queueContentsChanged];
    }
}

- (BOOL)requestDownload:(NSError **)outError;
{
    OBPRECONDITION([NSThread isMainThread]); // Only want to fire KVO on the main thread
    
    self.downloadRequested = YES;

    return [self.scope requestDownloadOfFileItem:self error:outError];
}

- (void)addFileItems:(NSMutableSet *)fileItems;
{
    [fileItems addObject:self];
}

- (void)eachItem:(void (^)(ODSItem *item))applier;
{
    applier(self);
}

- (void)eachFile:(void (^)(ODSFileItem *file))applier;
{
    applier(self);
}

- (void)eachFolder:(void (^)(ODSFolderItem *folder, BOOL *stop))applier;
{
    // Not us!
}

- (BOOL)inOrContainsItemIn:(NSSet *)items;
{
    return [items member:self] != nil;
}

- (ODSFolderItem *)parentFolderOfItem:(ODSItem *)item;
{
    return nil;
}

- (BOOL)hasFilename:(NSString *)filename;
{
    // Our 'name' has the path extension trimmed.
    return [_fileURL.lastPathComponent localizedStandardCompare:filename] == NSOrderedSame;
}

#pragma mark - ODSItem Internal

- (void)_addMotions:(NSMutableArray *)motions toParentFolderURL:(NSURL *)destinationFolderURL isTopLevel:(BOOL)isTopLevel usedFolderNames:(NSMutableSet *)usedFolderNames ignoringFileItems:(NSSet *)ignoredFileItems;
{
    if ([ignoredFileItems member:self])
        return;
    
    ODSFileItemMotion *motion;
    if (isTopLevel) {
        // We can't pick our URL if we are a top level file. This needs to be picked on the background copying queue.
        motion = [[ODSFileItemMotion alloc] initWithFileItem:self destinationFolderURL:nil];
    } else {
        // An ancestor folder has already picked a new name, so our destination path uniques us
        motion = [[ODSFileItemMotion alloc] initWithFileItem:self destinationFolderURL:destinationFolderURL];
    }
    
    [motions addObject:motion];
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    ODSScope *scope = self.scope;
    NSURL *documentsURL = scope.documentsURL;
    NSURL *fileURL = self.fileURL;
    NSString *relativePath = documentsURL != nil ? OFFileURLRelativePath(documentsURL, fileURL) : fileURL.path;
    return [NSString stringWithFormat:@"<%@:%p %@:'%@' date:%@>", NSStringFromClass([self class]), self, scope.identifier, relativePath, [self.userModificationDate xmlString]];
}

#pragma mark - Internal

// Called by our scope when it notices we've been moved.
- (void)didMoveToURL:(NSURL *)fileURL;
{
    self.fileURL = fileURL;
}

#pragma mark - Private

// Split out to make sure we only capture the variables we want and they are the non-__block versions so they get retained until the block executes
static void _notifyFileEditAndType(ODSFileItem *self, OFFileEdit *fileEdit, NSString *fileType)
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        // -presentedItemDidChange can get called at the end of a rename operation (after -presentedItemDidMoveToURL:). Only send our notification if we "really" changed.
        BOOL didChange = OFNOTEQUAL(self.fileEdit.uniqueEditIdentifier, fileEdit.uniqueEditIdentifier) || OFNOTEQUAL(self.fileType, fileType);
        if (!didChange)
            return;
        
        // Fire KVO on the main thread
        self.fileEdit = fileEdit;
        self.fileType = fileType;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self.scope _fileItemContentsChanged:self];
        }];
    }];
}

// Asynchronously refreshes the date and sends a ODSFileItemContentsChangedNotification notification
- (void)_queueContentsChanged;
{
    // We get sent -presentedItemDidChange even after -accommodatePresentedItemDeletionWithCompletionHandler:.
    // We don't need to not any content changes and if we try to get our modification date, we'll be unable to read the attributes of our file in the dead zone anyway.
    OBFinishPortingLater("<bug:///147937> (iOS-OmniOutliner Bug: Deal with items that are getting deleted. May not be an issue now that we aren't a presenter and don't get -presentedItemDidChange)");
#if 0
    if (_edits.hasAccommodatedDeletion) {
        DEBUG_FILE_ITEM(@"Deleted: ignoring change");
        return;
    }
#endif
    
    DEBUG_FILE_ITEM(@"Queuing contents changed update");

    [self.scope performAsynchronousFileAccessUsingBlock:^{
        
        OBFinishPortingLater("<bug:///147938> (iOS-OmniOutliner Bug: Now that we aren't a file presenter, we might be able to do a coordinated read here. We are running on the scope's action queue also (not the local directory scope's presenter queue))");
        /*
         NOTE: We do NOT use a coordinated read here anymore, though we would like to. If we are getting an incoming sync rename, we could end up deadlocking.
         
         First, there is Radar 10879451: Bad and random ordering of NSFilePresenter notifications. This means we can get a lone -presentedItemDidChange before the relinquish-to-writer wrapped presentedItemDidMoveToURL:. But, we have the old URL at this point. Doing a coordinated read on that URL blocks forever (see Radar 11076208: Coordinated reads started in response to -presentedItemDidChange can hang).
         */
                
        NSURL *fileURL = self.fileURL;
        
        __autoreleasing NSError *error = nil;
        OFFileEdit *fileEdit = [[OFFileEdit alloc] initWithFileURL:fileURL error:&error];
        if (!fileEdit) {
            // Possibly have been deleted
            [error log:@"Error getting file edit for %@", fileURL];
        } else {
            // Some file types may have the same extension but different UTIs based on whether they are a directory or not.
            NSString *fileType = OFUTIForFileExtensionPreferringNative([fileURL pathExtension], [NSNumber numberWithBool:fileEdit.directory]);
            
            OBASSERT(![NSThread isMainThread]);
            _notifyFileEditAndType(self, fileEdit, fileType);
        }
    }];
}

@end


@implementation ODSFileItemMotion

- initWithFileItem:(ODSFileItem *)fileItem destinationFolderURL:(NSURL *)destinationFolderURL;
{
    OBPRECONDITION(fileItem);
    OBPRECONDITION([NSThread isMainThread]); // The purpose of this class is to capture the state of the file item before going into the background and possibly racing with incoming renames
    
    if (!(self = [super init]))
        return nil;
    
    _fileItem = fileItem;
    _sourceFileURL = fileItem.fileURL;
    _originalItemEdit = [ODSFileItemEdit fileItemEditWithFileItem:fileItem];
    
    NSString *filename = [fileItem.fileURL lastPathComponent];
    
    // The original URL might not be downloaded, so we can't get this via attribute lookups.
    BOOL isDirectory = [[fileItem.fileURL absoluteString] hasSuffix:@"/"];
    
    // If the caller is intending to rename the item on copy/move, the destinationFolderURL might be nil (the decision about the name will be decided on the background queue).
    _destinationFileURL = [destinationFolderURL URLByAppendingPathComponent:filename isDirectory:isDirectory];
    
    return self;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"%@ -> %@", self.sourceFileURL, _destinationFileURL];
}

@end

@implementation ODSFileItemDeletion

- initWithFileItem:(ODSFileItem *)fileItem;
{
    OBPRECONDITION([NSThread isMainThread]); // The purpose of this class is to capture the state of the file item before going into the background and possibly racing with incoming renames

    if (!(self = [super init]))
        return nil;
    
    _fileItem = fileItem;
    _sourceFileURL = fileItem.fileURL;
    
    return self;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<DELETE %@>", _sourceFileURL];
}

@end

@implementation ODSFileItemEdit

+ (instancetype)fileItemEditWithFileItem:(ODSFileItem *)fileItem;
{
    return [[self alloc] initWithFileItem:fileItem];
}

- (instancetype)initWithFileItem:(ODSFileItem *)fileItem;
{
    OBPRECONDITION([NSThread isMainThread], "ODSFileItem gets updated on the main thread and we are supposed to be a consistent snapshot");
    OBPRECONDITION(fileItem);
    
    if (!(self = [super init]))
        return nil;
    
    _fileItem = fileItem;
    _originalFileEdit = fileItem.fileEdit; // Might be nil if we haven't been downloaded
    _originalFileURL = fileItem.fileURL; // ... so we have to store the original file URL too.
    
    return self;
}

@end

