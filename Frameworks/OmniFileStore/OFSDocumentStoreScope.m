// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentSToreScope-Subclass.h>

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/NSURL-OFExtensions.h>

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

OBDEPRECATED_METHOD(-urlForNewDocumentInFolderNamed:baseName:fileType:); // folderURL
OBDEPRECATED_METHOD(-addDocumentInFolderNamed:baseName:fromURL:option:completionHandler:); // folderURL
OBDEPRECATED_METHOD(-copyCurrentlyUsedFileNamesInFolderNamed:ignoringFileURL:); // folderURL

@interface OFSDocumentStoreScope ()
// Forward declarations for C functions
- (NSString *)_availableFileNameInFolderAtURL:(NSURL *)folderURL withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
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
    return OFURLContainsURL(containerURL, fileURL);
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
    _actionOperationQueue.name = [NSString stringWithFormat:@"com.omnigroup.frameworks.OmniFileStore.actions for <%@:%p>", NSStringFromClass([self class]), self];
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
    return [[self class] isFile:fileURL inContainer:self.documentsURL];
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

static NSString *_makeCanonicalPath(NSString *path)
{
    // We don't want to resolve symlinks in the last path component, or we can't tell symlinks apart from the things they point at
    NSString *canonicalParentPath = [[[path stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath] stringByStandardizingPath];
    return [canonicalParentPath stringByAppendingPathComponent:[path lastPathComponent]];
}

- (OFSDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after our first scan is done
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with changes to the fileItems property
    
    if (url == nil || ![url isFileURL])
        return nil;
    
    NSString *standardizedPathForURL = _makeCanonicalPath([url path]);
    OBASSERT(standardizedPathForURL != nil);
    for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
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

- (OFSDocumentStoreFileItem *)makeFileItemForURL:(NSURL *)fileURL isDirectory:(BOOL)isDirectory fileModificationDate:(NSDate *)fileModificationDate userModificationDate:(NSDate *)userModificationDate;
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
        if (otherFileItem.scope != self)
            continue; // cache keys aren't comparable across scopes
        
        OBFinishPortingLater("move this to subclasses ... OFX scope doesn't care about cache key goop. Can also relax the restriction that document directories end in Documents for OFX");
        OBASSERT(OFNOTEQUAL(OFSDocumentStoreScopeCacheKeyForURL(otherFileItem.fileURL), OFSDocumentStoreScopeCacheKeyForURL(fileURL)));
    }
#endif
    
    OFSDocumentStoreFileItem *fileItem = [[fileItemClass alloc] initWithScope:self fileURL:fileURL isDirectory:isDirectory fileModificationDate:fileModificationDate userModificationDate:userModificationDate];
    
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
        __autoreleasing NSDate *fileModificationDate = nil;
        if (![createdURL getResourceValue:&fileModificationDate forKey:NSURLContentModificationDateKey error:NULL]) {
            OBASSERT_NOT_REACHED("We just created it...");
        }
        
        __autoreleasing NSNumber *isDirectory = nil;
        __autoreleasing NSError *resourceError = nil;
        if (![createdURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError])
            NSLog(@"Error getting directory key for %@: %@", createdURL, [resourceError toPropertyList]);

        // The delegate is in charge of making sure that the file will sort to the top if the UI is sorting files by date. If it just copies a template, then it may need to call -[NSFileManager touchItemAtURL:error:]
        OBASSERT(fileModificationDate);
        OBASSERT([fileModificationDate timeIntervalSinceNow] < 0.5);
        
        // If we are replacing an existing document, there may already be a file item (but it is probably marked for deletion). But we also want to be careful that if there was a scan completed and repopulated _fileItems that *did* capture this URL, we don't want make a new file item for the same URL.
        OFSDocumentStoreFileItem *addedFileItem = nil;
        
        fileItem = [self fileItemWithURL:createdURL];
        
        if (fileItem)
            fileItem.fileModificationDate = fileModificationDate;
        else {
            // This function is called for newly created items, so our content modification date is the same as the file system modification time (or close enough).
            NSDate *userModificationDate = fileModificationDate;
            
            addedFileItem = [self makeFileItemForURL:createdURL isDirectory:[isDirectory boolValue] fileModificationDate:fileModificationDate userModificationDate:userModificationDate];
            if (!addedFileItem) {
                OBASSERT_NOT_REACHED("Some error in the delegate where we created a file of a type we don't display?");
            } else {
                fileItem = addedFileItem;
            
                // Start out with the right state when duplicating an item and otherwise set default metadata.
                [self updateFileItem:fileItem withMetadata:nil fileModificationDate:fileModificationDate];
            }
        }
        
        if (addedFileItem) {
            OBASSERT([self.fileItems member:addedFileItem] == nil);
                        
            [[self mutableSetValueForKey:OFValidateKeyPath(self, fileItems)] addObject:addedFileItem];
        }
    }
    
    if (handler)
        handler(fileItem, error);
}

