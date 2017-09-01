// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSScope-Subclass.h>

#import <OmniDocumentStore/ODSErrors.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniDocumentStore/ODSUtilities.h>

#import "ODSStore-Internal.h"
#import "ODSFileItem-Internal.h"
#import "ODSItem-Internal.h"
#import "ODSScope-Internal.h"

@import MobileCoreServices;
@import OmniFoundation;

RCS_ID("$Id$");

OBDEPRECATED_METHOD(-urlForNewDocumentInFolderNamed:baseName:fileType:); // folderURL
OBDEPRECATED_METHOD(-addDocumentInFolderNamed:baseName:fromURL:option:completionHandler:); // folderURL
OBDEPRECATED_METHOD(-copyCurrentlyUsedFileNamesInFolderNamed:ignoringFileURL:); // folderURL

OBDEPRECATED_METHOD(-fileWithURL:andDate:willCopyToURL:);
OBDEPRECATED_METHOD(-fileWithURL:andDate:finishedCopyToURL:andDate:successfully:);

@interface ODSScope (/*Private*/)
@property(nonatomic,copy) NSSet *fileItems; // redeclared so we can use -mutableSetValueForKey:
@end

@implementation ODSScope
{
    NSOperationQueue *_actionOperationQueue;

    ODSFolderItem *_rootFolder; // nil relative path, holds the top level items
}

// The returned key is only valid within the owning scope.
NSString *ODSScopeCacheKeyForURL(NSURL *url)
{
    OBPRECONDITION(url);
        
    // NSFileManager will return /private/var URLs even when passed a standardized (/var) URL. Our cache keys should always be in one space.
    // -URLByStandardizingPath only works if the URL exists, but it may or may not exist if the file isn't downloaded yet, so we could only normalize the parent URL (which should be a longer-lived container) and then append the last path component (so that /var/mobile vs /var/private/mobile differences won't hurt).
    // But, even easier is to drop everything before "/Documents/", leaving the container-relative suffix.
    NSString *urlString = [url absoluteString];
    
    NSUInteger urlStringLength = [urlString length];
    OBASSERT(urlStringLength > 0);
    NSRange cacheKeyRange = NSMakeRange(0, urlStringLength);
    
    NSRange documentsRange = [urlString rangeOfString:@"/Documents/"];
    OBASSERT(documentsRange.length > 0);
    
    if (documentsRange.length > 0) {
        cacheKeyRange = NSMakeRange(NSMaxRange(documentsRange), urlStringLength - NSMaxRange(documentsRange));
        OBASSERT(NSMaxRange(cacheKeyRange) == urlStringLength);
    }
    
    // Normalize directory URLs just in case some callers append the slash and others don't.
    if (cacheKeyRange.length > 0) { // The URL might end in .../Documents/
        if ([urlString characterAtIndex:urlStringLength - 1] == '/')
            cacheKeyRange.length--;
    }
    
    NSString *cacheKey = [urlString substringWithRange:cacheKeyRange];
    
    OBASSERT([cacheKey hasSuffix:@"/"] == NO);
    OBASSERT([cacheKey containsString:@"/private/var"] == NO);
    
    return cacheKey;
}

// This is split out from the instance method so that we can build a cache of container URLs. Getting the container URL is slow in some scopes.
+ (BOOL)isFile:(NSURL *)fileURL inContainer:(NSURL *)containerURL;
{
    return OFURLContainsURL(containerURL, fileURL);
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithDocumentStore:(ODSStore *)documentStore;
{
    OBPRECONDITION([self conformsToProtocol:@protocol(ODSConcreteScope)]); // Make sure subclasses declare conformance
    OBPRECONDITION(documentStore);
    
    if (!(self = [super init]))
        return nil;
    
    _weak_documentStore = documentStore;

    _actionOperationQueue = [[NSOperationQueue alloc] init];
    _actionOperationQueue.name = [NSString stringWithFormat:@"com.omnigroup.frameworks.OmniDocumentStore.actions for <%@:%p>", NSStringFromClass([self class]), self];
    _actionOperationQueue.maxConcurrentOperationCount = 1;

    _rootFolder = [[ODSFolderItem alloc] initWithScope:self];
    _rootFolder.relativePath = @"";
    
    return [super init];
}

- (void)dealloc;
{
    for (ODSFileItem *fileItem in _fileItems)
        [fileItem _invalidate];
    [_rootFolder eachFolder:^(ODSFolderItem *folder, BOOL *stop){
        [folder _invalidate];
    }];

    OBASSERT([_actionOperationQueue operationCount] == 0);
}

@synthesize documentStore = _weak_documentStore;

- (BOOL)isFileInContainer:(NSURL *)fileURL;
{
    return [[self class] isFile:fileURL inContainer:self.documentsURL];
}

+ (BOOL)automaticallyNotifiesObserversOfFileItems;
{
    return NO;
}

- (void)setFileItems:(NSSet *)fileItems itemMoved:(BOOL)itemMoved;
{
    OBPRECONDITION([NSThread isMainThread]); // Our KVO should fire only on the main thread
#ifdef OMNI_ASSERTIONS_ON
    for (ODSFileItem *fileItem in fileItems) {
        OBASSERT(fileItem.scope == self); // file items cannot move between scopes
        OBASSERT([self isFileInContainer:fileItem.fileURL]); // should have a URL we claim
    }
#endif
    fileItems = [fileItems filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ODSFileItem *  _Nonnull evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        return evaluatedObject.scope == self && [self isFileInContainer:evaluatedObject.fileURL];
    }]];
    
    BOOL changed = NO;
    if (![_fileItems isEqual:fileItems]) {
        [self willChangeValueForKey:OFValidateKeyPath(self, fileItems)];
        _fileItems = [[NSSet alloc] initWithSet:fileItems];
        [self didChangeValueForKey:OFValidateKeyPath(self, fileItems)];
        changed = YES;
    }
    
    if (changed || itemMoved)
        [self _updateItemTree];
}

static NSString *_makeCanonicalPath(NSString *path)
{
    // We don't want to resolve symlinks in the last path component, or we can't tell symlinks apart from the things they point at
    NSString *canonicalParentPath = [[[path stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath] stringByStandardizingPath];
    return [canonicalParentPath stringByAppendingPathComponent:[path lastPathComponent]];
}

+ (NSSet *)keyPathsForValuesAffectingTopLevelItems;
{
    ODSFolderItem *folder;
    return [NSSet setWithObject:OFKeyPathForKeys(@"rootFolder", OFValidateKeyPath(folder, childItems), nil)];
}
- (NSSet *)topLevelItems;
{
    return _rootFolder.childItems;
}

- (ODSFileItem *)fileItemWithURL:(NSURL *)url;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after our first scan is done
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with changes to the fileItems property
    
    if (url == nil || ![url isFileURL])
        return nil;
    
    NSString *standardizedPathForURL = _makeCanonicalPath([url path]);
    OBASSERT(standardizedPathForURL != nil);
    for (ODSFileItem *fileItem in _fileItems) {
        NSString *fileItemPath = _makeCanonicalPath([fileItem.fileURL path]);
        OBASSERT(fileItemPath != nil);
        
        DEBUG_STORE(@"- Checking file item: '%@'", fileItemPath);
        if ([fileItemPath compare:standardizedPathForURL] == NSOrderedSame)
            return fileItem;
    }
    DEBUG_STORE(@"Couldn't find file item for path: '%@'", standardizedPathForURL);
    DEBUG_STORE(@"Unicode: '%s'", [standardizedPathForURL cStringUsingEncoding:NSNonLossyASCIIStringEncoding]);
    return nil;
}

- (ODSFolderItem *)folderItemContainingItem:(ODSItem *)item;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    ODSFolderItem *folder = [_rootFolder parentFolderOfItem:item];
    
    // Backwards compatibility
    if (folder == _rootFolder)
        folder = nil;
    
    return folder;
}

