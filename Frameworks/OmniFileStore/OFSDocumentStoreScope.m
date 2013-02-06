// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentSToreScope-Subclass.h>

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OFVersionNumber.h>

#import "OFSDocumentStore-Internal.h"
#import "OFSDocumentStoreFileItem-Internal.h"
#import "OFSDocumentStoreItem-Internal.h"
#import "OFSDocumentStoreScope-Internal.h"

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <CoreServices/CoreServices.h>
#else
#import <MobileCoreServices/MobileCoreServices.h>
#endif

RCS_ID("$Id$");

@interface OFSDocumentStoreScope ()
// Forward declarations for C functions
- (NSString *)_availableFileNameInFolderNamed:(NSString *)folderName withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
@end

@implementation OFSDocumentStoreScope
{
    NSOperationQueue *_actionOperationQueue;

    NSDictionary *_groupItemByName;
    NSSet *_topLevelItems;
}

// The returned key is only valid within the owning scope.
NSString *OFSDocumentStoreScopeCacheKeyForURL(NSURL *url)
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
    return OFSURLContainsURL(containerURL, fileURL);
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithDocumentStore:(OFSDocumentStore *)documentStore;
{
    OBPRECONDITION([self conformsToProtocol:@protocol(OFSDocumentStoreConcreteScope)]); // Make sure subclasses declare conformance
    OBPRECONDITION(documentStore);
    
    if (!(self = [super init]))
        return nil;
    
    _weak_documentStore = documentStore;

    _actionOperationQueue = [[NSOperationQueue alloc] init];
    _actionOperationQueue.name = @"OFSDocumentStoreScope Actions";
    _actionOperationQueue.maxConcurrentOperationCount = 1;

    _groupItemByName = [NSMutableDictionary new];
    _topLevelItems = [NSMutableSet new];

    return [super init];
}

- (void)dealloc;
{
    for (OFSDocumentStoreFileItem *fileItem in _fileItems)
        [fileItem _invalidate];
    
    for (NSString *groupName in _groupItemByName)
        [[_groupItemByName objectForKey:groupName] _invalidate];

    OBASSERT([_actionOperationQueue operationCount] == 0);
}

@synthesize documentStore = _weak_documentStore;

- (BOOL)isFileInContainer:(NSURL *)fileURL;
{
    return [[self class] isFile:fileURL inContainer:[self documentsURL:NULL]];
}

+ (BOOL)automaticallyNotifiesObserversOfFileItems;
{
    return NO;
}

- (void)setFileItems:(NSSet *)fileItems;
{
    OBPRECONDITION([NSThread isMainThread]); // Our KVO should fire only on the main thread
#ifdef OMNI_ASSERTIONS_ON
    for (OFSDocumentStoreFileItem *fileItem in fileItems) {
        OBASSERT(fileItem.scope == self); // file items cannot move between scopes
        OBASSERT([self isFileInContainer:fileItem.fileURL]); // should have a URL we claim
    }
#endif
    
    if ([_fileItems isEqual:fileItems])
        return;
    
    [self willChangeValueForKey:OFValidateKeyPath(self, fileItems)];
    _fileItems = [[NSSet alloc] initWithSet:fileItems];
    [self didChangeValueForKey:OFValidateKeyPath(self, fileItems)];
    
    [self _updateTopLevelItems];
}

- (OFSDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after our first scan is done
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with changes to the fileItems property
    
    if (url == nil || ![url isFileURL])
        return nil;
    
    NSString *standardizedPathForURL = [[[url path] stringByResolvingSymlinksInPath] stringByStandardizingPath];
    OBASSERT(standardizedPathForURL != nil);
    for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
        NSString *fileItemPath = [[[fileItem.fileURL path] stringByResolvingSymlinksInPath] stringByStandardizingPath];
        OBASSERT(fileItemPath != nil);
        
        DEBUG_STORE(@"- Checking file item: '%@'", fileItemPath);
        if ([fileItemPath compare:standardizedPathForURL] == NSOrderedSame)
            return fileItem;
    }
    DEBUG_STORE(@"Couldn't find file item for path: '%@'", standardizedPathForURL);
    DEBUG_STORE(@"Unicode: '%s'", [standardizedPathForURL cStringUsingEncoding:NSNonLossyASCIIStringEncoding]);
    return nil;
}

- (OFSDocumentStoreFileItem *)fileItemWithName:(NSString *)fileName inFolder:(NSString *)folder;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Look through _fileItems for file with fileName in folder.
    for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
        NSString *itemFileName = [fileItem.fileURL lastPathComponent];

        OBFinishPortingLater("Handle folders again");
        NSString *itemFolderName = nil;
        //NSString *itemFolderName = OFSFolderNameForFileURL(fileItem.fileURL);
        
        // Check fileName and folder.
        if (([itemFolderName localizedCaseInsensitiveCompare:folder] == NSOrderedSame) &&
            ([itemFileName localizedCaseInsensitiveCompare:fileName] == NSOrderedSame)) {
            return fileItem;
        }
    }
    
    return nil;
}