- (NSURL *)urlForNewDocumentInFolderAtURL:(NSURL *)folderURL baseName:(NSString *)baseName fileType:(NSString *)documentUTI;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _actionOperationQueue);
    
    OBPRECONDITION(documentUTI);
        
    NSString *extension = CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)documentUTI, kUTTagClassFilenameExtension));
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    BOOL isPackage = UTTypeConformsTo((__bridge CFStringRef)documentUTI, kUTTypePackage);
    OBASSERT_IF(!isPackage, !UTTypeConformsTo((__bridge CFStringRef)documentUTI, kUTTypeFolder), "Types should be declared as conforming to kUTTypePackage, not kUTTypeFolder");
    
    NSUInteger counter = 0;
    
    NSURL *documentsURL = self.documentsURL;
    if (folderURL) {
        OBASSERT(OFURLContainsURL(documentsURL, folderURL));
    } else
        folderURL = documentsURL;
        
    OBFinishPortingLater("Propagate error");
    
    NSString *availableFileName = [self _availableFileNameInFolderAtURL:folderURL withBaseName:baseName extension:extension counter:&counter];
    
    return [folderURL URLByAppendingPathComponent:availableFileName isDirectory:isPackage];
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
        
        __autoreleasing NSError *error = nil;
        [coordinator coordinateReadingItemAtURL:fromURL options:0
                               writingItemAtURL:temporaryURL options:NSFileCoordinatorWritingForReplacing
                                          error:&error byAccessor:
         ^(NSURL *newReadingURL, NSURL *newWritingURL) {
             __autoreleasing NSError *copyError = nil;
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
    __autoreleasing NSError *error = nil;
    
    [coordinator coordinateReadingItemAtURL:fromURL options:0
                           writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing
                                      error:&error byAccessor:
     ^(NSURL *newReadingURL, NSURL *newWritingURL) {
         NSFileManager *manager = [NSFileManager defaultManager];
         
         if (isReplacing) {
             __autoreleasing NSError *removeError = nil;
             if (![manager removeItemAtURL:newWritingURL error:&removeError]) {
                 if (![removeError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) {
                     innerError = removeError;
                     NSLog(@"Error removing %@: %@", toURL, [removeError toPropertyList]);
                     return;
                 }
             }
         }
         
         __autoreleasing NSError *moveError = nil;
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

- (void)addDocumentInFolderAtURL:(NSURL *)folderURL fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    [self addDocumentInFolderAtURL:folderURL baseName:nil fromURL:fromURL option:option completionHandler:completionHandler];
}

// Enqueues an operationon the scope's background serial action queue. The completion handler will be called with the resulting file item, nil file item and an error.
- (void)addDocumentInFolderAtURL:(NSURL *)folderURL baseName:(NSString *)baseName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
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
    
    // fromURL should exist, so we can ask if it is a directory.
    __autoreleasing NSError *attributError;
    BOOL isDirectory;
    if (!OFSGetBoolResourceValue(fromURL, NSURLIsDirectoryKey, &isDirectory, &attributError)) {
        // OFSGetBoolResourceValue already logs
        isDirectory = [[fromURL absoluteString] hasSuffix:@"/"];
    }
    
    // We cannot decide on the destination URL w/o synchronizing with the action queue. In particular, if you try to duplicate "A" and "A 2", both operations could pick "A 3".
    [self performAsynchronousFileAccessUsingBlock:^{
        NSURL *toURL = nil;
        NSString *toFileName = (baseName) ? [baseName stringByAppendingPathExtension:[[fromURL lastPathComponent] pathExtension]] : [fromURL lastPathComponent];
        BOOL isReplacing = NO;
        
        if (option == OFSDocumentStoreAddNormally) {
            // Use the given file name.
            __autoreleasing NSError *urlError = nil;
            toURL = [self _urlForFolderAtURL:folderURL fileName:toFileName isDirectory:isDirectory error:&urlError];
            if (!toURL) {
                callCompletaionHandlerOnMainQueue(nil, urlError);
                return;
            }
        }
        else if (option == OFSDocumentStoreAddByRenaming) {
            // Generate a new file name.
            __autoreleasing NSString *toBaseName = nil;
            NSUInteger counter;
            [[toFileName stringByDeletingPathExtension] splitName:&toBaseName andCounter:&counter];
            
            toFileName = [self _availableFileNameInFolderAtURL:folderURL withBaseName:toBaseName extension:[toFileName pathExtension] counter:&counter];
            
            __autoreleasing NSError *urlError = nil;
            toURL = [self _urlForFolderAtURL:folderURL fileName:toFileName isDirectory:isDirectory error:&urlError];
            if (!toURL) {
                callCompletaionHandlerOnMainQueue(nil, urlError);
                return;
            }
        }
        else if (option == OFSDocumentStoreAddByReplacing) {
            // Use the given file name, but ensure that it does not exist in the documents directory.
            __autoreleasing NSError *urlError = nil;
            toURL = [self _urlForFolderAtURL:folderURL fileName:toFileName isDirectory:isDirectory error:&urlError];
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
        __autoreleasing NSError *addError = nil;
        BOOL success = _performAdd(self, fromURL, toURL, isReplacing, &addError);
        
        NSError *strongError = success ? nil : addError;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (success)
                _addItemAndNotifyHandler(self, completionHandler, toURL, nil);
            else
                _addItemAndNotifyHandler(self, completionHandler, nil, strongError);
        }];
    }];
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

- (void)renameFileItem:(OFSDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(fileItem.scope == self); // Can't use this method to move between scopes
    
    completionHandler = [completionHandler copy];
    
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
    
    NSURL *sourceFolderURL = [sourceURL URLByDeletingLastPathComponent];
    
    // TODO: This is ugly. In the case of a move, at least, we want to pass the file presenter that would hear about the move so that it will not get notifications. We do this since we have to handle the notifications ourselves anyway (since sometimes they don't get sent -- for case-only renames, for example). OFSDocumentStoreLocalDirectoryScope conforms, but OFXDocumentStoreScope does not, leaving OFXAccountAgent to deal with NSFilePresenter.
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
                    NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"\"%@\" is already taken.", @"OmniFileStore", OMNI_BUNDLE, @"Error description when renaming a file to a name that is already in use."), baseName];
                    NSString *suggestion = NSLocalizedStringFromTableInBundle(@"Please choose a different name.", @"OmniFileStore", OMNI_BUNDLE, @"Error suggestion when renaming a file to a name that is already in use.");
                    OFSError(&error, OFSFilenameAlreadyInUse, description, suggestion);
                    completionHandler(nil, error);
                }
                return;
            }
        }
        
        [self performMoveFromURL:sourceURL toURL:destinationURL filePresenter:filePresenter completionHandler:^(NSURL *finalDestinationURL, NSError *errorOrNil){
            OBASSERT([self isRunningOnActionQueue]);
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                // Make sure our file item knows it got moved w/o waiting for file presenter notifications so that the document picker's lookups can find the right file item for animations. This means that when doing coordinated file moves, we should try to avoid getting notified by passing a file presenter to the coordinator (either the OFXAccountAgent, or the OFSDocumentStoreLocalDirectoryScope).
                if (finalDestinationURL) {
                    [self completedMoveOfFileItem:fileItem toURL:finalDestinationURL];
                    if (completionHandler)
                        completionHandler(finalDestinationURL, nil);
                } else {
                    NSLog(@"Error renaming %@: %@", [fileItem shortDescription], [errorOrNil toPropertyList]);
                    if (completionHandler)
                        completionHandler(nil, errorOrNil);
                }
            }];
        }];
    }];
}