- (ODSFileItem *)makeFileItemForURL:(NSURL *)fileURL isDirectory:(BOOL)isDirectory fileEdit:(OFFileEdit *)fileEdit userModificationDate:(NSDate *)userModificationDate;
{
    ODSStore *documentStore = self.documentStore;
    if (!documentStore) {
        OBASSERT_NOT_REACHED("Asked for a file item while our document store was not set (weak pointer cleared somehow while we are still part of the store?");
        return nil;
    }
    
    // This assumes that the choice of file item class is consistent for each URL (since we will reuse file item).  Could double-check in this loop that the existing file item has the right class if we ever want this to be dynamic.
    Class fileItemClass = [documentStore fileItemClassForURL:fileURL];
    if (!fileItemClass) {
        // We have a UTI for this, but the delegate doesn't want it to show up in the listing (OmniGraffle templates, for example).
        return nil;
    }
    OBASSERT(OBClassIsSubclassOfClass(fileItemClass, [ODSFileItem class]));
    
#ifdef OMNI_ASSERTIONS_ON
    for (id <NSFilePresenter> presenter in [NSFileCoordinator filePresenters]) {
        if (![presenter isKindOfClass:[ODSFileItem class]])
            continue;
        ODSFileItem *otherFileItem  = (ODSFileItem *)presenter;
        if (otherFileItem.scope != self)
            continue; // cache keys aren't comparable across scopes
        
        OBFinishPortingLater("<bug:///147935> (iOS-OmniOutliner Engineering: move this to subclasses ... OFX scope doesn't care about cache key goop. Can also relax the restriction that document directories end in Documents for OFX)");
        OBASSERT(OFNOTEQUAL(ODSScopeCacheKeyForURL(otherFileItem.fileURL), ODSScopeCacheKeyForURL(fileURL)));
    }
#endif
    
    ODSFileItem *fileItem = [[fileItemClass alloc] initWithScope:self fileURL:fileURL isDirectory:isDirectory fileEdit:fileEdit userModificationDate:userModificationDate];
    
    // Shouldn't make file items for files we can't view.
    OBASSERT([documentStore canViewFileTypeWithIdentifier:fileItem.fileType]);
    
    DEBUG_STORE(@"  made new file item %@ for %@", fileItem, fileURL);
    
    return fileItem;
}

// Allow external objects to synchronize with our operations.
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;
{
    OBPRECONDITION(_actionOperationQueue);
    
    [_actionOperationQueue addOperationWithBlock:block];
}

// Calls the specified block on the current queue after all the currently enqueued asynchronous accesses finish. Useful when some action needs to happen after a sequence of other file accesses operations.
- (void)afterAsynchronousFileAccessFinishes:(void (^)(void))block;
{
    block = [block copy];
    
    NSOperationQueue *queue = [NSOperationQueue currentQueue];
    OBASSERT(queue);
    OBASSERT(queue != _actionOperationQueue);
    
    [self performAsynchronousFileAccessUsingBlock:^{
        [queue addOperationWithBlock:block];
    }];
}

// Helper that can be used for methods that create a file item and don't need/want to do a full scan.
static ODSFileItem *_addItem(ODSScope *self, OFFileMotionResult *motionResult)
{
    // As we modify our _fileItem set here and fire KVO, this should be on the main thread.
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(motionResult);
    
    ODSFileItem *fileItem = [self fileItemWithURL:motionResult.fileURL];
    
    if (!fileItem || fileItem.isDownloaded) {
        // Either a newly appearing file, a regular local file, or a OmniPresence file that is already downloaded, so it exists on disk.
        OBASSERT(motionResult.fileEdit != nil);
    } else if (fileItem) {
        // OmniPresence item that isn't downloaded. Only thing we can be doing here is renaming it. It won't have a file edit here (since it isn't on disk)
        OBASSERT(fileItem.fileEdit == nil);
        OBASSERT(motionResult.fileEdit == nil);
    }
    
    // If we are replacing an existing document, there may already be a file item (but it is probably marked for deletion). But we also want to be careful that if there was a scan completed and repopulated _fileItems that *did* capture this URL, we don't want make a new file item for the same URL.
    ODSFileItem *addedFileItem = nil;
    OFFileEdit *fileEdit = motionResult.fileEdit;
    
    if (fileItem) {
        // Might or might not be downloaded if we are moving an existing file item.
        if (fileEdit)
            fileItem.fileEdit = fileEdit;
        else
            OBASSERT(fileItem.fileEdit == nil);
    } else {
        // This function is called for newly created items, so our content modification date is the same as the file system modification time (or close enough).
        OBASSERT(fileEdit);
        
        NSDate *userModificationDate = fileEdit.fileModificationDate;
        
        addedFileItem = [self makeFileItemForURL:fileEdit.originalFileURL isDirectory:fileEdit.directory fileEdit:fileEdit userModificationDate:userModificationDate];
        if (!addedFileItem) {
            OBASSERT_NOT_REACHED("Some error in the delegate where we created a file of a type we don't display?");
        } else {
            fileItem = addedFileItem;
            
            // Start out with the right state when duplicating an item and otherwise set default metadata.
            [self updateFileItem:fileItem withMetadata:nil fileEdit:fileEdit];
        }
    }
    
    if (addedFileItem) {
        OBASSERT([self.fileItems member:addedFileItem] == nil);
        [self setFileItems:[self->_fileItems setByAddingObject:addedFileItem] itemMoved:NO];
    }
    
    return fileItem;
}

static void _addItemAndNotifyHandler(ODSScope *self, OFFileMotionResult *motionResult, NSError *error, void (^handler)(ODSFileItem *createdFileItem, NSError *error))
{
    // As we modify our _fileItem set here and fire KVO, this should be on the main thread.
    OBPRECONDITION([NSThread isMainThread]);
    
    // We just successfully wrote a new document; there is no need to do a full scan (though one may fire anyway if a metadata update starts due to a scope noticing the edit). Still, we want to get back to the UI as soon as possible by calling the completion handler w/o waiting for the scan.
    ODSFileItem *fileItem = nil;
    if (motionResult)
        fileItem = _addItem(self, motionResult);
    else
        OBASSERT(error);
    
    if (handler)
        handler(fileItem, error);
}

- (NSURL *)urlForNewDocumentInFolder:(ODSFolderItem *)folder baseName:(NSString *)baseName fileType:(NSString *)documentUTI;
{
    return [self urlForNewDocumentInFolderAtURL:[self _urlForFolder:folder] baseName:baseName fileType:documentUTI];
}

- (NSURL *)urlForNewDocumentInFolderAtURL:(NSURL *)folderURL baseName:(NSString *)baseName fileType:(NSString *)documentUTI;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _actionOperationQueue, "bug:///137297");
    
    OBPRECONDITION(documentUTI);
    
    BOOL isPackage;
    NSString *extension = ODSPathExtensionForFileType(documentUTI, &isPackage);
    
    NSUInteger counter = 0;
    
    NSURL *documentsURL = self.documentsURL;
    if (folderURL) {
        OBASSERT(OFURLContainsURL(documentsURL, folderURL));
    } else
        folderURL = documentsURL;
    
    NSString *availableFileName = [self _availableFileNameInFolderAtURL:folderURL withBaseName:baseName extension:extension counter:&counter];
    
    return [folderURL URLByAppendingPathComponent:availableFileName isDirectory:isPackage];
}

- (void)performDocumentCreationAction:(ODSScopeDocumentCreationAction)createDocument handler:(ODSScopeDocumentCreationHandler)handler;
{
    OBPRECONDITION(createDocument);
    
    createDocument = [createDocument copy];
    handler = [handler copy];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        createDocument(^(OFFileEdit *resultFileEdit, NSError *errorOrNil){
            OFFileMotionResult *motionResult = [[OFFileMotionResult alloc] initWithFileEdit:resultFileEdit];
            _addItemAndNotifyHandler(self, motionResult, errorOrNil, handler);
        });
    }];
}

typedef NS_OPTIONS(NSUInteger, AddOptions) {
    AddByReplacing = (1<<0),
    AddByCreatingParentDirectories = (1<<1),
    AddByMoving = (1<<2),
};