- (OFSDocumentStoreFileItem *)makeFileItemForURL:(NSURL *)fileURL date:(NSDate *)date;
{
    OFSDocumentStore *documentStore = self.documentStore;
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
    OBASSERT(OBClassIsSubclassOfClass(fileItemClass, [OFSDocumentStoreFileItem class]));
    
#ifdef OMNI_ASSERTIONS_ON
    for (id <NSFilePresenter> presenter in [NSFileCoordinator filePresenters]) {
        if (![presenter isKindOfClass:[OFSDocumentStoreFileItem class]])
            continue;
        OFSDocumentStoreFileItem *otherFileItem  = (OFSDocumentStoreFileItem *)presenter;
        if (otherFileItem.beingDeleted)
            continue; // Replacing a file with a new one.
        if (otherFileItem.scope != self)
            continue; // cache keys aren't comparable across scopes
        OBASSERT(OFNOTEQUAL(OFSDocumentStoreScopeCacheKeyForURL(otherFileItem.presentedItemURL), OFSDocumentStoreScopeCacheKeyForURL(fileURL)));
    }
#endif
    
    OFSDocumentStoreFileItem *fileItem = [[fileItemClass alloc] initWithScope:self fileURL:fileURL date:date];
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Shouldn't make file items for files we can't view.
    OBASSERT([documentStore canViewFileTypeWithIdentifier:fileItem.fileType]);
#endif
    
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
static void _addItemAndNotifyHandler(OFSDocumentStoreScope *self, void (^handler)(OFSDocumentStoreFileItem *createdFileItem, NSError *error), NSURL *createdURL, NSError *error)
{
    // As we modify our _fileItem set here and fire KVO, this should be on the main thread.
    OBPRECONDITION([NSThread isMainThread]);
    
    // We just successfully wrote a new document; there is no need to do a full scan (though one may fire anyway if a metadata update starts due to a scope noticing the edit). Still, we want to get back to the UI as soon as possible by calling the completion handler w/o waiting for the scan.
    OFSDocumentStoreFileItem *fileItem = nil;
    if (createdURL) {
        NSDate *date = nil;
        if (![createdURL getResourceValue:&date forKey:NSURLContentModificationDateKey error:NULL]) {
            OBASSERT_NOT_REACHED("We just created it...");
        }
        
        // The delegate is in charge of making sure that the file will sort to the top if the UI is sorting files by date. If it just copies a template, then it may need to call -[NSFileManager touchItemAtURL:error:]
        OBASSERT(date);
        OBASSERT([date timeIntervalSinceNow] < 0.5);
        
        // If we are replacing an existing document, there may already be a file item (but it is probably marked for deletion). But we also want to be careful that if there was a scan completed and repopulated _fileItems that *did* capture this URL, we don't want make a new file item for the same URL.
        OFSDocumentStoreFileItem *addedFileItem = nil;
        OFSDocumentStoreFileItem *deletedFileItem = nil;
        
        fileItem = [self fileItemWithURL:createdURL];
        if (fileItem.beingDeleted) {
            deletedFileItem = fileItem;
            fileItem = nil; // Ignore this one and make another for the newly replacing file
        }
        
        if (fileItem)
            fileItem.date = date;
        else {
            addedFileItem = [self makeFileItemForURL:createdURL date:date];
            if (!addedFileItem) {
                OBASSERT_NOT_REACHED("Some error in the delegate where we created a file of a type we don't display?");
            } else {
                fileItem = addedFileItem;
            
                // Start out with the right state when duplicating an item and otherwise set default metadata.
                [self updateFileItem:fileItem withMetadata:nil modificationDate:date];
            }
        }
        
        if (deletedFileItem) {
            OBASSERT([self.fileItems member:deletedFileItem] == deletedFileItem);
                        
            [[self mutableSetValueForKey:OFValidateKeyPath(self, fileItems)] removeObject:deletedFileItem];
                        
            // Since we've removed the deleted file item here, we'll lose track of it and never send it -_invalidate if we aren't careful. The deleted item might still be in a NSFilePresenter relinquish-to-writer block and we don't want to send _invalidate while it is still dealing with that. Still, if we don't remove it here, we have to avoid reusing it elsewhere when looking up file items by URL. So, we opt for the immediate removal and tell the file item to invalidate itself once it gets out of its writer block.
            [deletedFileItem _invalidateAfterWriter];
        }
        
        if (addedFileItem) {
            OBASSERT([self.fileItems member:addedFileItem] == nil);
                        
            [[self mutableSetValueForKey:OFValidateKeyPath(self, fileItems)] addObject:addedFileItem];
        }
    }
    
    if (handler)
        handler(fileItem, error);
}

- (NSURL *)urlForNewDocumentInFolderNamed:(NSString *)folderName baseName:(NSString *)name fileType:(NSString *)documentUTI;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _actionOperationQueue);
    
    OBPRECONDITION(documentUTI);
        
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)documentUTI, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSUInteger counter = 0;
        
    NSURL *fileURL = [self _availableURLInFolderNamed:folderName withBaseName:name extension:(__bridge NSString *)extension counter:&counter];
    CFRelease(extension);
    
    return fileURL;
}

- (void)performDocumentCreationAction:(OFSDocumentStoreScopeDocumentCreationAction)createDocument handler:(OFSDocumentStoreScopeDocumentCreationHandler)handler;
{
    OBPRECONDITION(createDocument);
    
    createDocument = [createDocument copy];
    handler = [handler copy];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        createDocument(^(NSURL *resultURL, NSError *errorOrNil){
            _addItemAndNotifyHandler(self, handler, resultURL, errorOrNil);
        });
    }];
}

