// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStoreFileItem.h>

#import <Foundation/NSFileCoordinator.h>
#import <Foundation/NSOperation.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreScope-Subclass.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/OFFilePresenterEdits.h>
#import <OmniFoundation/OFUTI.h>

#import "OFSDocumentStoreFileItem-Internal.h"
#import "OFSDocumentStoreItem-Internal.h"
#import "OFSDocumentStoreScope-Internal.h"


RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_FILE_ITEM_ENABLED 1
    #define DEBUG_FILE_ITEM(format, ...) NSLog(@"FILE ITEM %@: " format, [self shortDescription], ## __VA_ARGS__)
#else
    #define DEBUG_FILE_ITEM(format, ...)
#endif

NSString * const OFSDocumentStoreFileItemFileURLBinding = @"fileURL";
NSString * const OFSDocumentStoreFileItemFileTypeBinding = @"fileType";
NSString * const OFSDocumentStoreFileItemSelectedBinding = @"selected";
NSString * const OFSDocumentStoreFileItemDownloadRequestedBinding = @"downloadRequested";

@interface OFSDocumentStoreFileItem ()
@property(nonatomic) BOOL downloadRequested;
@property(readwrite,nonatomic) NSURL *fileURL;
@property(readwrite,nonatomic) NSString *fileType;
@end

NSString * const OFSDocumentStoreFileItemContentsChangedNotification = @"OFSDocumentStoreFileItemContentsChanged";
NSString * const OFSDocumentStoreFileItemFinishedDownloadingNotification = @"OFSDocumentStoreFileItemFinishedDownloading";
NSString * const OFSDocumentStoreFileItemInfoKey = @"fileItem";

@implementation OFSDocumentStoreFileItem
{
    NSURL *_fileURL;
    
    // ivars for properties in the OFSDocumentStoreItem protocol
    BOOL _hasDownloadQueued;
    BOOL _isDownloaded;
    BOOL _isDownloading;
    BOOL _isUploaded;
    BOOL _isUploading;
    double _percentDownloaded;
    double _percentUploaded;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBASSERT(OBClassImplementingMethod(self, @selector(name)) == [OFSDocumentStoreFileItem class]); // Subclass +displayNameForFileURL:fileType: instead.
    OBASSERT(OBClassImplementingMethod(self, @selector(editingName)) == [OFSDocumentStoreFileItem class]); // Subclass +editingNameForFileURL:fileType: instead.
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

- initWithScope:(OFSDocumentStoreScope *)scope fileURL:(NSURL *)fileURL isDirectory:(BOOL)isDirectory fileModificationDate:(NSDate *)fileModificationDate userModificationDate:(NSDate *)userModificationDate;
{
    OBPRECONDITION(scope);
    OBPRECONDITION(fileURL);
    OBPRECONDITION([fileURL isFileURL]);
    // OBPRECONDITION(fileModificationDate); // This can be nil for files that haven't been downloaded (since we don't publish stub files any more).
    OBPRECONDITION(userModificationDate);
    OBPRECONDITION(scope.documentStore);
    OBPRECONDITION([scope isFileInContainer:fileURL]);
    OBPRECONDITION(isDirectory == [[fileURL absoluteString] hasSuffix:@"/"]); // We can't compute isDirectory here based on the filesystem state since the file URL might not currently exist (if it represents a non-downloaded file in a cloud scope).
    
    if (!fileURL) {
        OBASSERT_NOT_REACHED("Bad caller");
        return nil;
    }
    
    // NOTE: OFSDocumentStoreFileItem CANNOT keep a pointer to an OFXFileItem (since when generating conflict versions the URL of the file item doesn't change). See -[OFXFileItem _generateConflictDocumentAndRevertToTemporaryDocumentContentsAtURL:coordinator:error:].

    if (!(self = [super initWithScope:scope]))
        return nil;
    
    _fileURL = [fileURL copy];
    _fileModificationDate = [fileModificationDate copy];
    _userModificationDate = [userModificationDate copy];

    // We might represent a file that isn't downloaded and not locally present, so we can't look up the directory-ness of the file ourselves.
    _fileType = [OFUTIForFileExtensionPreferringNative([_fileURL pathExtension], @(isDirectory)) copy];
    OBASSERT(_fileType);
        
    // Reasonable values for local documents that will never get updated by a sync container agent.
    _hasDownloadQueued = kOFSDocumentStoreFileItemDefault_HasDownloadQueued;
    _isDownloaded = kOFSDocumentStoreFileItemDefault_IsDownloaded;
    _isDownloading = kOFSDocumentStoreFileItemDefault_IsDownloading;
    _isUploaded = kOFSDocumentStoreFileItemDefault_IsUploaded;
    _isUploading = kOFSDocumentStoreFileItemDefault_IsUploading;
    _percentDownloaded = kOFSDocumentStoreFileItemDefault_PercentDownloaded;
    _percentUploaded = kOFSDocumentStoreFileItemDefault_PercentUploaded;

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
            [self willChangeValueForKey:OFSDocumentStoreFileItemFileURLBinding];
            _fileURL = fileURL;
            [self didChangeValueForKey:OFSDocumentStoreFileItemFileURLBinding];
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
    
    @synchronized(self) {
        if (OFNOTEQUAL(_fileType, fileType)) {
            [self willChangeValueForKey:OFSDocumentStoreFileItemFileTypeBinding];
            _fileType = fileType;
            [self didChangeValueForKey:OFSDocumentStoreFileItemFileTypeBinding];
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
    return [NSSet setWithObjects:OFSDocumentStoreFileItemFileURLBinding, nil];
}

- (NSComparisonResult)compare:(OFSDocumentStoreFileItem *)otherItem;
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

#pragma mark - OFSDocumentStoreItem protocol

- (NSString *)name;
{
    return [[self class] displayNameForFileURL:self.fileURL fileType:self.fileType];
}

- (void)setFileModificationDate:(NSDate *)fileModificationDate;
{
    OBPRECONDITION([NSThread isMainThread]); // Ensure we are only firing KVO on the main thread
    //OBPRECONDITION(fileModificationDate); // can be nil if this represents a non-downloaded cloud item.
    
    if (OFISEQUAL(_fileModificationDate, fileModificationDate))
        return;
    
    _fileModificationDate = [fileModificationDate copy];
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
@synthesize percentDownloaded = _percentDownloaded;
@synthesize percentUploaded = _percentUploaded;

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

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p '%@' date:%@>", NSStringFromClass([self class]), self, self.fileURL, [self.userModificationDate xmlString]];
}

#pragma mark - Internal

// Called by our scope when it notices we've been moved.
- (void)didMoveToURL:(NSURL *)fileURL;
{
    self.fileURL = fileURL;
}

#pragma mark - Private

// Split out to make sure we only capture the variables we want and they are the non-__block versions so they get retained until the block executes
static void _notifyDateAndFileType(OFSDocumentStoreFileItem *self, NSDate *fileModificationDate, NSString *fileType)
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        // -presentedItemDidChange can get called at the end of a rename operation (after -presentedItemDidMoveToURL:). Only send our notification if we "really" changed.
        BOOL didChange = OFNOTEQUAL(self.fileModificationDate, fileModificationDate) || OFNOTEQUAL(self.fileType, fileType);
        if (!didChange)
            return;
        
        // Fire KVO on the main thread
        self.fileModificationDate = fileModificationDate;
        self.fileType = fileType;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self.scope _fileItemContentsChanged:self];
        }];
    }];
}