#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

// Move items that are in a different scope into this scope.
- (void)moveFileItems:(NSSet *)fileItems completionHandler:(void (^)(OFSDocumentStoreFileItem *failingFileItem, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // since we'll send the completion handler back to the main thread, make sure we came from there

    completionHandler = [completionHandler copy];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        OBFinishPortingLater("Deal with folder structure when moving documents between scopes");
        NSMutableSet *usedFilenames = [self _copyCurrentlyUsedFileNamesInFolderAtURL:nil];
        
        OFSDocumentStoreFileItem *failingFileItem;
        __autoreleasing NSError *error;
        for (OFSDocumentStoreFileItem *fileItem in fileItems) {
            OBASSERT(fileItem.scope != self);
            
            error = nil;
            NSURL *newURL = [self _moveURL:fileItem.fileURL avoidingFileNames:usedFilenames usingCoordinator:YES error:&error];
            if (!newURL) {
                failingFileItem = fileItem;
                break;
            }
            
            [usedFilenames addObject:[newURL lastPathComponent]];
        }
        
        if (completionHandler) {
            NSError *strongError = error;
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionHandler(failingFileItem, strongError);
            }];
        }
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
        [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForMerging error:outError byAccessor:^(NSURL *newURL1, NSURL *newURL2) {

            DEBUG_STORE(@"Moving document: %@ -> %@ (scope %@)", sourceURL, destinationURL, scope);
            // The documentation also says that this method does a coordinated move, so we don't need to (and in fact, experimentally, if we try we deadlock).
            success = [[NSFileManager defaultManager] moveItemAtURL:sourceURL toURL:destinationURL error:outError];
        }];
    } else {
        DEBUG_STORE(@"Moving document (without extra coordination): %@ -> %@ (scope %@)", sourceURL, destinationURL, scope);
        success = [[NSFileManager defaultManager] moveItemAtURL:sourceURL toURL:destinationURL error:outError];
    }
    
    if (!success)
        return nil;
    return destinationURL;
}