static OFFileEdit *_performAdd(ODSScope *scope, NSURL *fromURL, NSURL *toURL, AddOptions options, NSError **outError)
{
    OBPRECONDITION(![NSThread isMainThread]); // Were going to do file coordination which could deadlock with file presenters on the main thread
    OBASSERT_NOTNULL(outError); // We know we pass in a non-null pointer, so we can avoid the outError-NULL checks.
    
    // We might be able to do a coordinated read/write to duplicate documents. Since we need to sometimes move, let's just always do that. Since the source might have incoming sync writes or have presenters with outstanding writes, do a coordinated read while copying it into a temporary location. It is a bit annoying that we have two separate operations, but we should still get a consistent snapshot of the source at our destination location.
    NSURL *moveSourceURL;
    BOOL moveSourceIsTemporaryCopy = NO;
    if (options & AddByMoving) {
        // We can move this URL directly.
        moveSourceURL = fromURL;
    } else {
        NSFileManager *manager = [NSFileManager defaultManager];

        NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[fromURL lastPathComponent]];
        temporaryPath = [manager uniqueFilenameFromName:temporaryPath allowOriginal:YES create:NO error:outError];
        if (!temporaryPath)
            return nil;
        
        moveSourceURL = [NSURL fileURLWithPath:temporaryPath];
        DEBUG_STORE(@"Making copy of %@ at %@", fromURL, moveSourceURL);
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block BOOL success = NO;
        __block NSError *innerError = nil;
        
        __autoreleasing NSError *error = nil;
        [coordinator coordinateReadingItemAtURL:fromURL options:0
                               writingItemAtURL:moveSourceURL options:NSFileCoordinatorWritingForReplacing
                                          error:&error byAccessor:
         ^(NSURL *newReadingURL, NSURL *newWritingURL) {
             __autoreleasing NSError *copyError = nil;
             if (![manager copyItemAtURL:newReadingURL toURL:newWritingURL error:&copyError]) {
                 [copyError log:@"Error copying %@ to %@", newReadingURL, newWritingURL];
                 innerError = copyError;
                 return;
             }
             
             success = YES;
         }];
        
        
        if (!success) {
            OBASSERT(error || innerError);
            if (innerError)
                error = innerError;
            *outError = error;
            return nil;
        }
        moveSourceIsTemporaryCopy = YES;
    }
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block OFFileEdit *fileEdit = nil;
    __block NSError *innerError = nil;
    __autoreleasing NSError *error = nil;

    // If we are moving the original input, we require that it is not in any scope and doesn't need file coordination. So, we don't specify the source here as either being read/written since we should have the only reference to it.
    [coordinator coordinateWritingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing
                                      error:&error byAccessor:
     ^(NSURL *newWritingURL) {
         NSFileManager *manager = [NSFileManager defaultManager];
         
         BOOL replaced = NO;
         
         if (options & AddByReplacing) {
             __autoreleasing NSError *replaceError = nil;
             
             replaced = [manager replaceItemAtURL:newWritingURL withItemAtURL:moveSourceURL backupItemName:nil options:0 resultingItemURL:NULL error:&replaceError];
             if (!replaced) {
                 if (![replaceError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) {
                     innerError = replaceError;
                     [replaceError log:@"Error replacing %@ with %@", newWritingURL, moveSourceURL];
                     return;
                 }
             }
         }
         
         if (!replaced) {
             __autoreleasing NSError *moveError = nil;
             if (![coordinator moveItemAtURL:moveSourceURL toURL:newWritingURL createIntermediateDirectories:(options & AddByCreatingParentDirectories) error:&moveError]) {
                 NSLog(@"Error moving %@ -> %@: %@", moveSourceURL, newWritingURL, [moveError toPropertyList]);
                 innerError = moveError;
                 return;
             }
         }

         // We are making a new file here, so make sure the modification date is updated (for our initial user edit date). If needed, we could pass a flag in to disable this (or switch this off by default, but have a flag to enable it). The important bit is that we do this on the background file queue before we look up the fileEdit.
         __autoreleasing NSError *touchError;
         if (![[NSFileManager defaultManager] touchItemAtURL:newWritingURL error:NULL]) {
             [touchError log:@"Cannot update modification date of %@", newWritingURL];
             // not fatal...
         }

         __autoreleasing NSError *fileError = nil;
         fileEdit = [[OFFileEdit alloc] initWithFileURL:newWritingURL error:&fileError];
         if (!fileEdit) {
             [fileError log:@"Cannot get file edit for %@", newWritingURL];
             innerError = fileError;
         }
     }];
    
    
    if (!fileEdit) {
        OBASSERT(error || innerError);
        if (innerError)
            error = innerError;
        *outError = error;
        
        // Clean up the temporary copy
        if (moveSourceIsTemporaryCopy)
            [[NSFileManager defaultManager] removeItemAtURL:moveSourceURL error:NULL];
        
        return nil;
    }
    
    return fileEdit;
}

- (void)addDocumentInFolder:(ODSFolderItem *)folderItem fromURL:(NSURL *)fromURL option:(ODSStoreAddOption)option completionHandler:(void (^)(ODSFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    [self addDocumentInFolder:folderItem baseName:nil fromURL:fromURL option:option completionHandler:completionHandler];
}

- (void)addDocumentInFolder:(ODSFolderItem *)folderItem baseName:(NSString *)baseName fromURL:(NSURL *)fromURL option:(ODSStoreAddOption)option completionHandler:(void (^)(ODSFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    // Infer the result file type from the incoming fromURL's type.
    NSString *fileType = OFUTIForFileURLPreferringNative(fromURL, NULL);
    [self addDocumentInFolder:folderItem baseName:baseName fileType:fileType fromURL:fromURL option:option completionHandler:completionHandler];
}

// Enqueues an operation on the scope's background serial action queue. The completion handler will be called with the resulting file item, nil file item and an error.
- (void)addDocumentInFolder:(ODSFolderItem *)folderItem baseName:(NSString *)baseName fileType:(NSString *)fileType fromURL:(NSURL *)fromURL option:(ODSStoreAddOption)option completionHandler:(void (^)(ODSFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // We'll invoke the completion handler on the main thread
    OBPRECONDITION(!folderItem || folderItem.scope == self);
    OBPRECONDITION(fileType);
    OBPRECONDITION(fromURL);
    
    if (!folderItem)
        folderItem = _rootFolder;
    
    NSURL *folderURL = [self _urlForFolder:folderItem]; // ODSItems are main-thread only, so switch to folderURL.
    
    if (!baseName)
        baseName = [[fromURL lastPathComponent] stringByDeletingPathExtension];
    
    // Don't copy in random files that the user tapped on in the WebDAV browser or that higher level UI didn't filter out.
    BOOL canView;
    NSString *extension;
    BOOL isDirectory;
    {
        // We don't know where the file will end up, but this should be good enough to check if we've be able to view it.
        BOOL fileTypeIsPackage;
        extension = ODSPathExtensionForFileType(fileType, &fileTypeIsPackage);
        
        // fromURL should exist, so we can ask if it is a directory.
        __autoreleasing NSError *attributError;
        if (!OFGetBoolResourceValue(fromURL, NSURLIsDirectoryKey, &isDirectory, &attributError)) {
            // OFGetBoolResourceValue already logs
            isDirectory = [[fromURL absoluteString] hasSuffix:@"/"];
        }
        // Can't clone a directory to become a flat file -- the source URL and destination file type need to at least agree on package-ness.
        // This currently spuriously fails for OmniGraffle since the .graffle file extension can be either a package or not. The input template is a flat-file .gtemplate, but we get passed in the com.omnigroup.omnigraffle.graffle-package (the caller just assumed when it should map flat-stencil to flat-graffle).
        // OBASSERT(fileTypeIsPackage == isDirectory);
        
        NSURL *fakeDestinationURL = [folderURL URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:extension]];

        canView = ([self.documentStore fileItemClassForURL:fakeDestinationURL] != Nil);
        canView &= (fileType != nil) && [self.documentStore canViewFileTypeWithIdentifier:fileType];
    }
    
    if (!canView) {
        NSLog(@"Unable to add document: unsupported file type [%@] for document [%@]", fileType, fromURL);
        if (completionHandler) {
            __autoreleasing NSError *error = nil;
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to add document.", @"OmniDocumentStore", OMNI_BUNDLE, @"Error description when a file type is not recognized.");
            NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
            OBASSERT(![NSString isEmptyString:appName]);
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ does not recognize this kind of file.", @"OmniDocumentStore", OMNI_BUNDLE, @"Error reason when a file type is not recognized."), appName];
            
            ODSError(&error, ODSUnrecognizedFileType, description, reason);
            completionHandler(nil, error);
        }
        return;
    }
    
    if (!completionHandler)
        completionHandler = ^(ODSFileItem *duplicateFileItem, NSError *error){
            if (!duplicateFileItem)
                NSLog(@"Error adding document of type %@ from %@: %@", fileType, fromURL, [error toPropertyList]);
        };
    
    
    completionHandler = [completionHandler copy]; // preserve scope
    
    // Convenience for dispatching the completion handler to the main queue.
    void (^callCompletionHandlerOnMainQueue)(ODSFileItem *duplicateFileItem, NSError *error) = ^(ODSFileItem *duplicateFileItem, NSError *error){
        OBPRECONDITION(![NSThread isMainThread]);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(duplicateFileItem, error);
        }];
    };
    callCompletionHandlerOnMainQueue = [callCompletionHandlerOnMainQueue copy];
    
    // We cannot decide on the destination URL w/o synchronizing with the action queue. In particular, if you try to duplicate "A" and "A 2", both operations could pick "A 3".
    [self performAsynchronousFileAccessUsingBlock:^{
        NSURL *toURL = nil;
        NSString *toFileName = [baseName stringByAppendingPathExtension:extension];
        AddOptions addOptions = 0;
        
        if (option == ODSStoreAddByCopyingSourceToDestinationURL) {
            // Use the given file name.
            __autoreleasing NSError *urlError = nil;
            toURL = [self _urlForFolderAtURL:folderURL fileName:toFileName isDirectory:isDirectory error:&urlError];
            if (!toURL) {
                callCompletionHandlerOnMainQueue(nil, urlError);
                return;
            }
        }
        else if (option == ODSStoreAddByCopyingSourceToAvailableDestinationURL || option == ODSStoreAddByMovingTemporarySourceToAvailableDestinationURL) {
            if (option == ODSStoreAddByMovingTemporarySourceToAvailableDestinationURL)
                addOptions |= AddByMoving;
            
            // Generate a new file name.
            __autoreleasing NSString *toBaseName = nil;
            NSUInteger counter;
            [[toFileName stringByDeletingPathExtension] splitName:&toBaseName andCounter:&counter];
            
            toFileName = [self _availableFileNameInFolderAtURL:folderURL withBaseName:toBaseName extension:[toFileName pathExtension] counter:&counter];
            
            __autoreleasing NSError *urlError = nil;
            toURL = [self _urlForFolderAtURL:folderURL fileName:toFileName isDirectory:isDirectory error:&urlError];
            if (!toURL) {
                callCompletionHandlerOnMainQueue(nil, urlError);
                return;
            }
        }
        else if (option == ODSStoreAddByCopyingSourceToReplaceDestinationURL) {
            // Use the given file name, but ensure that it does not exist in the documents directory.
            __autoreleasing NSError *urlError = nil;
            toURL = [self _urlForFolderAtURL:folderURL fileName:toFileName isDirectory:isDirectory error:&urlError];
            if (!toURL) {
                callCompletionHandlerOnMainQueue(nil, urlError);
                return;
            }
            
            addOptions |= AddByReplacing;
        }
        else {
            // TODO: Perhaps we should create an error and assign it to outError?
            OBASSERT_NOT_REACHED("ODSStoreAddOption not given or invalid.");
            callCompletionHandlerOnMainQueue(nil, nil);
            return;
        }
        
        __autoreleasing NSError *addError = nil;
        OFFileEdit *fileEdit = _performAdd(self, fromURL, toURL, addOptions, &addError);
        
        NSError *strongError = fileEdit ? nil : addError;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (fileEdit) {
                OFFileMotionResult *motionResult = [[OFFileMotionResult alloc] initWithFileEdit:fileEdit];
                _addItemAndNotifyHandler(self, motionResult, nil, completionHandler);
            } else
                _addItemAndNotifyHandler(self, nil, strongError, completionHandler);
        }];
    }];
}