static BOOL _performAdd(OFSDocumentStoreScope *scope, NSURL *fromURL, NSURL *toURL, BOOL isReplacing, NSError **outError)
{
    OBPRECONDITION(![NSThread isMainThread]); // Were going to do file coordination which could deadlock with file presenters on the main thread
    OBASSERT_NOTNULL(outError); // We know we pass in a non-null pointer, so we can avoid the outError-NULL checks.
    
    // We might be able to do a coordinated read/write to duplicate documents. Since we need to sometimes move, let's just always do that. Since the source might have incoming sync writes or have presenters with outstanding writes, do a coordinated read while copying it into a temporary location. It is a bit annoying that we have two separate operations, but we should still get a consistent snapshot of the source at our destination location.
    NSURL *temporaryURL;
    {
        NSFileManager *manager = [NSFileManager defaultManager];
        NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[fromURL lastPathComponent]];
        temporaryPath = [manager uniqueFilenameFromName:temporaryPath allowOriginal:YES create:NO error:outError];
        if (!temporaryPath)
            return NO;
        
        temporaryURL = [NSURL fileURLWithPath:temporaryPath];
        DEBUG_STORE(@"Making copy of %@ at %@", fromURL, temporaryURL);
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block BOOL success = NO;
        __block NSError *innerError = nil;
        
        NSError *error = nil;
        [coordinator coordinateReadingItemAtURL:fromURL options:0
                               writingItemAtURL:temporaryURL options:NSFileCoordinatorWritingForReplacing
                                          error:&error byAccessor:
         ^(NSURL *newReadingURL, NSURL *newWritingURL) {
             NSError *copyError = nil;
             if (![manager copyItemAtURL:newReadingURL toURL:newWritingURL error:&copyError]) {
                 NSLog(@"Error copying %@ to %@: %@", fromURL, temporaryURL, [copyError toPropertyList]);
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
            return NO;
        }
    }
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block BOOL success = NO;
    __block NSError *innerError = nil;
    NSError *error = nil;
    
    [coordinator coordinateReadingItemAtURL:fromURL options:0
                           writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing
                                      error:&error byAccessor:
     ^(NSURL *newReadingURL, NSURL *newWritingURL) {
         NSFileManager *manager = [NSFileManager defaultManager];
         
         if (isReplacing) {
             NSError *removeError = nil;
             if (![manager removeItemAtURL:newWritingURL error:&removeError]) {
                 if (![removeError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) {
                     innerError = removeError;
                     NSLog(@"Error removing %@: %@", toURL, [removeError toPropertyList]);
                     return;
                 }
             }
         }
         
         NSError *moveError = nil;
         if (![manager moveItemAtURL:temporaryURL toURL:toURL error:&moveError]) {
             NSLog(@"Error moving %@ -> %@: %@", temporaryURL, toURL, [moveError toPropertyList]);
             innerError = moveError;
             return;
         }
         
         success = YES;
     }];
    
    
    if (!success) {
        OBASSERT(error || innerError);
        if (innerError)
            error = innerError;
        *outError = error;
        
        // Clean up the temporary copy
        [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:NULL];
        
        return NO;
    }
    
    return YES;
}

- (void)addDocumentInFolderNamed:(NSString *)folderName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    [self addDocumentInFolderNamed:folderName baseName:nil fromURL:fromURL option:option completionHandler:completionHandler];
}

// Enqueues an operationon the scope's background serial action queue. The completion handler will be called with the resulting file item, nil file item and an error.
- (void)addDocumentInFolderNamed:(NSString *)folderName baseName:(NSString *)baseName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // We'll invoke the completion handler on the main thread
    
    // Don't copy in random files that the user tapped on in the WebDAV browser or that higher level UI didn't filter out.
    BOOL canView = ([self.documentStore fileItemClassForURL:fromURL] != Nil);
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    NSString *fileType = OFUTIForFileURLPreferringNative(fromURL, NULL);
    canView &= (fileType != nil) && [self.documentStore canViewFileTypeWithIdentifier:fileType];
#endif
    if (!canView) {
        if (completionHandler) {
            __autoreleasing NSError *error = nil;
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to add document.", @"OmniFileStore", OMNI_BUNDLE, @"Error description when a file type is not recognized.");
            NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
            OBASSERT(![NSString isEmptyString:appName]);
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ does not recognize this kind of file.", @"OmniFileStore", OMNI_BUNDLE, @"Error reason when a file type is not recognized."), appName];
            
            OFSError(&error, OFSUnrecognizedFileType, description, reason);
            completionHandler(nil, error);
        }
        return;
    }
    
    if (!completionHandler)
        completionHandler = ^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
            if (!duplicateFileItem)
                NSLog(@"Error adding document from %@: %@", fromURL, [error toPropertyList]);
        };
    
    completionHandler = [completionHandler copy]; // preserve scope
    
    // Convenience for dispatching the completion handler to the main queue.
    void (^callCompletaionHandlerOnMainQueue)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) = ^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
        OBPRECONDITION(![NSThread isMainThread]);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(duplicateFileItem, error);
        }];
    };
    callCompletaionHandlerOnMainQueue = [callCompletaionHandlerOnMainQueue copy];
    
    NSError *documentsError = nil;
    if (![self documentsURL:&documentsError]) {
        callCompletaionHandlerOnMainQueue(nil, documentsError);
        return;
    }
    
    
    // We cannot decide on the destination URL w/o synchronizing with the action queue. In particular, if you try to duplicate "A" and "A 2", both operations could pick "A 3".
    [self performAsynchronousFileAccessUsingBlock:^{
        NSURL *toURL = nil;
        NSString *toFileName = (baseName) ? [baseName stringByAppendingPathExtension:[[fromURL lastPathComponent] pathExtension]] : [fromURL lastPathComponent];
        BOOL isReplacing = NO;
        
        if (option == OFSDocumentStoreAddNormally) {
            // Use the given file name.
            NSError *urlError = nil;
            toURL = [self _urlForFolderName:folderName fileName:toFileName error:&urlError];
            if (!toURL) {
                callCompletaionHandlerOnMainQueue(nil, urlError);
                return;
            }
        }
        else if (option == OFSDocumentStoreAddByRenaming) {
            // Generate a new file name.
            NSString *toBaseName = nil;
            NSUInteger counter;
            [[toFileName stringByDeletingPathExtension] splitName:&toBaseName andCounter:&counter];
            
            toFileName = [self _availableFileNameInFolderNamed:folderName withBaseName:toBaseName extension:[toFileName pathExtension] counter:&counter];
            
            NSError *urlError = nil;
            toURL = [self _urlForFolderName:folderName fileName:toFileName error:&urlError];
            if (!toURL) {
                callCompletaionHandlerOnMainQueue(nil, urlError);
                return;
            }
        }
        else if (option == OFSDocumentStoreAddByReplacing) {
            // Use the given file name, but ensure that it does not exist in the documents directory.
            NSError *urlError = nil;
            toURL = [self _urlForFolderName:folderName fileName:toFileName error:&urlError];
            if (!toURL) {
                callCompletaionHandlerOnMainQueue(nil, urlError);
                return;
            }
            
            isReplacing = YES;
        }
        else {
            // TODO: Perhaps we should create an error and assign it to outError?
            OBASSERT_NOT_REACHED("OFSDocumentStoreAddOpiton not given or invalid.");
            callCompletaionHandlerOnMainQueue(nil, nil);
            return;
        }
        
        // TODO: Add the same file item creation that adding new documents does to avoid having to rescan here.
        NSError *addError = nil;
        BOOL success = _performAdd(self, fromURL, toURL, isReplacing, &addError);
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (success)
                _addItemAndNotifyHandler(self, completionHandler, toURL, nil);
            else
                _addItemAndNotifyHandler(self, completionHandler, nil, addError);
        }];
    }];
}