- (BOOL)isTrash;
{
    return NO;
}

static OFSDocumentStoreScope *_trashScope = nil;

+ (OFSDocumentStoreScope *)trashScope;
{
    return _trashScope;
}

+ (void)setTrashScope:(OFSDocumentStoreScope *)trashScope;
{
    assert(_trashScope == nil); // We shouldn't have more than one trash in an iOS app
    _trashScope = trashScope;
    OBPRECONDITION(_trashScope == nil || [_trashScope isTrash]); // The trash scope should know it's the trash
}

#endif

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
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // On iOS, we have to handle our own trash

    OFSDocumentStoreScope *trashScope = [self trashScope];

#define REQUIRE_TRASH 1
#if REQUIRE_TRASH
    // Let's require the trash so we don't unrecoverably delete things we mean to recoverably delete
    assert(trashScope != nil);
#else
    // If we don't require the trash and don't have one, just delete the file
    if (trashScope == nil) {
        if (outResultingURL != NULL)
            *outResultingURL = nil;
        return [[NSFileManager defaultManager] atomicallyRemoveItemAtURL:newURL2 error:outError];
    }
#endif

    __block BOOL success = NO;
    [trashScope _performSynchronousFileAccessUsingBlock:^{
        NSMutableSet *usedFilenames = [trashScope _copyCurrentlyUsedFileNamesInFolderAtURL:nil];
        NSURL *newURL = [trashScope _moveURL:url avoidingFileNames:usedFilenames usingCoordinator:NO error:outError];
        if (outResultingURL != NULL)
            *outResultingURL = newURL;
        success = newURL != nil;
    }];

    return success;