- (NSMutableSet *)_copyCurrentlyUsedFolderNamesInFolder:(ODSFolderItem *)parentFolder;
{
    // We might be racing with incoming sync'd changes. We don't scan inside the async block like we do for files since this can't be a document and if we lose the race we'll just bail.
    OBPRECONDITION([NSThread isMainThread]);
    NSMutableSet *usedFolderNames = [NSMutableSet set];
    NSSet *childItems = parentFolder ? parentFolder.childItems : self.topLevelItems;
    
    for (ODSItem *item in childItems) {
        if (![item isKindOfClass:[ODSFolderItem class]])
            continue;
        ODSFolderItem *childFolder = (ODSFolderItem *)item;
        [usedFolderNames addObject:childFolder.name];
    }
    return usedFolderNames;
}

- (void)_doMotion:(NSString *)motionType withItems:(NSSet *)items toFolder:(ODSFolderItem *)parentFolder ignoringFileItems:(NSSet *)ignoredFileItems status:(ODSScopeItemMotionStatus)status completionHandler:(void (^)(NSSet *finalItems))completionHandler
           action:(OFFileMotionResult *(^)(ODSFileItemMotion *itemMotion, NSURL *destinationURL, NSError **outError))action;
{
    OBPRECONDITION(!parentFolder || parentFolder.scope == self);
    
    DEBUG_STORE(@"%@ items %@ to folder %@", motionType, [items valueForKey:@"shortDescription"], [parentFolder shortDescription]);
    
    status = [status copy];
    completionHandler = [completionHandler copy];
    action = [action copy];
    
    if (!parentFolder)
        parentFolder = _rootFolder;
    
    NSURL *parentFolderURL = [self _urlForFolder:parentFolder];
    NSMutableSet *usedFolderNames = [self _copyCurrentlyUsedFolderNamesInFolder:parentFolder];
    NSMutableArray *motions = [NSMutableArray new];
    
    // Make our plans about what *file* motions to do (folders are implicit).
    for (ODSItem *item in items) {
        [item _addMotions:motions toParentFolderURL:parentFolderURL isTopLevel:YES usedFolderNames:usedFolderNames ignoringFileItems:ignoredFileItems];
    }
    
    if ([motions count] == 0) {
        // Everything handled by ignored items?
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (completionHandler) {
                NSSet *addedChildren = [NSSet set];
                DEBUG_STORE(@"%@ yielded added children %@", motionType, [addedChildren valueForKey:@"shortDescription"]);
                completionHandler(addedChildren);
            }
        }];
        return;
    }
    
    DEBUG_STORE(@"Planned motions:\n%@", [motions valueForKey:@"shortDescription"]);
    
    [self performAsynchronousFileAccessUsingBlock:^{
        // We put this hear to capture scope, but we only add/read it on the main queue.
        NSMutableSet *createdFileItems = [NSMutableSet new];
        
        NSMutableSet *usedFilenames = nil;
        BOOL parentIsDirectory;
        if ([[NSFileManager defaultManager] fileExistsAtPath:parentFolderURL.path isDirectory:&parentIsDirectory] && parentIsDirectory)
            usedFilenames = [self copyCurrentlyUsedFileNamesInFolderAtURL:parentFolderURL ignoringFileURL:nil];
        
        for (ODSFileItemMotion *motion in motions) {
            NSURL *sourceFileURL = motion.sourceFileURL;
            NSURL *destinationFileURL = motion.destinationFileURL;
            
            if (!destinationFileURL) {
                // Top level file (instead of something nested in a folder) that needs uniquing based on the used filenames in the destination.
                NSString *sourceFileName = [sourceFileURL lastPathComponent];
                __autoreleasing NSString *baseName = nil;
                NSUInteger counter;
                [[sourceFileName stringByDeletingPathExtension] splitName:&baseName andCounter:&counter];
                
                // The sourceFileURL might not exist if is for a non-downloaded OmniPresence document. So, we can't look up NSURLIsDirectoryKey.
                BOOL isDirectory = [[sourceFileURL absoluteString] hasSuffix:@"/"];
                
                NSString *destinationFilename = [self _availableFileNameAvoidingUsedFileNames:usedFilenames withBaseName:baseName extension:[sourceFileName pathExtension] counter:&counter];
                
                destinationFileURL = [parentFolderURL URLByAppendingPathComponent:destinationFilename isDirectory:isDirectory];
            }
            DEBUG_STORE(@"%@ %@ to %@", motionType, sourceFileURL, destinationFileURL);
            
            NSError *strongError;
            __autoreleasing NSError *actionError = nil;
            OFFileMotionResult *result = action(motion, destinationFileURL, &actionError);
            if (!result) {
                [actionError log:@"Error performing %@ of %@ to %@ in folder %@", motionType, sourceFileURL, destinationFileURL, parentFolderURL];
                strongError = actionError;
            } else {
                [usedFilenames addObject:[destinationFileURL lastPathComponent]];
            }
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (result) {
                    ODSFileItem *createdFileItem = _addItem(self, result);
                    ODSFileItemEdit *createdFileItemEdit = [ODSFileItemEdit fileItemEditWithFileItem:createdFileItem];
                    
                    [createdFileItems addObject:createdFileItem];
                    OBASSERT(createdFileItem);
                    if (status)
                        status(motion, destinationFileURL, createdFileItemEdit, nil);
                } else
                    if (status)
                        status(motion, destinationFileURL, nil, strongError);
            }];
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            // Build any new folders
            [self _updateItemTree];
            
            if (completionHandler) {
                NSSet *moveItems = createdFileItems;
                if ([motionType isEqualToString:@"COPY"]) {
                    // Give the completion handler the immediate children of parentFolder that were created (so if we had "a/b/c" duplicating "a/b" to "a/b2", we'd pass back "a/b2" not "a/b2/c".
                    moveItems = [parentFolder childrenContainingItems:moveItems];
                }
                DEBUG_STORE(@"%@ yielded added children %@", motionType, [moveItems valueForKey:@"shortDescription"]);
                completionHandler(moveItems);
            }
        }];
    }];
}

- (void)copyItems:(NSSet *)items toFolder:(ODSFolderItem *)parentFolder status:(ODSScopeItemMotionStatus)status completionHandler:(void (^)(NSSet *finalItems))completionHandler;
{
    // We send our 'finished' message here instead of inside the action since this block gets the result file item and is already dispatched to the main queue.
    status = [status copy];
    ODSScopeItemMotionStatus copyStatus = ^(ODSFileItemMotion *sourceItemMotion, NSURL *destinationURL, ODSFileItemEdit *destinationEditOrNil, NSError *error){
        OBASSERT([NSThread isMainThread]);
        OBASSERT((destinationEditOrNil == nil) ^ (error == nil));
        
        // This percolates up to copy the preview
        [self fileItemEdit:sourceItemMotion.originalItemEdit finishedCopyToURL:destinationURL withFileItemEdit:destinationEditOrNil];
        
        if (status)
            status(sourceItemMotion, destinationURL, destinationEditOrNil, error);
    };
    
    [self _doMotion:@"COPY" withItems:items toFolder:parentFolder ignoringFileItems:nil status:copyStatus completionHandler:completionHandler
             action:
     ^OFFileMotionResult *(ODSFileItemMotion *sourceItemMotion, NSURL *destinationFileURL, NSError **outError) {
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             // This percolates up to make the new location an alias for previews for the expected copy
             [self fileItemEdit:sourceItemMotion.originalItemEdit willCopyToURL:destinationFileURL];
         }];

         OFFileEdit *resultEdit = _performAdd(self, sourceItemMotion.sourceFileURL, destinationFileURL, AddByCreatingParentDirectories, outError);
         if (!resultEdit)
             return nil;
         return [[OFFileMotionResult alloc] initWithFileEdit:resultEdit];
     }];
}