// Asynchronously refreshes the date and sends a OFSDocumentStoreFileItemContentsChangedNotification notification
- (void)_queueContentsChanged;
{
    // We get sent -presentedItemDidChange even after -accommodatePresentedItemDeletionWithCompletionHandler:.
    // We don't need to not any content changes and if we try to get our modification date, we'll be unable to read the attributes of our file in the dead zone anyway.
    OBFinishPortingLater("Deal with items that are getting deleted. May not be an issue now that we aren't a presenter and don't get -presentedItemDidChange");
#if 0
    if (_edits.hasAccommodatedDeletion) {
        DEBUG_FILE_ITEM(@"Deleted: ignoring change");
        return;
    }
#endif
    
    DEBUG_FILE_ITEM(@"Queuing contents changed update");

    [self.scope performAsynchronousFileAccessUsingBlock:^{
        
        OBFinishPortingLater("Now that we aren't a file presenter, we might be able to do a coordinated read here. We are running on the scope's action queue also (not the local directory scope's presenter queue)");
        /*
         NOTE: We do NOT use a coordinated read here anymore, though we would like to. If we are getting an incoming sync rename, we could end up deadlocking.
         
         First, there is Radar 10879451: Bad and random ordering of NSFilePresenter notifications. This means we can get a lone -presentedItemDidChange before the relinquish-to-writer wrapped presentedItemDidMoveToURL:. But, we have the old URL at this point. Doing a coordinated read on that URL blocks forever (see Radar 11076208: Coordinated reads started in response to -presentedItemDidChange can hang).
         */
                
        NSDate *modificationDate = nil;
        NSString *fileType = nil;
        
        NSError *error = nil;
        
        NSURL *fileURL = self.fileURL;
        
        // We use the file modification date rather than a date embedded inside the file since the latter would cause duplicated documents to not sort to the front as a new document (until you modified them, at which point they'd go flying to the beginning).
        __autoreleasing NSError *attributesError = nil;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[fileURL absoluteURL] path]  error:&attributesError];
        if (!attributes)
            NSLog(@"Error getting attributes for %@ -- %@", [fileURL absoluteString], [attributesError toPropertyList]);
        else
            modificationDate = [attributes fileModificationDate];
        if (!modificationDate)
            modificationDate = [NSDate date]; // Default to now if we can't get the attributes or they are bogus for some reason.
        
        // Some file types may have the same extension but different UTIs based on whether they are a directory or not.
        BOOL isDirectory = [[attributes objectForKey:NSFileType] isEqual:NSFileTypeDirectory];
        
        fileType = OFUTIForFileExtensionPreferringNative([fileURL pathExtension], [NSNumber numberWithBool:isDirectory]);
        
        if (!modificationDate) {
            NSLog(@"Error performing coordinated read of modification date of %@: %@", [fileURL absoluteString], [error toPropertyList]);
            modificationDate = [NSDate date]; // Default to now if we can't get the attributes or they are bogus for some reason.
        }
        
        OBASSERT(![NSThread isMainThread]);
        
        _notifyDateAndFileType(self, modificationDate, fileType);
    }];
}

@end