static NSURL *_destinationURLForMove(NSURL *sourceURL, NSURL *destinationDirectoryURL, NSString *destinationFileName)
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destinationDirectoryURL);
    OBPRECONDITION(destinationFileName);
    
    NSNumber *sourceIsDirectory = nil;
    NSError *resourceError = nil;
    if (![sourceURL getResourceValue:&sourceIsDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
        NSLog(@"Error checking if source URL %@ is a directory: %@", [sourceURL absoluteString], [resourceError toPropertyList]);
        // not fatal...
    }
    OBASSERT(sourceIsDirectory);
    
    return [destinationDirectoryURL URLByAppendingPathComponent:destinationFileName isDirectory:[sourceIsDirectory boolValue]];
}

// Helper for _coordinatedMoveItem. See commentary below for why this is structured the way it is.
static NSOperation *_completeCoordinatedMoveItem(OFSDocumentStoreFileItem *fileItem, NSURL *destinationURL, NSError *error, NSOperationQueue *completionQueue, void (^completionHandler)(NSURL *destinationURL, NSError *errorOrNil))
{
    // We tell NSFileCoordinator for the move to *not* send our fileItem presenter notifications, we have the responsibility to notify it.
    
    // It isn't 100% clear if we should pass destinationURL to -itemAtURL:didMoveToURL or whether we should pass newURL2. Experimentally, passing destinationURL works, but I haven't been able to provoke NSFileCoordinator into passing newURL2 != destinationURL. I'm assuming that NSFileCoordinator will not call -presentedItemDidMoveToURL: if it needs to give us a temporary URL. It could be that we are located at a temporary URL right this second, but by the time we return from this coordination the file coordinator should have moved us to the temporary URL. We just want to get our notification in before anything else can queue something up.
    // This means that scanning operations will need to both consider the current file item URL and its expected eventual file URL, otherwise if we can in the middle of a move, we may remove one file item and add another (yielding an animation glitch).
    
    NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        if (destinationURL)
            [fileItem presentedItemDidMoveToURL:destinationURL];
        else
            NSLog(@"Error renaming %@: %@", [fileItem shortDescription], [error toPropertyList]);
        
        if (completionHandler) {
            [completionQueue addOperationWithBlock:^{
                completionHandler(destinationURL, error);
            }];
        }
    }];
    [[fileItem presentedItemOperationQueue] addOperation:op];
    return op;
}

static NSOperation *_checkRenamePreconditions(OFSDocumentStoreFileItem *fileItem, NSURL *sourceURL, NSURL *newURL1, NSOperationQueue *completionQueue, void (^completionHandler)(NSURL *destinationURL, NSError *errorOrNil))
{
    // It's arguable that we should allow this.
    // Validate that the file hasn't been deleted or moved. Before this coordinator is allowed to invoke its accessor, we assume the coordinator blocks until the presenters for the involved URLs have fully hear about -presentedItemDidMoveToURL:. Experimetally this is the case (though they may not have gotten a 'reacquire' called yet. In the case of deletion, our fileURL property will point into the UBD dead zone.
    // -URLByStandardizingPath only works if the URL exists, so we only normalize the parent URL and then compare the last path component (so that /var/mobile vs /var/private/mobile differences won't hurt).
    NSURL *newURL1Parent = [[newURL1 URLByDeletingLastPathComponent] URLByStandardizingPath];
    NSURL *sourceURLParent = [[sourceURL URLByDeletingLastPathComponent] URLByStandardizingPath];
    
    if (![newURL1Parent isEqual:sourceURLParent] || ![[newURL1 lastPathComponent] isEqual:[sourceURL lastPathComponent]]) {
        DEBUG_STORE(@"  bailing on move -- something else moved the file item to %@", newURL1);
        
        // Some other presenter has moved this.
        return _completeCoordinatedMoveItem(fileItem, nil/*destinationURL*/, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil], completionQueue, completionHandler);
    }
    return nil;
}

/*
 The passed in sourceURL should be the file item's fileURL captured on the main thread when the move was requested. If, by the time we get into the file coordinator this has changed (some other move operation beat us), we'll bail (our preconditions have failed).
 We expect that the fileItem will have already been told (on the main thread) that it is optimistically expecting to move to the given destinationURL via -_expectPresentedItemToMoveToURL:. In the case that we fail, we'll tell the file item that the move didn't work out.
 The passed in completionHandler must have already been copied because we are on the background queue here.
 */