- (NSURL *)_urlForFolder:(ODSFolderItem *)folder;
{
    OBPRECONDITION(folder);
    
    NSURL *url = self.documentsURL;
    if (folder != _rootFolder){
        if (!folder.relativePath) {
            OBStopInDebugger("Congratulations!  You've reproduced <bug:///120310> (Crasher: -[NSURL URLByAppendingPathComponent:isDirectory:]: component, components, or pathExtension cannot be nil).");
            return nil;
        }
        url = [url URLByAppendingPathComponent:folder.relativePath isDirectory:YES];
    }
    return url;
}

static NSURL *_destinationURLForMove(NSURL *sourceURL, NSURL *destinationDirectoryURL, NSString *destinationFileName)
{
    OBPRECONDITION([sourceURL isFileURL]);
    OBPRECONDITION([destinationDirectoryURL isFileURL]);
    OBPRECONDITION(![NSString isEmptyString:destinationFileName]);
    
    // We might be renaming a non-downloaded file, so we can't get the NSURLIsDirectoryKey from sourceURL.
    BOOL sourceIsDirectory = [[sourceURL absoluteString] hasSuffix:@"/"];
    
    return [destinationDirectoryURL URLByAppendingPathComponent:destinationFileName isDirectory:sourceIsDirectory];
}

- (void)updateFileItem:(ODSFileItem *)fileItem withBlock:(void (^)(void (^updateCompletionHandler)(BOOL success, NSURL *destinationURL, NSError *error)))block completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
    block(^void (BOOL success, NSURL *destinationURL, NSError *error) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            // Make sure our file item knows it got moved w/o waiting for file presenter notifications so that the document picker's lookups can find the right file item for animations. This means that when doing coordinated file moves, we should try to avoid getting notified by passing a file presenter to the coordinator (either the OFXAccountAgent, or the ODSLocalDirectoryScope).
            if (success) {
                [self completedMoveOfFileItem:fileItem toURL:destinationURL];
                if (completionHandler)
                    completionHandler(destinationURL, nil);
            } else {
                NSLog(@"Error renaming %@: %@", [fileItem shortDescription], [error toPropertyList]);
                if (completionHandler)
                    completionHandler(nil, error);
            }
        }];
    });
}

- (void)renameFileItem:(ODSFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileItem.scope == self); // Can't use this method to move between scopes
    
    completionHandler = [completionHandler copy];
    
    // The document should already live in the local documents directory, a sync container documents directory or a folder there under. Keep it in whichever one it was in.
    NSURL *containingDirectoryURL = [fileItem.fileURL URLByDeletingLastPathComponent];
    OBASSERT(containingDirectoryURL);
    OBASSERT(!ODSIsInInbox(containingDirectoryURL), "scanItemsWithCompletionHandler: now ignores the 'Inbox' so we should never get into this situation.");
    
    NSString *extension = OFPreferredPathExtensionForUTI(fileType);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *destinationFileName = [baseName stringByAppendingPathExtension:extension];
    
    NSURL *sourceURL = fileItem.fileURL;
    NSURL *destinationURL = _destinationURLForMove(sourceURL, containingDirectoryURL, destinationFileName);
    
    NSURL *sourceFolderURL = [sourceURL URLByDeletingLastPathComponent];
    
    // TODO: This is ugly. In the case of a move, at least, we want to pass the file presenter that would hear about the move so that it will not get notifications. We do this since we have to handle the notifications ourselves anyway (since sometimes they don't get sent -- for case-only renames, for example). ODSLocalDirectoryScope conforms, but OFXDocumentStoreScope does not, leaving OFXAccountAgent to deal with NSFilePresenter.
    id <NSFilePresenter> filePresenter;
    if ([self conformsToProtocol:@protocol(NSFilePresenter)])
        filePresenter = (id <NSFilePresenter>)self;
    
    [self performAsynchronousFileAccessUsingBlock:^{
        // Check if there is a file item with this name. Ignore the source URL so that the user can make capitalization/accent corrections in file names w/o getting a self-conflict.
        NSSet *usedFileNames = [self copyCurrentlyUsedFileNamesInFolderAtURL:sourceFolderURL ignoringFileURL:sourceURL];
        for (NSString *usedFileName in usedFileNames) {
            if ([usedFileName localizedCaseInsensitiveCompare:destinationFileName] == NSOrderedSame) {
                if (completionHandler) {
                    __autoreleasing NSError *error = nil;
                    NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"\"%@\" is already taken.", @"OmniDocumentStore", OMNI_BUNDLE, @"Error description when renaming a file to a name that is already in use."), baseName];
                    NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please choose a different name.", @"OmniDocumentStore", OMNI_BUNDLE, @"Error suggestion when renaming a file to a name that is already in use.");
                    ODSError(&error, ODSFilenameAlreadyInUse, description, suggestion);
                    
                    NSError *strongError = error;
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        completionHandler(nil, strongError);
                    }];
                }
                return;
            }
        }
        
        [self updateFileItem:fileItem withBlock:^ void (void (^updateCompletionHandler)(BOOL success, NSURL *destinationURL, NSError *error)) {
            __autoreleasing NSError *moveError;
            OFFileMotionResult *result = [self performMoveFromURL:sourceURL toURL:destinationURL filePresenter:filePresenter error:&moveError];
            
            NSError *strongError = result ? nil : moveError;
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                // Make sure our file item knows it got moved w/o waiting for file presenter notifications so that the document picker's lookups can find the right file item for animations. This means that when doing coordinated file moves, we should try to avoid getting notified by passing a file presenter to the coordinator (either the OFXAccountAgent, or the ODSLocalDirectoryScope).
                // Here since we are definitely renaming w/in the same folder, the scope can't have changed.
                if (result) {
                    [self completedMoveOfFileItem:fileItem toURL:destinationURL];
                }
            }];

            if (updateCompletionHandler)
                updateCompletionHandler(result != nil, destinationURL, strongError);
        } completionHandler:completionHandler];
    }];
}

static NSString *_filenameForUserGivenFolderName(NSString *name)
{
    if (![NSString isEmptyString:[name pathExtension]])
        return [name stringByAppendingPathExtension:OFDirectoryPathExtension];
    return name;
}

- (void)renameFolderItem:(ODSFolderItem *)folderItem baseName:(NSString *)baseName completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(folderItem.scope == self); // Can't use this method to move between scopes
    OBPRECONDITION(![NSString isEmptyString:baseName]);
    
    completionHandler = [completionHandler copy];

    NSString *folderFilename = _filenameForUserGivenFolderName(baseName);
    
    // We can't have two folders with the same name.
    if ([folderItem.parentFolder childItemWithFilename:folderFilename]) {
        if (completionHandler) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot rename folder.", @"OmniDocumentStore", OMNI_BUNDLE, @"Error message when renaming a folder and there is already a folder with the requested name.");
            NSString *message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Another folder already has the name \"%@\".", @"OmniDocumentStore", OMNI_BUNDLE, @"Error message when renaming a folder and there is already a folder with the requested name."), baseName];
            __autoreleasing NSError *error;
            ODSError(&error, ODSFilenameAlreadyInUse, description, message);
            
            completionHandler(nil, @[error]);
        }
        return;
    }
    
    // We want to update the name on *this* folder item rather than move the items into a new folder. This way, existing users of the folder item can keep their reference to the object.
    // Optimistically update the existing folder, but remember the original name in case there is an error
    NSString *originalRelativePath = folderItem.relativePath;
    folderItem.relativePath = [[folderItem.relativePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:folderFilename];
        
    [self _moveItems:folderItem.childItems toFolder:folderItem completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil){
        if ([movedFileItems count] == 0)
            folderItem.relativePath = originalRelativePath; // Oh well; put it back.
        else
            OBASSERT([folderItem.parentFolder.childItems containsObject:folderItem], "Folder should still be in the item tree");
        
        if (completionHandler)
            completionHandler(movedFileItems, errorsOrNil);
    }];
}