#else

    // On Mac, we can use the system trash
    return [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:outResultingURL error:outError];

#endif
}

- (BOOL)prepareToMoveFileItem:(OFSDocumentStoreFileItem *)fileItem toScope:(OFSDocumentStoreScope *)otherScope error:(NSError **)outError;
{
    return YES;
}

- (NSComparisonResult)compareDocumentScope:(OFSDocumentStoreScope *)otherScope;
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
    [cacheKeyToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *fileIdentifier, OFSDocumentStoreFileItem *fileItem, BOOL *stop) {
        [fileItem _invalidate];
    }];
}

/*
 The passed in sourceURL should be the file item's fileURL captured on the main thread when the move was requested. If, by the time we get into the file coordinator this has changed (some other move operation beat us), we'll bail (our preconditions have failed).
 We expect that the fileItem will have already been told (on the main thread) that it is optimistically expecting to move to the given destinationURL via -_expectPresentedItemToMoveToURL:. In the case that we fail, we'll tell the file item that the move didn't work out.
 The passed in completionHandler must have already been copied because we are on the background queue here.
 */
- (void)performMoveFromURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL filePresenter:(id <NSFilePresenter>)filePresenter completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION(![NSThread isMainThread]); // We should be on the action queue
    OBPRECONDITION([self isFileInContainer:sourceURL]);
    
    DEBUG_STORE(@"Perform move from %@ to %@", sourceURL, destinationURL);
    
    completionHandler = [completionHandler copy];
    
    __autoreleasing NSError *coordinatorError = nil;
    
#ifdef DEBUG_STORE_ENABLED
    for (id <NSFilePresenter> presenter in [NSFileCoordinator filePresenters]) {
        NSLog(@"  presenter %@ at %@", [(id)presenter shortDescription], presenter.presentedItemURL);
    }
#endif
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:filePresenter];
    
    // TODO: Move permissing-fixing code below to the inbox handling code in OmniUI.
    if (![coordinator moveItemAtURL:sourceURL toURL:destinationURL createIntermediateDirectories:YES error:&coordinatorError]) {
        if (completionHandler)
            completionHandler(nil, coordinatorError);
    } else {
        if (completionHandler)
            completionHandler(destinationURL, nil);
    }
}

- (void)completedMoveOfFileItem:(OFSDocumentStoreFileItem *)fileItem toURL:(NSURL *)destinationURL;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    OBFinishPortingLater("Maybe combine this with -fileWithURL:andDate:didMoveToURL:");
    [fileItem didMoveToURL:destinationURL];
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

- (void)updateFileItem:(OFSDocumentStoreFileItem *)fileItem withMetadata:(id)metadata fileModificationDate:(NSDate *)fileModificationDate;
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
    __autoreleasing NSError *attributesError = nil;
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

- (NSString *)_availableFileNameInFolderAtURL:(NSURL *)folderURL withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    NSSet *usedFileNames = [self _copyCurrentlyUsedFileNamesInFolderAtURL:folderURL];
    NSString *fileName = [self _availableFileNameAvoidingUsedFileNames:usedFileNames withBaseName:baseName extension:extension counter:ioCounter];
    return fileName;
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