static NSOperation *_coordinatedMoveItem(OFSDocumentStoreScope *self, OFSDocumentStoreFileItem *fileItem, NSURL *sourceURL, NSURL *destinationURL, NSOperationQueue *completionQueue, void (^completionHandler)(NSURL *destinationURL, NSError *errorOrNil))
{
    OBPRECONDITION(![NSThread isMainThread]); // We should be on the action queue
    OBPRECONDITION((completionQueue == nil) == (completionHandler == nil)); // both or neither
    OBPRECONDITION(fileItem.scope == self);
    
    DEBUG_STORE(@"Moving item %@ from %@ to %@", [fileItem shortDescription], sourceURL, destinationURL);
    
    // Make sure the completion handler has already been promoted to the heap. The caller should have done that before jumping to the _actionOperationQueue.
    OBASSERT((id)completionHandler == [completionHandler copy]);
    
    __block NSOperation *presenterNotificationBlock = nil;
    NSError *coordinatorError = nil;
    
#ifdef DEBUG_STORE_ENABLED
    for (id <NSFilePresenter> presenter in [NSFileCoordinator filePresenters]) {
        NSLog(@"  presenter %@ at %@", [(id)presenter shortDescription], presenter.presentedItemURL);
    }
#endif
    
    // Pass our file item so that it will not receive presenter notifications (we are in charge of sending those). Note we assume that the coordination request will block until all previously queued notifications for this presenter have finished. The definitely would if we passed nil since the 'relinquish' block would need to unblock the coordinator, but here we are telling coordinator to not ask us to relinquish...
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:fileItem];
    
    // Radar 10686553: Coordinated renaming to fix filename case provokes accomodate for deletion
    // If the two paths only differ based on case, we'll rename to a unique name first. Terrible.
    if ([[sourceURL path] localizedCaseInsensitiveCompare:[destinationURL path]] == NSOrderedSame) {
        OBFinishPortingLater("Deal with folders again somehow");
        //NSString *folderName = OFSFolderNameForFileURL(sourceURL);
        NSString *folderName = nil;
        
        NSString *fileName = [sourceURL lastPathComponent];
        NSString *baseName = nil;
        NSUInteger counter;
        [[fileName stringByDeletingPathExtension] splitName:&baseName andCounter:&counter];
        
        NSString *temporaryFileName = [self _availableFileNameInFolderNamed:folderName withBaseName:baseName extension:[fileName pathExtension] counter:&counter];
        NSURL *temporaryURL = _destinationURLForMove(sourceURL, [sourceURL URLByDeletingLastPathComponent], temporaryFileName);
        DEBUG_STORE(@"  doing temporary rename to avoid NSFileCoordinator bug %@ -> %@", sourceURL, temporaryURL);
        
        [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving
                               writingItemAtURL:temporaryURL options:NSFileCoordinatorWritingForReplacing
                                          error:&coordinatorError
                                     byAccessor:
         ^(NSURL *newURL1, NSURL *newURL2){
             if ((presenterNotificationBlock = _checkRenamePreconditions(fileItem, sourceURL, newURL1, completionQueue, completionHandler)))
                 return;
             
             NSFileManager *fileManager = [NSFileManager defaultManager];
             
             NSError *moveError = nil;
             if (![fileManager moveItemAtURL:newURL1 toURL:newURL2 error:&moveError]) {
                 NSLog(@"Error moving \"%@\" to \"%@\": %@", [newURL1 absoluteString], [newURL2 absoluteString], [moveError toPropertyList]);
                 presenterNotificationBlock = _completeCoordinatedMoveItem(fileItem, nil/*destinationURL*/, moveError, completionQueue, completionHandler);
                 return;
             }
             
             [coordinator itemAtURL:sourceURL didMoveToURL:temporaryURL];
         }];
        
        if (presenterNotificationBlock)
            return presenterNotificationBlock; // Something didn't work out already
        
        sourceURL = temporaryURL; // Head off to do the rename to the eventual location.
    }
    
    [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving
                           writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForReplacing
                                      error:&coordinatorError
                                 byAccessor:
     ^(NSURL *newURL1, NSURL *newURL2){
         DEBUG_STORE(@"  coordinator issued URLs to move from %@ to %@", newURL1, newURL2);
         
         if ((presenterNotificationBlock = _checkRenamePreconditions(fileItem, sourceURL, newURL1, completionQueue, completionHandler)))
             return;
         
         NSFileManager *fileManager = [NSFileManager defaultManager];
         
         NSError *moveError = nil;
         if (![fileManager moveItemAtURL:newURL1 toURL:newURL2 error:&moveError]) {
             NSLog(@"Error moving \"%@\" to \"%@\": %@", [newURL1 absoluteString], [newURL2 absoluteString], [moveError toPropertyList]);
             presenterNotificationBlock = _completeCoordinatedMoveItem(fileItem, nil/*destinationURL*/, moveError, completionQueue, completionHandler);
             return;
         }
         
         // Experimentally, we do need to call -itemAtURL:didMoveToURL:, even if we are specifying a move via our options AND if we get passed a presenter, we can't call it directly but need to post that on the presenter queue. Without this, we get various oddities if we have back to back coordinated move operations were the first passes a nil presenter (so notifications are queued -- this could happen if a sync is initiating a move) and the second passes a non-nil presenter (so there are no notifications queued). The -itemAtURL:didMoveToURL: call will cause the second coordination request to block at least until the queued -presentedItemDidMoveToURL: is invoked, but it will NOT wait for the 'reacquire' block to execute. But, at least all the messages seem to be enqueued, so doing an enqueued notification here means our update will appear after all the notifications from the first coordinator.
         [coordinator itemAtURL:sourceURL didMoveToURL:destinationURL];
         
         presenterNotificationBlock = _completeCoordinatedMoveItem(fileItem, destinationURL, nil/*error*/, completionQueue, completionHandler);
         
         NSError *attributesError = nil;
         NSDictionary *attributes = [fileManager attributesOfItemAtPath:[[newURL2 absoluteURL] path] error:&attributesError];
         if (!attributes) {
             // Hopefully non-fatal, but worrisome. We'll log it at least....
             NSLog(@"Error getting attributes of \"%@\": %@", [newURL2 absoluteString], [attributesError toPropertyList]);
         } else {
             NSUInteger mode = [attributes filePosixPermissions];
             if ((mode & S_IWUSR) == 0) {
                 mode |= S_IWUSR;
                 attributesError = nil;
                 if (![fileManager setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:mode] forKey:NSFilePosixPermissions] ofItemAtPath:[[newURL2 absoluteURL] path] error:&attributesError]) {
                     NSLog(@"Error setting attributes of \"%@\": %@", [newURL2 absoluteString], [attributesError toPropertyList]);
                 }
             }
         }
     }];
    
    if (!presenterNotificationBlock) {
        // We need to call _completeCoordinatedMoveItem(), otherwise the accessor would have.
        OBASSERT(coordinatorError);
        return _completeCoordinatedMoveItem(fileItem, nil/*destinationURL*/, coordinatorError/*error*/, completionQueue, completionHandler);
    } else {
        return presenterNotificationBlock;
    }
}