- (NSURL *)_moveURL:(NSURL *)sourceURL avoidingFileNames:(NSSet *)usedFilenames usingCoordinator:(BOOL)shouldUseCoordinator error:(NSError **)outError;
{
    OBPRECONDITION(![NSThread isMainThread], "We are going to do file coordination, and so want to avoid deadlock.");
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(![self isFileInContainer:sourceURL], "Should not be taking URLs we already have");

    // We presume the caller has already checked in with the scope as to whether it is OK to move the sourceURL out of it (it is fully downloaded).
    
    NSURL *scopeDocumentsURL = self.documentsURL;
    
    // Reading attributes of the source outside of file coordination, but we'd like to know whether it is a directory to build the proper destination URL, and we need to know the destination to do the coordination.
    NSURL *destinationURL;
    {
        __autoreleasing NSNumber *sourceIsDirectory = nil;
        __autoreleasing NSError *resourceError = nil;
        if (![sourceURL getResourceValue:&sourceIsDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
            NSLog(@"Error checking if source URL %@ is a directory: %@", [sourceURL absoluteString], [resourceError toPropertyList]);
            // not fatal...
        }
        OBASSERT(sourceIsDirectory);
        
        NSString *fileName = [sourceURL lastPathComponent];
        __autoreleasing NSString *baseName = nil;
        NSUInteger counter;
        [[fileName stringByDeletingPathExtension] splitName:&baseName andCounter:&counter];

        NSString *destinationFilename = [self _availableFileNameAvoidingUsedFileNames:usedFilenames withBaseName:baseName extension:[fileName pathExtension] counter:&counter];
        destinationURL = _destinationURLForMove(sourceURL, scopeDocumentsURL, destinationFilename);
    }

    __block BOOL success = NO;
    if (shouldUseCoordinator) {
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block NSError *strongError = nil;
        [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForMerging error:outError byAccessor:^(NSURL *newURL1, NSURL *newURL2) {

            DEBUG_STORE(@"Moving document: %@ -> %@ (scope %@)", sourceURL, destinationURL, self);
            // The documentation also says that this method does a coordinated move, so we don't need to (and in fact, experimentally, if we try we deadlock).
            __autoreleasing NSError *error;
            success = [[NSFileManager defaultManager] moveItemAtURL:sourceURL toURL:destinationURL error:&error];
            if (!success) {
                strongError = error;
            }
        }];
        if (!success) {
            if (outError) {
                *outError = strongError;
            }
        }
    } else {
        DEBUG_STORE(@"Moving document (without extra coordination): %@ -> %@ (scope %@)", sourceURL, destinationURL, self);
        success = [[NSFileManager defaultManager] moveItemAtURL:sourceURL toURL:destinationURL error:outError];
    }
    
    if (!success)
        return nil;
    return destinationURL;
}

- (void)makeFolderFromItems:(NSSet *)items inParentFolder:(ODSFolderItem *)parentFolder completionHandler:(void (^)(ODSFolderItem *createdFolder, NSArray *errorsOrNil))completionHandler;
{
    completionHandler = [completionHandler copy];

    /*
     Find an unused folder URL (might be racing with incoming sync'd changes. We don't scan inside the async block like we do for files since this can't be a document and if we lose the race we'll just bail.
     */
    NSURL *sourceFolderURL;
    NSURL *destinationFolderURL;
    NSString *destinationRelativePath;
    {
        NSMutableSet *usedFolderNames = [self _copyCurrentlyUsedFolderNamesInFolder:parentFolder];
        NSString *folderName = NSLocalizedStringWithDefaultValue(@"Untitled Folder", @"OmniDocumentStore", OMNI_BUNDLE, @"Untitled", @"title for new untitled folders");
        NSUInteger counter = 0;
        NSString *destinationFolderName = [self _availableFileNameAvoidingUsedFileNames:usedFolderNames withBaseName:folderName extension:nil counter:&counter];
        
        sourceFolderURL = self.documentsURL;
        NSString *parentRelativePath = parentFolder.relativePath;
        if (parentRelativePath && ![NSString isEmptyString:parentRelativePath])
            sourceFolderURL = [sourceFolderURL URLByAppendingPathComponent:parentRelativePath isDirectory:YES];
        destinationFolderURL = [sourceFolderURL URLByAppendingPathComponent:destinationFolderName isDirectory:YES];

        destinationRelativePath = OFFileURLRelativePath(self.documentsURL, destinationFolderURL);
        OBASSERT_NOTNULL(parentRelativePath);
        OBASSERT([destinationRelativePath isEqualToString:[parentRelativePath stringByAppendingPathComponent:destinationFolderName]]);
    }
    
    ODSFolderItem *subFolder = [[ODSFolderItem alloc] initWithScope:self];
    subFolder.relativePath = destinationRelativePath;
    
    [self _moveItems:items toFolder:subFolder completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil) {
        [subFolder _invalidate]; // Done with this temporary.
        
        if ([movedFileItems count] > 0) {
            // Some move worked, so there is a new folder even if some files got left behind.
            [self _updateItemTree];
            
            ODSFolderItem *resultFolder = (ODSFolderItem *)[_rootFolder itemWithRelativePath:destinationRelativePath];
            OBASSERT(resultFolder);
            OBASSERT(resultFolder.type == ODSItemTypeFolder);
            
            if (completionHandler)
                completionHandler(resultFolder, errorsOrNil);
        } else {
            if (completionHandler)
                completionHandler(nil, errorsOrNil);
        }
    }];
}

- (BOOL)isTrash;
{
    return NO;
}

static ODSScope *_trashScope = nil;

+ (ODSScope *)trashScope;
{
    return _trashScope;
}

+ (void)setTrashScope:(ODSScope *)trashScope;
{
    assert(_trashScope == nil); // We shouldn't have more than one trash in an iOS app
    _trashScope = trashScope;
    OBPRECONDITION(_trashScope == nil || [_trashScope isTrash]); // The trash scope should know it's the trash
}

// This risks deadlock, please try not to use it!
- (void)_performSynchronousFileAccessUsingBlock:(void (^)(void))block;
{
    if ([NSOperationQueue currentQueue] == _actionOperationQueue) {
        block();
        return;
    }

    [_actionOperationQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:block]] waitUntilFinished:YES];
}

+ (BOOL)trashItemAtURL:(NSURL *)url resultingItemURL:(NSURL **)outResultingURL error:(NSError **)outError;
{
    ODSScope *trashScope = [self trashScope];

    // Let's require the trash so we don't unrecoverably delete things we mean to recoverably delete
    assert(trashScope != nil);

    __block BOOL success = NO;
    __block NSError *strongError = nil;
    __block NSURL *resultingURL = nil;
    [trashScope _performSynchronousFileAccessUsingBlock:^{
        NSMutableSet *usedFilenames = [trashScope _copyCurrentlyUsedFileNamesInFolderAtURL:nil];

        __autoreleasing NSError *error = nil;
        resultingURL = [trashScope _moveURL:url avoidingFileNames:usedFilenames usingCoordinator:NO error:&error];
        if (!resultingURL) {
            strongError = error;
        }

        success = (resultingURL != nil);
    }];

    if (!success && outError) {
        *outError = strongError;
    }

    if (outResultingURL != NULL && resultingURL != nil)
        *outResultingURL = resultingURL;
    
    return success;
}

static ODSScope *_templateScope = nil;

- (BOOL)isTemplate;
{
    return NO;
}

+ (ODSScope *)templateScope;
{
    return _templateScope;
}

+ (void)setTemplateScope:(ODSScope *)templateScope;
{
    assert(_templateScope == nil); // We shouldn't have more than one template scope in an iOS app
    _templateScope = templateScope;
    OBPRECONDITION(_templateScope == nil || [_templateScope isTemplate]); // The template scope should know it's the template scope
}

- (BOOL)canRenameDocuments;
{
    return YES;
}

- (BOOL)canCreateFolders;
{
    return !self.isTrash;
}

- (BOOL)isExternal;
{
    return NO;
}

- (BOOL)prepareToRelinquishItem:(ODSItem *)item error:(NSError **)outError;
{
    return YES;
}

- (void)finishRelinquishingMovedItems:(NSSet *)movedItems;
{
    // For subclasses
}

- (void)_moveItems:(NSSet *)items toFolder:(ODSFolderItem *)parentFolder completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;
{
    [self _moveItems:items toFolder:parentFolder ignoringFileItems:nil completionHandler:completionHandler];
}