- (void)renameFileItem:(OFSDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionQueue:(NSOperationQueue *)completionQueue handler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION((completionQueue == nil) == (completionHandler == nil));
    OBPRECONDITION(fileItem.scope == self); // Can't use this method to move between scopes
    
    // capture scope
    completionHandler = [completionHandler copy];
    
    /*
     From NSFileCoordinator.h, "For another example, the most accurate and safe way to coordinate a move is to invoke -coordinateWritingItemAtURL:options:writingItemAtURL:options:error:byAccessor: using the NSFileCoordinatorWritingForMoving option with the source URL and NSFileCoordinatorWritingForReplacing with the destination URL."
     */
    
    // The document should already live in the local documents directory, a sync container documents directory or a folder there under. Keep it in whichever one it was in.
    NSURL *containingDirectoryURL = [fileItem.fileURL URLByDeletingLastPathComponent];
    OBASSERT(containingDirectoryURL);
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // scanItemsWithCompletionHandler: now ignores the 'Inbox' so we should never get into this situation.
    OBASSERT(!OFSInInInbox(containingDirectoryURL));
#endif
    
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)fileType, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *destinationFileName = [baseName stringByAppendingPathExtension:(__bridge NSString *)extension];
    CFRelease(extension);
    
    NSURL *sourceURL = fileItem.fileURL;
    NSURL *destinationURL = _destinationURLForMove(sourceURL, containingDirectoryURL, destinationFileName);
    
    OBFinishPortingLater("Deal with folders somehow again");
    //NSString *sourceFolderName = OFSFolderNameForFileURL(sourceURL);
    NSString *sourceFolderName = nil;
    
    [self performAsynchronousFileAccessUsingBlock:^{
        // Check if there is a file item with this name. Ignore the source URL so that the user can make capitalization/accent corrections in file names w/o getting a self-conflict.
        NSSet *usedFileNames = [self copyCurrentlyUsedFileNamesInFolderNamed:sourceFolderName ignoringFileURL:sourceURL];
        for (NSString *usedFileName in usedFileNames) {
            if ([usedFileName localizedCaseInsensitiveCompare:destinationFileName] == NSOrderedSame) {
                if (completionHandler) {
                    [completionQueue addOperationWithBlock:^{
                        __autoreleasing NSError *error = nil;
                        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"\"%@\" is already taken.", @"OmniFileStore", OMNI_BUNDLE, @"Error description when renaming a file to a name that is already in use."), baseName];
                        NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please choose a different name.", @"OmniFileStore", OMNI_BUNDLE, @"Error suggestion when renaming a file to a name that is already in use.");
                        OFSError(&error, OFSFilenameAlreadyInUse, description, suggestion);
                        completionHandler(nil, error);
                    }];
                }
                return;
            }
        }
        
        _coordinatedMoveItem(self, fileItem, sourceURL, destinationURL, completionQueue, completionHandler);
    }];
}

- (void)deleteItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(fileItem.scope == self);
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with updating of fileItems, and this is the queue we'll invoke the completion handler on.
    
    // capture scope (might not be necessary since we aren't currently asynchronous here).
    completionHandler = [completionHandler copy];
    
    [_actionOperationQueue addOperationWithBlock:^{
        // Passing nil for the presenter so that the file item gets its normal deletion accommodation request (it should then send us -_fileItemHasAccommodatedDeletion:).
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        NSError *error = nil;
        __block BOOL success = NO;
        __block NSError *innerError = nil;
        
        [coordinator coordinateWritingItemAtURL:fileItem.fileURL options:NSFileCoordinatorWritingForDeleting error:&error byAccessor:^(NSURL *newURL){
            DEBUG_STORE(@"  coordinator issued URL to delete %@", newURL);
            
            NSError *deleteError = nil;
            if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&deleteError]) {
                NSLog(@"Error deleting %@: %@", [newURL absoluteString], [deleteError toPropertyList]);
                innerError = deleteError;
                return;
            }
            
            // Recommended calling convention for this API (since it returns void) is to set a __block variable to success...
            success = YES;
        }];
        
        
        if (!success) {
            OBASSERT(error || innerError);
            if (innerError)
                error = innerError;
        } else
            error = nil;
        
        if (completionHandler) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (error)
                    completionHandler(error);
                else
                    completionHandler(innerError);
            }];
        }
    }];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