- (void)_moveItems:(NSSet *)items toFolder:(ODSFolderItem *)parentFolder ignoringFileItems:(NSSet *)ignoredFileItems completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // since we'll send the completion handler back to the main thread, make sure we came from there
    OBPRECONDITION(!parentFolder || parentFolder.scope == self);

    // This gets used for both moving items into our scope and moving them out.
    BOOL movingWithinSameScope;
    {
        ODSScope *sourceScope = [(ODSItem *)[items anyObject] scope];
        OBPRECONDITION([items all:^BOOL(ODSItem *item) { return item.scope == sourceScope; }], "All the items should be from the same scope");
        OBPRECONDITION(sourceScope == self || parentFolder.scope == self, "We should be involved in this move somehow, not an innocent bystander");
        
        // We calculate this here since if we are moving items to the trash, the source items might have been invalidated and had their scope cleared by the time we get to the status block.
        movingWithinSameScope = (sourceScope == self);
    }
    
    __block NSMutableSet *movedFileItems = [NSMutableSet new];
    __block NSMutableArray *errors = [NSMutableArray new];

    // For moves we pass back the original items (since they might be deleted or are otherwise likely out of view). Copies pass back the new items since they'll likely be duplicating but either way the originals should still be around.
    ODSScopeItemMotionStatus status = ^(ODSFileItemMotion *sourceItemMotion, NSURL *destionationFileURL, ODSFileItemEdit *destinationEditOrNil, NSError *errorOrNil){
        OBASSERT([NSThread isMainThread]);
        OBASSERT((destinationEditOrNil == nil) ^ (errorOrNil == nil));
        if (!destinationEditOrNil) {
            [errors addObject:errorOrNil];
            return;
        }
        
        [movedFileItems addObject:sourceItemMotion.fileItem];
        
        OBASSERT_IF(movingWithinSameScope, sourceItemMotion.fileItem == destinationEditOrNil.fileItem, "The URL on the file item should have been updated soon enough that we found the existing item and updated its URL"); // -completedMoveOfFileItem:toURL: should have been called and our fast item creation path should have thus found the updated item.
    };
    
    void (^motionCompletion)(NSSet *createdItems) = ^(NSSet *createdItems){
        OBASSERT([NSThread isMainThread]);
        if (completionHandler)
            completionHandler(createdItems, errors);
    };
    
    // TODO: This is ugly. In the case of a move, at least, we want to pass the file presenter that would hear about the move so that it will not get notifications. We do this since we have to handle the notifications ourselves anyway (since sometimes they don't get sent -- for case-only renames, for example). ODSLocalDirectoryScope conforms, but OFXDocumentStoreScope does not, leaving OFXAccountAgent to deal with NSFilePresenter.
    id <NSFilePresenter> filePresenter;
    if ([self conformsToProtocol:@protocol(NSFilePresenter)])
        filePresenter = (id <NSFilePresenter>)self;

    [self _doMotion:@"MOVE" withItems:items toFolder:parentFolder ignoringFileItems:(NSSet *)ignoredFileItems status:status completionHandler:motionCompletion
             action:
     ^OFFileMotionResult *(ODSFileItemMotion *sourceItemMotion, NSURL *destinationFileURL, NSError **outError) {
         OBASSERT(![NSThread isMainThread]);
         
         OFFileMotionResult *result = [self performMoveFromURL:sourceItemMotion.sourceFileURL toURL:destinationFileURL filePresenter:filePresenter error:outError];
         if (!result) {
             return nil;
         }
         
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [self.documentStore _fileItem:sourceItemMotion.fileItem willMoveToURL:destinationFileURL];
             
             // Make sure our file item knows it got moved w/o waiting for file presenter notifications so that the document picker's lookups can find the right file item for animations. This means that when doing coordinated file moves, we should try to avoid getting notified by passing a file presenter to the coordinator (either the OFXAccountAgent, or the ODSLocalDirectoryScope).
             if (!movingWithinSameScope) {
                 sourceItemMotion.fileItem.scope = self;
             }
             
             [self completedMoveOfFileItem:sourceItemMotion.fileItem toURL:destinationFileURL];
         }];
         return result;
     }];
}

// Move items that are in a different scope into this scope.
- (void)takeItems:(NSSet *)items toFolder:(ODSFolderItem *)folderItem ignoringFileItems:(NSSet *)ignoredFileItems completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;
{
    OBPRECONDITION([items any:^BOOL(ODSItem *item) { return item.scope == self; }] == nil, "None of the items should belong to this scope already");
    
    [self _moveItems:items toFolder:folderItem ignoringFileItems:ignoredFileItems completionHandler:completionHandler];
}

- (void)moveItems:(NSSet *)items toFolder:(ODSFolderItem *)folderItem completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;
{
    OBPRECONDITION([items all:^BOOL(ODSItem *item) { return item.scope == self; }], "All the items should belong to this scope already");
    
    [self _moveItems:items toFolder:folderItem completionHandler:completionHandler];
}

- (NSComparisonResult)compareDocumentScope:(ODSScope *)otherScope;
{
    NSInteger scopeGroupRank = self.documentScopeGroupRank;
    NSInteger otherScopeGroupRank = otherScope.documentScopeGroupRank;
    if (scopeGroupRank == otherScopeGroupRank)
        return [self.displayName localizedStandardCompare:otherScope.displayName];
    else if (scopeGroupRank < otherScopeGroupRank)
        return NSOrderedAscending;
    else
        return NSOrderedDescending;
}

- (NSInteger)documentScopeGroupRank;
{
    return 0;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

#pragma mark - Internal

- (NSMutableSet *)_copyCurrentlyUsedFileNamesInFolderAtURL:(NSURL *)folderURL;
{
    return [self copyCurrentlyUsedFileNamesInFolderAtURL:folderURL ignoringFileURL:nil];
}

- (void)invalidateUnusedFileItems:(NSDictionary *)cacheKeyToFileItem;
{
    [cacheKeyToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *fileIdentifier, ODSFileItem *fileItem, BOOL *stop) {
        [fileItem _invalidate];
    }];
}

- (OFFileMotionResult *)performMoveFromURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL filePresenter:(id <NSFilePresenter>)filePresenter error:(NSError **)outError;
{
    OBPRECONDITION(![NSThread isMainThread]); // We should be on the action queue
    // OBPRECONDITION([self isFileInContainer:sourceURL]); // This is used to move files into scopes (moving from Local documents to OmniPresence, vice versa, and from scopes out to the Trash.
    
    DEBUG_STORE(@"Perform move from %@ to %@", sourceURL, destinationURL);
    
    __autoreleasing NSError *coordinatorError = nil;
    
#if DEBUG_STORE_ENABLED
    for (id <NSFilePresenter> presenter in [NSFileCoordinator filePresenters]) {
        NSLog(@"  presenter %@ at %@", [(id)presenter shortDescription], presenter.presentedItemURL);
    }
#endif
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:filePresenter];
    
    __block OFFileEdit *resultFileEdit = nil;
    __block NSError *fileEditError = nil;
    
    BOOL success = [coordinator moveItemAtURL:sourceURL toURL:destinationURL createIntermediateDirectories:YES error:&coordinatorError success:^(NSURL *resultURL) {
        __autoreleasing NSError *error;
        resultFileEdit = [[OFFileEdit alloc] initWithFileURL:resultURL error:&error];
        if (!resultFileEdit) {
            OBASSERT_NOT_REACHED("Success shouldn't have been called if the move was a success");
            fileEditError = error;
        }
    }];

    if (success) {
        if (!resultFileEdit) {
            // Again, this shouldn't happen, but just in case...
            if (outError)
                *outError = fileEditError;
            return nil;
        }

        // The file coordinator might have given us a temporary URL. Make sure we are reporting the state that should have existed at the moment the coordinated move finished (though of course, by now, racing edits may have changed things).
        resultFileEdit = [[OFFileEdit alloc] initWithFileURL:destinationURL fileModificationDate:resultFileEdit.fileModificationDate inode:resultFileEdit.inode isDirectory:resultFileEdit.directory];
        
        return [[OFFileMotionResult alloc] initWithFileEdit:resultFileEdit];
    }
    
    if (outError)
        *outError = coordinatorError;
    return nil;
}

- (void)completedMoveOfFileItem:(ODSFileItem *)fileItem toURL:(NSURL *)destinationURL;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    [self.documentStore _fileItem:fileItem willMoveToURL:destinationURL];
    [fileItem didMoveToURL:destinationURL];

    // We don't call -_updateItemTree since this gets called for moves w/in a folder. The caller is responsible for handling this if needed.
    //[self _updateItemTree];
}

- (void)fileItemEdit:(ODSFileItemEdit *)fileItemEdit willCopyToURL:(NSURL *)newURL;
{
    [self.documentStore _fileItemEdit:fileItemEdit willCopyToURL:newURL];
}
- (void)fileItemEdit:(ODSFileItemEdit *)fileItemEdit finishedCopyToURL:(NSURL *)destinationURL withFileItemEdit:(ODSFileItemEdit *)destinationFileItemEditOrNil;
{
    [self.documentStore _fileItemEdit:fileItemEdit finishedCopyToURL:(NSURL *)destinationURL withFileItemEdit:destinationFileItemEditOrNil];
}

- (void)_fileItemContentsChanged:(ODSFileItem *)fileItem;
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fileItem forKey:ODSFileItemInfoKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:ODSFileItemContentsChangedNotification object:self.documentStore userInfo:userInfo];
}