// Migrates all the existing documents in one scope to another (either by copying or moving), preserving their folder structure.
- (void)migrateDocumentsFromScope:(OFSDocumentStoreScope *)sourceScope byMoving:(BOOL)shouldMove completionHandler:(void (^)(NSDictionary *migratedURLs, NSDictionary *errorURLs))completionHandler;
{
    OBFinishPorting;
#if 0
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(sourceScope);
    OBPRECONDITION(sourceScope != self);
    
    // Make sure we know what we are moving to/from
    OBPRECONDITION(self.hasFinishedInitialScan);
    OBPRECONDITION(sourceScope.hasFinishedInitialScan);
    
    completionHandler = [completionHandler copy];
    
    NSURL *sourceDocumentsURL = [sourceScope documentsURL:NULL];
    NSURL *destinationDocumentsURL = [self documentsURL:NULL];
    OBASSERT(sourceDocumentsURL);
    OBASSERT(destinationDocumentsURL);
    
    [self performAsynchronousFileAccessUsingBlock:^{
        DEBUG_STORE(@"Migrating documents from %@ to %@ by %@", sourceDocumentsURL, destinationDocumentsURL, shouldMove ? @"moving" : @"copying");
        
        NSMutableDictionary *migratedURLs = [NSMutableDictionary dictionary]; // sourceURL -> destURL
        NSMutableDictionary *errorURLs = [NSMutableDictionary dictionary]; // sourceURL -> error
        
        // Gather the names to avoid (only from the destination).
        NSMutableDictionary *usedFileNamesByFolder = [self copyCurrentlyUsedFileNamesByFolderName];
        DEBUG_STORE(@"  usedFileNamesByFolder = %@", usedFileNamesByFolder);
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // TODO: Can we better serialize with the source scope? Here we are reading some (recent) historical notion of the items it has. Maybe it is better to serialize with the source than the destination so we can be sure to get recent edits?
        for (OFSDocumentStoreFileItem *sourceFileItem in sourceScope.fileItems) {
            NSURL *sourceURL = sourceFileItem.fileURL;
            
            // The higher level code prompts the user (obviously a race condition between the two, but unlikely).
            NSError *error = nil;
            if (![sourceScope prepareToMoveFileItem:sourceFileItem toScope:self error:&error]) {
                [errorURLs setObject:error forKey:sourceURL];
                continue;
            }
            
            NSString *sourceFolderName = OFSFolderNameForFileURL(sourceURL);
            NSMutableSet *usedFileNames = usedFileNamesByFolder[sourceFolderName];
            
            NSString *sourceFileName = [sourceURL lastPathComponent];
            NSUInteger counter = 0;
            NSString *destinationName = OFSDocumentStoreScopeFindAvailableName(usedFileNames, [sourceFileName stringByDeletingPathExtension], [sourceFileName pathExtension], &counter);
            
            NSURL *destinationURL = destinationDocumentsURL;
            if (![NSString isEmptyString:sourceFolderName])
                destinationURL = [destinationURL URLByAppendingPathComponent:sourceFolderName];
            destinationURL = [destinationURL URLByAppendingPathComponent:destinationName];
            
            __block BOOL migrateSuccess = NO;
            __block NSError *migrateError = nil;
            
            __block NSDate *sourceDate = nil;
            __block NSDate *destinationDate = nil;
            
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            
            // NOTE: File previews use the on-disk date, not the metadata date, so we can't ask sourceFileItem for its -date.
            if (shouldMove) {
                [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving
                                       writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForReplacing error:&migrateError byAccessor:
                 ^(NSURL *newURL1, NSURL *newURL2){
                     migrateSuccess = [fileManager moveItemAtURL:newURL1 toURL:newURL2 error:&migrateError];
                     
                     sourceDate = OFSDocumentStoreScopeModificationDateForFileURL(fileManager, newURL2);
                     destinationDate = sourceDate;
                 }];
            } else {
                [coordinator coordinateReadingItemAtURL:sourceURL options:0
                                       writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForReplacing error:&migrateError byAccessor:
                 ^(NSURL *newURL1, NSURL *newURL2){
                     migrateSuccess = [fileManager copyItemAtURL:newURL1 toURL:newURL2 error:&migrateError];
                     
                     sourceDate = OFSDocumentStoreScopeModificationDateForFileURL(fileManager, newURL1);
                     destinationDate = OFSDocumentStoreScopeModificationDateForFileURL(fileManager, newURL2);
                 }];
            }
            
            if (!migrateSuccess) {
                [errorURLs setObject:migrateError forKey:sourceURL];
                DEBUG_STORE(@"  error moving %@: %@", sourceURL, [migrateError toPropertyList]);
            } else {
                OBFinishPortingLater("If we don't reuse file items, should we send this up call on move or not?");
                
                if (!shouldMove) { // The file item hears about moves via NSFilePresenter and tells us
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [self _fileWithURL:sourceURL andDate:sourceDate didCopyToURL:destinationURL andDate:destinationDate];
                    }];
                }
                
                [migratedURLs setObject:destinationURL forKey:sourceURL];
                DEBUG_STORE(@"  migrated %@ to %@", sourceURL, destinationURL);
                
                // Now we need to avoid this file name.
                [usedFileNames addObject:[destinationURL lastPathComponent]];
            }
        }
        
        if (completionHandler) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionHandler(migratedURLs, errorURLs);
            }];
        }
    }];
#endif
}
#endif

- (BOOL)prepareToMoveFileItem:(OFSDocumentStoreFileItem *)fileItem toScope:(OFSDocumentStoreScope *)otherScope error:(NSError **)outError;
{
    return YES;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

#pragma mark - Internal

- (NSMutableSet *)_copyCurrentlyUsedFileNamesInFolderNamed:(NSString *)folderName;
{
    return [self copyCurrentlyUsedFileNamesInFolderNamed:folderName ignoringFileURL:nil];
}

- (void)fileItemFinishedDownloading:(OFSDocumentStoreFileItem *)fileItem;
{
    OFSDocumentStore *documentStore = self.documentStore;
    if (!documentStore)
        return; // Weak pointer cleared
    
    // The file type and modification date stored in this file item may not have changed (since undownloaded file items know those). So, -_queueContentsChanged may end up posting no notification. Rather than forcing it to do so in this case, we have a specific notification for a download finishing.
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fileItem forKey:OFSDocumentStoreFileItemInfoKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:OFSDocumentStoreFileItemFinishedDownloadingNotification object:documentStore userInfo:userInfo];
}

- (void)invalidateUnusedFileItems:(NSDictionary *)cacheKeyToFileItem;
{
    [cacheKeyToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *cacheKey, OFSDocumentStoreFileItem *fileItem, BOOL *stop) {
        [fileItem _invalidate];
    }];
}

- (void)_fileItemHasAccommodatedDeletion:(OFSDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(![NSThread isMainThread]); // This gets called from the file presenter queue for the item.
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        OBASSERT([_fileItems member:fileItem] == fileItem); // If this fails, note the circumstances here...
        
        [[self mutableSetValueForKey:OFValidateKeyPath(self, fileItems)] removeObject:fileItem];
        
        // We don't expect that the item is in a writer block, but just in case...
        [fileItem _invalidateAfterWriter];
    }];
}

- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
{
    [self.documentStore _fileWithURL:oldURL andDate:date didMoveToURL:newURL];
}

- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;
{
    [self.documentStore _fileWithURL:oldURL andDate:date didCopyToURL:newURL andDate:newDate];
}

- (void)_fileItemContentsChanged:(OFSDocumentStoreFileItem *)fileItem;
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fileItem forKey:OFSDocumentStoreFileItemInfoKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:OFSDocumentStoreFileItemContentsChangedNotification object:self.documentStore userInfo:userInfo];
}

- (void)updateFileItem:(OFSDocumentStoreFileItem *)fileItem withMetadata:(id)metadata modificationDate:(NSDate *)modificationDate;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSMutableDictionary *)copyCurrentlyUsedFileNamesByFolderName; // NSMutableDictionary of folder name -> set of names, "" for the top-level folder
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderNamed:(NSString *)folderName ignoringFileURL:(NSURL *)fileURLToIgnore;
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