- (void)updateFileItem:(ODSFileItem *)fileItem withMetadata:(id)metadata fileEdit:(OFFileEdit *)fileEdit;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderAtURL:(NSURL *)folderURL ignoringFileURL:(NSURL *)fileURLToIgnore;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)isRunningOnActionQueue;
{
    return [NSOperationQueue currentQueue] == _actionOperationQueue;
}
#endif

#pragma mark - Private

// We CANNOT check for file non-existence here. Cloud documents may be present on the server and we may only know about them via a metadata item that produced an ODSFileItem. So, we take in an array of URLs and unique against that.
NSString *ODSScopeFindAvailableName(NSSet *usedFileNames, NSString *baseName, NSString *extension, NSUInteger *ioCounter)
{
    NSUInteger counter = *ioCounter; // starting counter
    
    while (YES) {
        NSString *candidateName;
        if (counter == 0) {
            candidateName = baseName;
            counter = 2; // First duplicate should be "Foo 2".
        } else {
            candidateName = [[NSString alloc] initWithFormat:@"%@ %lu", baseName, counter];
            counter++;
        }
        
        if (![NSString isEmptyString:extension]) { // Is nil when we are creating new folders
            OBASSERT_NOTNULL(extension);
            candidateName = [candidateName stringByAppendingPathExtension:extension];
        }
        
        // Not using -memeber: because it uses -isEqual: which was incorrectly returning nil with some Japanese filenames.
        NSString *matchedFileName = [usedFileNames any:^BOOL(id object) {
            NSString *usedFileName = (NSString *)object;
            if ([usedFileName localizedCaseInsensitiveCompare:candidateName] == NSOrderedSame) {
                return YES;
            }
            
            return NO;
        }];
        
        if (matchedFileName == nil) {
            *ioCounter = counter; // report how many we used
            return candidateName;
        }
    }
}

- (NSString *)_availableFileNameAvoidingUsedFileNames:(NSSet *)usedFilenames withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    OBPRECONDITION(_fileItems); // Make sure we've done a local scan. It might be out of date, so maybe we should scan here too.
    OBPRECONDITION(self.hasFinishedInitialScan); // We can't unique against other files until we know what is there
    
    return ODSScopeFindAvailableName(usedFilenames, baseName, extension, ioCounter);
}

- (NSString *)_availableFileNameInFolderAtURL:(NSURL *)folderURL withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    NSSet *usedFileNames = [self _copyCurrentlyUsedFileNamesInFolderAtURL:folderURL];
    NSString *fileName = [self _availableFileNameAvoidingUsedFileNames:usedFileNames withBaseName:baseName extension:extension counter:ioCounter];
    return fileName;
}

- (NSURL *)_urlForFolderAtURL:(NSURL *)folderURL fileName:(NSString *)fileName isDirectory:(BOOL)isDirectory error:(NSError **)outError;
{
    OBPRECONDITION(fileName);
    
    NSURL *documentsURL = self.documentsURL;
    if (folderURL)
        OBASSERT(OFURLContainsURL(documentsURL, folderURL));
    else
        folderURL = documentsURL;
        
    return [folderURL URLByAppendingPathComponent:fileName isDirectory:isDirectory];
}

static void _addChildItem(NSMutableDictionary *folderItemByRelativePath, NSMutableDictionary *folderItemToChildItems, ODSFolderItem *parent, ODSItem *childItem)
{
    OBASSERT(parent != childItem, @"can't add parent as a child of itself!  we'll crash eventually in a KVO loop!");
    NSMutableSet *childItems = folderItemToChildItems[parent];
    if (!childItems) {
        childItems = [NSMutableSet new];
        folderItemToChildItems[parent] = childItems;
        
        // This folder now is marked as having content, so hook it to its parent (and so up to the root).
        NSString *relativePath = parent.relativePath;
        if (![NSString isEmptyString:relativePath]) {
            relativePath = [parent.relativePath stringByDeletingLastPathComponent];
            ODSFolderItem *container = folderItemByRelativePath[relativePath];
            _addChildItem(folderItemByRelativePath, folderItemToChildItems, container, parent);
        }
    }
    [childItems addObject:childItem];
}

static ODSFolderItem *_folderItemWithRelativePath(ODSScope *self, NSString *relativePath, NSMutableDictionary *folderItemByRelativePath, NSMutableDictionary *folderItemToChildItems)
{
    ODSFolderItem *folderItem = folderItemByRelativePath[relativePath];
    if (folderItem)
        return folderItem;
    
    folderItem = folderItemByRelativePath[[relativePath lowercaseString]];
    if (folderItem) {
        // Cache the new case "spelling" for something we've seen before (to avoid further calls to -lowercaseString, which is expensive). We merge all the items for a group into one (indeterminate) spelling of a folder name (since the iOS filesystem is case-sensitive, but we should be hiding this when we can).
        folderItemByRelativePath[relativePath] = folderItem;
        return folderItem;
    }
    
    // New folder!
    folderItem = [[ODSFolderItem alloc] initWithScope:self];
    folderItem.relativePath = relativePath;
    
    folderItemByRelativePath[relativePath] = folderItem;
    folderItemByRelativePath[[relativePath lowercaseString]] = folderItem;
    
    // Add this folder to its parent folder
    OBASSERT(![NSString isEmptyString:relativePath]);
    NSString *containingFolderRelativePath = [relativePath stringByDeletingLastPathComponent];
    ODSFolderItem *parentFolderItem = _folderItemWithRelativePath(self, containingFolderRelativePath, folderItemByRelativePath, folderItemToChildItems);
    _addChildItem(folderItemByRelativePath, folderItemToChildItems, parentFolderItem, folderItem);

    return folderItem;
}

- (void)_updateItemTree
{
    // Reuse folders from previous scans so UI sitting atop us can hold onto them w/o needless churn.
    NSMutableDictionary *folderItemByRelativePath = [NSMutableDictionary new];
    NSMutableDictionary *folderItemToChildItems = [NSMutableDictionary new];
    
    [_rootFolder eachFolder:^(ODSFolderItem *folder, BOOL *stop) {
        // Register the old folders by relative path
        NSString *relativePath = folder.relativePath;
        folderItemByRelativePath[relativePath] = folder;
        folderItemByRelativePath[[relativePath lowercaseString]] = folder;
    }];
    
    NSURL *documentsURL = self.documentsURL;

    for (ODSFileItem *fileItem in _fileItems) {
        NSURL *fileURL = fileItem.fileURL;
        NSString *folderRelativePath;
        if (documentsURL == nil) {
            folderRelativePath = @"";
        } else {
            OBASSERT(OFURLContainsURL(documentsURL, fileURL));
        
            NSString *relativePath = OFFileURLRelativePath(documentsURL, fileURL);
            folderRelativePath = [relativePath stringByDeletingLastPathComponent];
        }
        ODSFolderItem *folderItem = _folderItemWithRelativePath(self, folderRelativePath, folderItemByRelativePath, folderItemToChildItems);
        _addChildItem(folderItemByRelativePath, folderItemToChildItems, folderItem, fileItem);
    }
    
    //
#if DEBUG_STORE_ENABLED
    {
        NSLog(@"Scanned folders:");
        for (NSString *relativePath in [[folderItemByRelativePath allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
            NSLog(@"  %@ -> %@", relativePath, folderItemByRelativePath[relativePath]);
        }
        
        NSLog(@"Scanned folder contents:");
        NSArray *sortedFolderItems = [[folderItemToChildItems allKeys] sortedArrayUsingComparator:^NSComparisonResult(ODSFolderItem *folder1, ODSFolderItem *folder2) {
            if (![folder1 isKindOfClass:[ODSFolderItem class]])
                return NSOrderedDescending;
            if (![folder2 isKindOfClass:[ODSFolderItem class]])
                return NSOrderedAscending;
            
            return [folder1.relativePath localizedStandardCompare:folder2.relativePath];
        }];
        for (ODSFolderItem *folderItem in sortedFolderItems) {
            NSSet *childItems = folderItemToChildItems[folderItem];
            NSLog(@"  %@ -> %@", [folderItem shortDescription], [childItems setByPerformingSelector:@selector(shortDescription)]);
        }
    }
#endif
    
    // Populate folders, discarding any folders that didn't end up transitively containing files.
    NSMutableArray *usedFolderItems = [NSMutableArray new];
    [folderItemToChildItems enumerateKeysAndObjectsUsingBlock:^(ODSFolderItem *folder, NSSet *childItems, BOOL *stop) {
        if ([childItems count] == 0 && folder != _rootFolder) {
            DEBUG_STORE(@"Discarding empty folder %@", [folder shortDescription]);
            [folder _invalidate];
        } else {
            folder.childItems = childItems;
            [usedFolderItems addObject:folder];
        }
    }];
    
    // Could solve this a number of ways, but handle the special case of transitioning to zero files.
    if ([folderItemToChildItems count] == 0)
        _rootFolder.childItems = [NSSet set];
}

@end