// We CANNOT check for file non-existence here. Cloud documents may be present on the server and we may only know about them via a metadata item that produced an OFSDocumentStoreFileItem. So, we take in an array of URLs and unique against that.
NSString *OFSDocumentStoreScopeFindAvailableName(NSSet *usedFileNames, NSString *baseName, NSString *extension, NSUInteger *ioCounter)
{
    NSUInteger counter = *ioCounter; // starting counter
    
    while (YES) {
        NSString *candidateName;
        if (counter == 0) {
            candidateName = [[NSString alloc] initWithFormat:@"%@.%@", baseName, extension];
            counter = 2; // First duplicate should be "Foo 2".
        } else {
            candidateName = [[NSString alloc] initWithFormat:@"%@ %lu.%@", baseName, counter, extension];
            counter++;
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

NSDate *OFSDocumentStoreScopeModificationDateForFileURL(NSFileManager *fileManager, NSURL *fileURL)
{
    NSError *attributesError = nil;
    NSDate *modificationDate = nil;
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:[fileURL path]  error:&attributesError];
    if (!attributes)
        NSLog(@"Error getting attributes for %@ -- %@", [fileURL absoluteString], [attributesError toPropertyList]);
    else
        modificationDate = [attributes fileModificationDate];
    if (!modificationDate)
        modificationDate = [NSDate date]; // Default to now if we can't get the attributes or they are bogus for some reason.
    
    return modificationDate;
}

- (NSString *)_availableFileNameAvoidingUsedFileNames:(NSSet *)usedFilenames withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    OBPRECONDITION(_fileItems); // Make sure we've done a local scan. It might be out of date, so maybe we should scan here too.
    OBPRECONDITION(self.hasFinishedInitialScan); // We can't unique against other files until we know what is there
    
    return OFSDocumentStoreScopeFindAvailableName(usedFilenames, baseName, extension, ioCounter);
}

- (NSString *)_availableFileNameInFolderNamed:(NSString *)folderName withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    NSSet *usedFileNames = [self _copyCurrentlyUsedFileNamesInFolderNamed:folderName];
    NSString *fileName = [self _availableFileNameAvoidingUsedFileNames:usedFileNames withBaseName:baseName extension:extension counter:ioCounter];
    return fileName;
}

- (NSURL *)_availableURLInFolderNamed:(NSString *)folderName withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    OBFinishPortingLater("Propagate error");
    
    NSURL *documentsURL = [self documentsURL:NULL];
    NSURL *folderURL = documentsURL;
    if (![NSString isEmptyString:folderName]) {
        OBFinishPorting;
#if 0
        folderURL = [folderURL URLByAppendingPathComponent:folderName];
        OBASSERT(OFSIsFolder(folderURL));
#endif
    }
    
    NSString *availableFileName = [self _availableFileNameInFolderNamed:folderName withBaseName:baseName extension:extension counter:ioCounter];
    return [folderURL URLByAppendingPathComponent:availableFileName];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSURL *)_availableURLWithFileName:(NSString *)fileName;
{
    OBFinishPorting;
#if 0
    NSString *originalName = [fileName stringByDeletingPathExtension];
    NSString *extension = [fileName pathExtension];
    
    // If the file item name ends in a number, we are likely duplicating a duplicate.  Take that as our starting counter.  Of course, this means that if we duplicate "Revenue 2010", we'll get "Revenue 2011". But, w/o this we'll get "Revenue 2010 2", "Revenue 2010 2 2", etc.
    NSString *baseName = nil;
    NSUInteger counter;
    [originalName splitName:&baseName andCounter:&counter];
    
    return [self _availableURLWithBaseName:baseName extension:extension counter:&counter];
#endif
}
#endif

- (NSURL *)_urlForFolderName:(NSString *)folderName fileName:(NSString *)fileName error:(NSError **)outError;
{
    OBPRECONDITION(fileName);
    
    NSURL *url = [self documentsURL:outError];
    if (!url)
        return nil;
    
    if (folderName)
        url = [url URLByAppendingPathComponent:folderName];
    
    return [url URLByAppendingPathComponent:fileName];
}

- (void)_updateTopLevelItems;
{
    NSMutableSet *topLevelItems = [[NSMutableSet alloc] init];
    NSMutableDictionary *itemsByGroupName = [[NSMutableDictionary alloc] init];
    
    OBFinishPortingLater("Decide how to group things into folders on iOS when they are in a synchronized directory");
    for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
#if 0
        NSURL *containerURL = [fileItem.fileURL URLByDeletingLastPathComponent];
        if (OFSIsFolder(containerURL)) {
            NSString *groupName = [containerURL lastPathComponent];
            
            NSMutableSet *itemsInGroup = [itemsByGroupName objectForKey:groupName];
            if (!itemsInGroup) {
                itemsInGroup = [[NSMutableSet alloc] init];
                [itemsByGroupName setObject:itemsInGroup forKey:groupName];
            }
            [itemsInGroup addObject:fileItem];
        } else
#endif
        {
            [topLevelItems addObject:fileItem];
        }
    }
    
    // Build/update groups, now that we know the final set of items in each
    NSMutableDictionary *groupByName = [NSMutableDictionary dictionary];
    for (NSString *groupName in itemsByGroupName) {
        OFSDocumentStoreGroupItem *groupItem = [_groupItemByName objectForKey:groupName];
        if (!groupItem) {
            groupItem = [[OFSDocumentStoreGroupItem alloc] initWithScope:self];
            groupItem.name = groupName;
        }
        
        [groupByName setObject:groupItem forKey:groupName];
        groupItem.fileItems = [itemsByGroupName objectForKey:groupName];
        
        [topLevelItems addObject:groupItem];
    }
    
    // Invalidate the any groups that we no longer need
    for (NSString *groupName in _groupItemByName) {
        if ([groupByName objectForKey:groupName] == nil) {
            OFSDocumentStoreGroupItem *groupItem = [_groupItemByName objectForKey:groupName];
            DEBUG_STORE(@"Group \"%@\" no longer needed, invalidating %@", groupName, [groupItem shortDescription]);
            [groupItem _invalidate];
        }
    }
    
    _groupItemByName = [groupByName copy];
    DEBUG_STORE(@"Scanned groups %@", _groupItemByName);
    DEBUG_STORE(@"Scanned top level items %@", [[_topLevelItems allObjects] arrayByPerformingSelector:@selector(shortDescription)]);
    
    if (OFNOTEQUAL(_topLevelItems, topLevelItems)) {
        [self willChangeValueForKey:OFValidateKeyPath(self, topLevelItems)];
        _topLevelItems = [[NSSet alloc] initWithSet:topLevelItems];
        [self didChangeValueForKey:OFValidateKeyPath(self, topLevelItems)];
    }
}

@end
