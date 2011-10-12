// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentStore.h>

#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniUI/OUIDocumentStoreDelegate.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/OUIDocumentStoreGroupItem.h>

#import "OUIDocumentStore-Internal.h"
#import "OUIDocumentStoreItem-Internal.h"
#import "OUIDocumentStoreFileItem-Internal.h"

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <CoreServices/CoreServices.h>
#else
#import <MobileCoreServices/MobileCoreServices.h>
#endif

#import <sys/stat.h> // For S_IWUSR

#if 0 && defined(DEBUG)
    #define DEBUG_STORE_ENABLED
    #define DEBUG_STORE(format, ...) NSLog(@"DOC STORE: " format, ## __VA_ARGS__)
#else
    #define DEBUG_STORE(format, ...)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_METADATA(format, ...) NSLog(@"METADATA: " format, ## __VA_ARGS__)
#else
    #define DEBUG_METADATA(format, ...)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_UNIQUE(format, ...) NSLog(@"UNIQUE: " format, ## __VA_ARGS__)
#else
    #define DEBUG_UNIQUE(format, ...)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_CLOUD_ENABLED
    #define DEBUG_CLOUD(format, ...) NSLog(@"CLOUD: " format, ## __VA_ARGS__)
#else
    #define DEBUG_CLOUD(format, ...)
#endif

// This logs complaints in the Simulator and iCloud isn't supported there anyway.
#if defined(TARGET_IPHONE_SIMULATOR) && TARGET_IPHONE_SIMULATOR
    #define USE_METADATA_QUERY 0
#else
    #define USE_METADATA_QUERY 1
#endif

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
#define SHOW_SYNC_THROTTLE
#endif

#ifdef SHOW_SYNC_THROTTLE
/* From the iOS 5 beta 7 release notes:

 "NEW: In this beta of iOS 5.0 the number of times an app can synchronize in quick succession with the servers has been reduced. If you are debugging your app and want to see whether your synchronize requests are being throttled, you can call the -[NSUbiquitousKeyValueStore _printDebugDescription] method directly in gdb. Please note that -[NSUbiquitousKeyValueStore _printDebugDescription] is an SPI so you are strongly advised not to use it in your app."
*/
@interface NSUbiquitousKeyValueStore (/*Private*/)
- (void)_printDebugDescription;
@end
#endif

OBDEPRECATED_METHOD(-documentStore:proxyClassForURL:); // -documentStore:fileItemClassForURL:
OBDEPRECATED_METHOD(-documentStore:scannedProxies:); // -documentStore:scannedFileItems:

NSString * const OUIDocumentStoreFileItemsBinding = @"fileItems";
NSString * const OUIDocumentStoreTopLevelItemsBinding = @"topLevelItems";

// iWork uses ".../Foo.folder/Document.ext" for grouping in the document picker.
static NSString * const OUIDocumentStoreFolderPathExtension = @"folder";

static BOOL _isFolder(NSURL *URL)
{
    return [[URL pathExtension] caseInsensitiveCompare:OUIDocumentStoreFolderPathExtension] == NSOrderedSame;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
static NSString *_folderFilename(NSURL *fileURL)
{
    NSURL *containerURL = [fileURL URLByDeletingLastPathComponent];
    if (_isFolder(containerURL))
        return [containerURL lastPathComponent];
    return nil;
}
#endif

@interface OUIDocumentStore ()
+ (NSURL *)_ubiquityContainerURL;
+ (NSURL *)_ubiquityDocumentsURL:(NSError **)outError;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (OUIDocumentStoreScope)_defaultScope;
- (NSURL *)_containerURLForScope:(OUIDocumentStoreScope)scope error:(NSError **)outError;
- (NSURL *)_urlForScope:(OUIDocumentStoreScope)scope folderName:(NSString *)folderName fileName:(NSString *)fileName error:(NSError **)outError;
- (NSURL *)_moveURL:(NSURL *)sourceURL toCloud:(BOOL)shouldBeInCloud error:(NSError **)outError;
#endif
- (void)_startMetadataQuery;
- (void)_stopMetadataQuery;
- (void)_flushAfterInitialDocumentScanActions;
- (OUIDocumentStoreFileItem *)_newFileItemForURL:(NSURL *)fileURL date:(NSDate *)date;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)_applicationDidEnterBackgroundNotification:(NSNotification *)note;
- (void)_applicationWillEnterForegroundNotification:(NSNotification *)note;
#endif
- (void)_renameFileItemsToHaveUniqueFileNames;
@end

@implementation OUIDocumentStore
{
    // NOTE: There is no setter for this; we currently make some calls to the delegate from a background queue and just use the ivar.
    id <OUIDocumentStoreDelegate> _nonretained_delegate;
    NSURL *_directoryURL;
    
    NSMetadataQuery *_metadataQuery;
    BOOL _metadataInitialScanFinished;
    NSMutableArray *_afterInitialDocumentScanActions;

    BOOL _isRenamingFileItemsToHaveUniqueFileNames;
    
    NSSet *_fileItems;
    NSDictionary *_groupItemByName;
    
    NSSet *_topLevelItems;
    
    NSOperationQueue *_actionOperationQueue;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (NSURL *)userDocumentsDirectoryURL;
{
    static NSURL *documentDirectoryURL = nil; // Avoid trying the creation on each call.
    
    if (!documentDirectoryURL) {
        NSError *error = nil;
        documentDirectoryURL = [[[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error] copy];
        if (!documentDirectoryURL) {
            NSLog(@"Error creating user documents directory: %@", [error toPropertyList]);
        }
        
        [documentDirectoryURL autorelease];
        documentDirectoryURL = [[documentDirectoryURL URLByStandardizingPath] copy];
    }
    
    return documentDirectoryURL;
}
#endif

// We CANNOT check for file non-existence here. iCloud documents may be present on the server and we may only know about them via an NSMetadataQuery update that produced an OUIDocumentStoreFileItem. Also, iWork tries to avoid duplicate file names across folders and storage scopes. So, we take in an array of URLs and unique against that.
static NSString *_availableName(NSSet *usedFileNames, NSString *baseName, NSString *extension, NSUInteger *ioCounter)
{
    NSUInteger counter = *ioCounter; // starting counter
    
    while (YES) {
        NSString *candidateName;
        if (counter == 0) {
            candidateName = [[NSString alloc] initWithFormat:@"%@.%@", baseName, extension];
            counter = 2; // First duplicate should be "Foo 2".
        } else {
            candidateName = [[NSString alloc] initWithFormat:@"%@ %d.%@", baseName, counter, extension];
            counter++;
        }
        
        if ([usedFileNames member:candidateName] == nil) {
            *ioCounter = counter; // report how many we used
            return [candidateName autorelease];
        }
        [candidateName release];
    }
}

- (NSMutableSet *)_copyCurrentlyUsedFileNames;
{
    NSMutableSet *usedFileNames = [[NSMutableSet alloc] init];
    for (NSURL *url in [_fileItems valueForKey:OUIDocumentStoreFileItemFilePresenterURLBinding])
        [usedFileNames addObject:[url lastPathComponent]];
    return usedFileNames;
}

- (NSString *)availableFileNameAvoidingUsedFileNames:(NSSet *)usedFilenames withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    OBPRECONDITION(_fileItems); // Make sure we've done a local scan. It might be out of date, so maybe we should scan here too.
    OBPRECONDITION(self.hasFinishedInitialMetdataQuery); // We can't unique against iCloud until whe know what is there
        
    return _availableName(usedFilenames, baseName, extension, ioCounter);
}

- (NSString *)availableFileNameWithBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    OBPRECONDITION(_fileItems); // Make sure we've done a local scan. It might be out of date, so maybe we should scan here too.
    OBPRECONDITION(self.hasFinishedInitialMetdataQuery); // We can't unique against iCloud until whe know what is there
    
    NSSet *usedFileNames = [self _copyCurrentlyUsedFileNames];
    NSString *fileName = [self availableFileNameAvoidingUsedFileNames:usedFileNames withBaseName:baseName extension:extension counter:ioCounter];
    [usedFileNames release];
    return fileName;
}

- (NSURL *)availableURLInDirectoryAtURL:(NSURL *)directoryURL baseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    NSString *availableFileName = [self availableFileNameWithBaseName:baseName extension:extension counter:ioCounter];
    return [directoryURL URLByAppendingPathComponent:availableFileName];
}

- (BOOL)userFileExistsWithFileNameOfURL:(NSURL *)fileURL;
{
    return [self fileItemNamed:[[fileURL lastPathComponent] stringByDeletingPathExtension]] != nil;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSURL *)availableURLWithFileName:(NSString *)fileName;
{
    NSString *originalName = [fileName stringByDeletingPathExtension];
    NSString *extension = [fileName pathExtension];
    
    // If the file item name ends in a number, we are likely duplicating a duplicate.  Take that as our starting counter.  Of course, this means that if we duplicate "Revenue 2010", we'll get "Revenue 2011". But, w/o this we'll get "Revenue 2010 2", "Revenue 2010 2 2", etc.
    NSString *baseName = nil;
    NSUInteger counter;
    OFSFileManagerSplitNameAndCounter(originalName, &baseName, &counter);
    
    return [self availableURLInDirectoryAtURL:[[self class] userDocumentsDirectoryURL]
                                     baseName:baseName
                                    extension:extension
                                      counter:&counter];
}
#endif

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- initWithDirectoryURL:(NSURL *)directoryURL delegate:(id <OUIDocumentStoreDelegate>)delegate;
{
    OBPRECONDITION(delegate);
    
    if (!(self = [super init]))
        return nil;

    _directoryURL = [directoryURL copy];
    _nonretained_delegate = delegate;
    
    _actionOperationQueue = [[NSOperationQueue alloc] init];
    [_actionOperationQueue setName:@"OUIDocumentStore file actions"];
    [_actionOperationQueue setMaxConcurrentOperationCount:1];
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_applicationDidEnterBackgroundNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(_applicationWillEnterForegroundNotification:) name:UIApplicationWillEnterForegroundNotification object:nil];
#endif
    
#if 0 && defined(DEBUG)
    if (_directoryURL)
        [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:_directoryURL];
#endif

    [self _startMetadataQuery];
    [self scanItemsWithCompletionHandler:nil]; OBFinishPortingLater("Should we let the caller specify a completion handler?");
    
    return self;
}

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;
{
    if (!_afterInitialDocumentScanActions)
        _afterInitialDocumentScanActions = [[NSMutableArray alloc] init];
    [_afterInitialDocumentScanActions addObject:[[action copy] autorelease]];
     
    // ... might be able to call it right now
    [self _flushAfterInitialDocumentScanActions];
}

- (void)dealloc;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#endif
    
    [_directoryURL release];
    
    [_metadataQuery release];
    
    for (OUIDocumentStoreFileItem *fileItem in _fileItems)
        [fileItem _invalidate];
    
    [_fileItems release];
    [_groupItemByName release];
    [_topLevelItems release];
    [_afterInitialDocumentScanActions release];
        
    OBASSERT([_actionOperationQueue operationCount] == 0);
    [_actionOperationQueue release];
    
    [super dealloc];
}

@synthesize directoryURL = _directoryURL;
- (void)setDirectoryURL:(NSURL *)directoryURL;
{
    if (OFISEQUAL(_directoryURL, directoryURL))
        return;
    
    [_directoryURL release];
    _directoryURL = [directoryURL copy];
    
    [self scanItemsWithCompletionHandler:nil];
    
}

// Allow external objects to synchronize with our operations.
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;
{
    OBPRECONDITION(_actionOperationQueue);
    
    [_actionOperationQueue addOperationWithBlock:block];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

static BOOL _performAdd(NSURL *fromURL, NSURL *toURL, OUIDocumentStoreScope scope, BOOL isReplacing, NSError **outError)
{
    OBPRECONDITION(![NSThread isMainThread]); // Were going to do file coordination or -setUbiquitous: stuff which could deadlock with file presenters on the main thread
    OBASSERT_NOTNULL(outError); // We know we pass in a non-null pointer, so we can avoid the outError-NULL checks.
    
    // We might be able to do a coordinated read/write to duplicate documents in iCloud, but -setUbiquitous:... is the official API and it *moves* documents. Since we need to sometimes move, let's just always do that. Since the source might have incoming iCloud writes or have presenters with outstanding writes, do a coordinated read while copying it into a temporary location. It is a bit annoying that we have two separate operations, but we should still get a consistent snapshot of the source at our destination location.
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
                 innerError = [copyError retain];
                 return;
             }
             
             success = YES;
         }];
        
        [coordinator release];
        
        if (!success) {
            OBASSERT(error || innerError);
            if (innerError)
                error = [innerError autorelease];
            *outError = error;
            return NO;
        }
    }
    
    if (scope == OUIDocumentStoreScopeUbiquitous) {
        // -setUbiquitous:... does its own file coordination and is documented to not be good to call on the main thread (since we may have file presenters that would cause deadlock).
        OBASSERT(![NSThread isMainThread]); // -setUbiquitous:... is documented to not be good to call on the main thread.
        
        if (![[NSFileManager defaultManager] setUbiquitous:YES itemAtURL:temporaryURL destinationURL:toURL error:outError]) {
            NSLog(@"Error from setUbiquitous:YES %@ -> %@: %@", temporaryURL, toURL, [*outError toPropertyList]);
            return NO;
        }
    } else {
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
                         innerError = [removeError retain];
                         NSLog(@"Error removing %@: %@", toURL, [removeError toPropertyList]);
                         return;
                     }
                 }
             }
             
             NSError *moveError = nil;
             if (![manager moveItemAtURL:temporaryURL toURL:toURL error:&moveError]) {
                 NSLog(@"Error moving %@ -> %@: %@", temporaryURL, toURL, [moveError toPropertyList]);
                 innerError = [moveError retain];
                 return;
             }
             
             success = YES;
         }];
        
        [coordinator release];
        
        if (!success) {
            OBASSERT(error || innerError);
            if (innerError)
                error = [innerError autorelease];
            *outError = error;
            
            // Clean up the temporary copy
            [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:NULL];
            
            return NO;
        }
    }
    
    return YES;
}

// Explicit scope version is useful if, for example, the document picker has an open directory and restores a sample document (which would have unknown scope), we should probably put it in that open folder with the default scope.
// On success, returns a block which is already enqueued on the document store's background serial operation queue. This isn't always useful, but if you need to wait for several operations to finish, it can be. The completion handler will also be called with the resulting file item. On error, calls the completionHandler with a nil item and the error encountered.
- (NSOperation *)addDocumentWithScope:(OUIDocumentStoreScope)scope inFolderNamed:(NSString *)folderName fromURL:(NSURL *)fromURL option:(OUIDocumentStoreAddOption)option completionHandler:(void (^)(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // We'll invoke the completion handler on the main thread

    if (!completionHandler)
        completionHandler = ^(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error){
            NSLog(@"Error adding document from %@: %@", fromURL, [error toPropertyList]);
        };
    
    completionHandler = [[completionHandler copy] autorelease]; // preserve scope
    
    if (scope == OUIDocumentStoreScopeUnknown)
        scope = [[self class] _defaultScope];
        
    NSURL *toURL = nil;
    BOOL isReplacing = NO;
    
    if (option == OUIDocumentStoreAddNormally) {
        // Use the given file name.
        NSError *error = nil;
        toURL = [self _urlForScope:scope folderName:folderName fileName:[fromURL lastPathComponent] error:&error];
        if (!toURL) {
            completionHandler(nil, error);
            return nil;
        }
    }
    else if (option == OUIDocumentStoreAddByRenaming) {
        // Generate a new file name.
        NSString *fileName = [fromURL lastPathComponent];
        NSString *baseName = nil;
        NSUInteger counter;
        OFSFileManagerSplitNameAndCounter([fileName stringByDeletingPathExtension], &baseName, &counter);

        fileName = [self availableFileNameWithBaseName:baseName extension:[fileName pathExtension] counter:&counter];

        NSError *error = nil;
        toURL = [self _urlForScope:scope folderName:folderName fileName:fileName error:&error];
        if (!toURL) {
            completionHandler(nil, error);
            return nil;
        }
    }
    else if (option == OUIDocumentStoreAddByReplacing) {
        // Use the given file name, but ensure that it does not exist in the documents directory.
        NSError *error = nil;
        toURL = [self _urlForScope:scope folderName:folderName fileName:[fromURL lastPathComponent] error:&error];
        if (!toURL) {
            completionHandler(nil, error);
            return nil;
        }
        
        isReplacing = YES;
    }
    else {
        // TODO: Perhaps we should create an error and assign it to outError?
        OBASSERT_NOT_REACHED("OUIDocumentStoreAddOpiton not given or invalid.");
        completionHandler(nil, nil);
        return nil;
    }
    
    // The rest of this method performs coordination operations which could deadlock with presenters on the main queue.
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        NSError *error = nil;
        BOOL success = _performAdd(fromURL, toURL, scope, isReplacing, &error);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (success) {
                [self scanItemsWithCompletionHandler:^{
                    OUIDocumentStoreFileItem *duplicateItem = [self fileItemWithURL:toURL];
                    OBASSERT(duplicateItem);
                    completionHandler(duplicateItem, nil);
                }];
            } else
                completionHandler(nil, error);
        }];
    }];
    
    // We must have a different queue for the actions than we have for notifications, lest we deadlock vs. our OUIDocumentStoreFileItems.
    [_actionOperationQueue addOperation:operation];
    
    return operation;
}

- (NSOperation *)addDocumentFromURL:(NSURL *)fromURL option:(OUIDocumentStoreAddOption)option completionHandler:(void (^)(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OUIDocumentStoreScope scope = [self scopeForFileURL:fromURL];
    if (scope == OUIDocumentStoreScopeUnknown) {
        // Might be coming from UIDocumentInteractionController or our app wrapper if we are restoring a template.
        scope = [[self class] _defaultScope];
    }
    
    return [self addDocumentWithScope:scope inFolderNamed:_folderFilename(fromURL) fromURL:fromURL option:option completionHandler:completionHandler];
}
#endif

static NSURL *_coordinatedMoveItem(OUIDocumentStoreFileItem *fileItem, NSURL *destinationDirectoryURL, NSString *destinationFileName, NSError **outError)
{
    OBPRECONDITION(![NSThread isMainThread]); // We should be on the action queue
    
    DEBUG_STORE(@"Moving item %@ into directory %@ with name %@", [fileItem shortDescription], [destinationDirectoryURL absoluteString], destinationFileName);
    
    NSURL *sourceURL = fileItem.fileURL;
    NSNumber *sourceIsDirectory = nil;
    NSError *resourceError = nil;
    if (![sourceURL getResourceValue:&sourceIsDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
        NSLog(@"Error checking if source URL %@ is a directory: %@", [sourceURL absoluteString], [resourceError toPropertyList]);
        // not fatal...
    }
    OBASSERT(sourceIsDirectory);
    
    NSURL *destinationURL = [destinationDirectoryURL URLByAppendingPathComponent:destinationFileName isDirectory:[sourceIsDirectory boolValue]];
    
    NSError *error = nil;
    __block BOOL success = NO;
    __block NSError *innerError = nil;
    
#ifdef DEBUG_STORE_ENABLED
    for (id <NSFilePresenter> presenter in [NSFileCoordinator filePresenters]) {
        NSLog(@"  presenter %@ at %@", [(id)presenter shortDescription], presenter.presentedItemURL);
    }
#endif
    
    // We're currently passing in the file item as the file presenter to _attempt_ to avoid having async -presentedItemDidMoveToURL: notifications sent (so we send it ourselves for a synchronous change). But, we still get an async change notification. The 'isDirectory' check is also an attempt to make sure we have the same URL that we would have gotten (with the proper trailing slash) in case NSFileCoordinator tries to cleanup incorrect fileURLs, even on non-nil presenters.
    NSFileCoordinator *coordinator = [[[NSFileCoordinator alloc] initWithFilePresenter:fileItem] autorelease];
    
    [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving
                           writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForReplacing
                                      error:&error
                                 byAccessor:
     ^(NSURL *newURL1, NSURL *newURL2){         
         DEBUG_STORE(@"  coordinator issued URLs to move from %@ to %@", newURL1, newURL2);
         
         NSFileManager *fileManager = [NSFileManager defaultManager];
         
         NSError *moveError = nil;
         if (![fileManager moveItemAtURL:newURL1 toURL:newURL2 error:&moveError]) {
             NSLog(@"Error moving \"%@\" to \"%@\": %@", [newURL1 absoluteString], [newURL2 absoluteString], [moveError toPropertyList]);
             innerError = [moveError retain];
             return;
         }
         
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
         
         // Recommended calling convention for this API (since it returns void) is to set a __block variable to success...
         success = YES;
     }];
    
    if (success) {
        OBASSERT(innerError == nil);
        // Change our URL synchronously. The 'newURL2' in the block above may *not* be the same as what we asked for if there is some intermediate operation, but by the time the synchronous call to NSFileCoordinator returns we should be here.
        [fileItem presentedItemDidMoveToURL:destinationURL];
        return destinationURL;
    } else {
        OBASSERT(innerError != nil);

        NSLog(@"Error renaming %@ with file name \"%@\": %@", [fileItem shortDescription], destinationFileName, error ? [error toPropertyList] : @"???");
        error = [innerError autorelease];
        if (outError)
            *outError = error;
        return nil;
    }
}

- (void)renameFileItem:(OUIDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionQueue:(NSOperationQueue *)completionQueue handler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION((completionQueue == nil) == (completionHandler == nil));
    
    // capture scope
    completionHandler = [[completionHandler copy] autorelease];
    
    /*
     From NSFileCoordinator.h, "For another example, the most accurate and safe way to coordinate a move is to invoke -coordinateWritingItemAtURL:options:writingItemAtURL:options:error:byAccessor: using the NSFileCoordinatorWritingForMoving option with the source URL and NSFileCoordinatorWritingForReplacing with the destination URL."
     */
    
    // The document should already live in the local documents directory, the ubiquity documents directory or a folder there under. Keep it in whichever one it was in.
    NSURL *containingDirectoryURL = [fileItem.fileURL URLByDeletingLastPathComponent];
    OBASSERT(containingDirectoryURL);
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
//    OBASSERT([containingDirectoryURL isEqual:[[self class] userDocumentsDirectoryURL]] ||
//             [containingDirectoryURL isEqual:[[self class] _ubiquityDocumentsURL:NULL]]);
// won't be equal unless the paths are standardized
// also won't be equal if the file is in the Inbox
    
    if ([[containingDirectoryURL lastPathComponent] isEqualToString:@"Inbox"]) {
        NSString *containingPath = [[[[containingDirectoryURL URLByDeletingLastPathComponent] path] stringByExpandingTildeInPath] stringByStandardizingPath];
        NSString *userPath = [[[[[self class] userDocumentsDirectoryURL] path] stringByExpandingTildeInPath] stringByStandardizingPath];
        if ([userPath isEqualToString:containingPath]) {
            containingDirectoryURL = [[self class] userDocumentsDirectoryURL];
            OBFinishPortingLater("Might want to move this from the Inbox to the Cloud instead of 'Documents'");
       }
    }
#endif
    
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)fileType, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
        NSUInteger emptyCounter = 0;
    
    NSString *destinationFileName = [self availableFileNameWithBaseName:baseName extension:(NSString *)extension counter:&emptyCounter];
    CFRelease(extension);
    
    OBFinishPortingLater("Rename any previews for this item too, since we find them by name (and remove the previews on failure, probably)");

    [self performAsynchronousFileAccessUsingBlock:^{
        NSError *error = nil;
        NSURL *destinationURL = _coordinatedMoveItem(fileItem, containingDirectoryURL, destinationFileName, &error);
        if (completionHandler) {
            [completionQueue addOperationWithBlock:^{
                if (destinationURL)
                    completionHandler(destinationURL, nil);
                else 
                    completionHandler(nil, error);
            }];
        }
    }];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)makeGroupWithFileItems:(NSSet *)fileItems completionHandler:(void (^)(OUIDocumentStoreGroupItem *group, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items
    
    OBFinishPortingLater("Should we rescan before finding an available path, or depend on the caller to know things are up to date?");
    OBPRECONDITION(_fileItems); // Make sure we've done a local scan. It might be out of date, so maybe we should scan here too.
    OBPRECONDITION(self.hasFinishedInitialMetdataQuery); // We can't unique against iCloud until whe know what is there

    // Find an available folder placeholder name. First, build up a list of all the folder URLs we know about based on our file items.
    NSMutableSet *folderFilenames = [NSMutableSet set];
    for (OUIDocumentStoreFileItem *fileItem in _fileItems) {
        NSURL *containingURL = [fileItem.fileURL URLByDeletingLastPathComponent];
        if (_isFolder(containingURL)) // Might be ~/Documents or a ubiquity container
            [folderFilenames addObject:[containingURL lastPathComponent]];
    }
    
    NSString *baseName = NSLocalizedStringFromTableInBundle(@"Folder", @"OmniUI", OMNI_BUNDLE, @"Base name for document picker folder names");
    NSUInteger counter = 0;
    NSString *folderName = _availableName(folderFilenames, baseName, OUIDocumentStoreFolderPathExtension, &counter);
    
    [self moveItems:fileItems toFolderNamed:folderName completionHandler:completionHandler];
}
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)moveItems:(NSSet *)fileItems toFolderNamed:(NSString *)folderName completionHandler:(void (^)(OUIDocumentStoreGroupItem *group, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items, and this is the queue we'll invoke the completion handler on.
    
    OBFinishPortingLater("Can we rename iCloud items that aren't yet fully (or at all) downloaded?");

    // capture scope (might not be necessary since we aren't currently asynchronous here).
    completionHandler = [[completionHandler copy] autorelease];

    // This is similar to the document renaming path, but we already know that no other renaming should be needed (and we are doing multiple items).    
    for (OUIDocumentStoreFileItem *fileItem in fileItems) {
        NSURL *sourceURL = fileItem.fileURL;

        // Make a destination in a folder under the same container scope as the original item
        NSURL *destinationDirectoryURL;
        {
            NSError *error = nil;
            NSURL *containerURL = [self _containerURLForScope:fileItem.scope error:&error];
            if (!containerURL) {
                if (completionHandler)
                    completionHandler(nil, error);
                return;
            }
            
            // TODO: We might be creating a directory in the ubiquity container. To we need to do a coordinated read/write of this non-document directory in case there is an incoming folder creation from iCloud? This seems like a pretty small hole, but still...
            destinationDirectoryURL = [containerURL URLByAppendingPathComponent:folderName isDirectory:YES];
            if (![[NSFileManager defaultManager] directoryExistsAtPath:[destinationDirectoryURL path]]) {
                if (![[NSFileManager defaultManager] createDirectoryAtURL:destinationDirectoryURL withIntermediateDirectories:YES/*shouldn't be necessary...*/ attributes:nil error:&error]) {
                    if (completionHandler)
                        completionHandler(nil, error);
                    return;
                }
            }
        }
        
        NSError *error = nil;
        NSURL *destinationURL = _coordinatedMoveItem(fileItem, destinationDirectoryURL, [sourceURL lastPathComponent], &error);
        if (!destinationURL) {
            if (completionHandler)
                completionHandler(nil, error);
            return;
        }
    }
    
    [self scanItemsWithCompletionHandler:^{
        OUIDocumentStoreGroupItem *group = [_groupItemByName objectForKey:folderName];
        OBASSERT(group);
        
        if (completionHandler)
            completionHandler(group, nil);
    }];
}
#endif

- (void)moveItemsAtURLs:(NSSet *)urls toFolderInCloudWithName:(NSString *)folderNameOrNil completionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    NSMutableDictionary *movedURLs = [NSMutableDictionary dictionary];
    NSMutableDictionary *errorURLs = [NSMutableDictionary dictionary];
    
    // Early out for no-ops
    if ([urls count] == 0) {
        completionHandler(movedURLs, errorURLs);
        return;
    }
    
    OBFinishPortingLater("Can we rename iCloud items that aren't yet fully (or at all) downloaded?");
    
#ifdef DEBUG_CLOUD_ENABLED
    void (^originalCompletionHandler)(NSDictionary *, NSDictionary *) = completionHandler;
    completionHandler = ^(NSDictionary *theMovedURLs, NSDictionary *theErrorURLs) {
        DEBUG_CLOUD(@"-moveItemsAtURLs:... is executing completion handler %p", (void *)originalCompletionHandler);
        originalCompletionHandler(theMovedURLs, theErrorURLs);
    };
#endif
        
    // Make a destination in a folder under the same container scope as the original item
    NSURL *destinationDirectoryURL;
    {
        NSError *error = nil;
        NSURL *containerURL = [[self class] _ubiquityDocumentsURL:&error];
        if (!containerURL)
            goto bail;
        
        // TODO: We might be creating a directory in the ubiquity container. To we need to do a coordinated read/write of this non-document directory in case there is an incoming folder creation from iCloud? This seems like a pretty small hole, but still...
        if (folderNameOrNil)
            destinationDirectoryURL = [containerURL URLByAppendingPathComponent:folderNameOrNil isDirectory:YES];
        else
            destinationDirectoryURL = containerURL;
        
        OBASSERT([destinationDirectoryURL isFileURL]);
        DEBUG_CLOUD(@"-moveItemsAtURLs:... is trying to create cloud directory %@", destinationDirectoryURL);
        if (![[NSFileManager defaultManager] directoryExistsAtPath:[destinationDirectoryURL path]]) {
            if (![[NSFileManager defaultManager] createDirectoryAtURL:destinationDirectoryURL withIntermediateDirectories:YES/*shouldn't be necessary...*/ attributes:nil error:&error]) {
                for (NSURL *sourceURL in urls)
                    [errorURLs setObject:error forKey:sourceURL];
                
                DEBUG_CLOUD(@"-moveItemsAtURLs:... failed to create cloud directory %@: %@", destinationDirectoryURL, error);
                goto bail;
            }
        }
    }
        
    for (NSURL *sourceURL in urls) {
        OBASSERT([[movedURLs allKeys] containsObject:sourceURL] == NO);
        OBASSERT([[errorURLs allKeys] containsObject:sourceURL] == NO);
        
        NSURL *destinationURL = [destinationDirectoryURL URLByAppendingPathComponent:[sourceURL lastPathComponent]];
        NSError *error;
        
        DEBUG_CLOUD(@"-moveItemsAtURLs:... is attempting to move %@ to the cloud at %@", sourceURL, destinationURL);
        if ([[NSFileManager defaultManager] setUbiquitous:YES itemAtURL:sourceURL destinationURL:destinationURL error:&error]) {
            DEBUG_CLOUD(@"-moveItemsAtURLs:... successfully created %@", destinationURL);
            [movedURLs setObject:destinationURL forKey:sourceURL];
        } else {
            OBASSERT_NOTNULL(error);
            DEBUG_CLOUD(@"-moveItemsAtURLs:... failed to create %@: %@", destinationURL, error);
            [errorURLs setObject:error forKey:sourceURL];
        }
    }
    
    [self scanItemsWithCompletionHandler:^{
        if (completionHandler)
            completionHandler(movedURLs, errorURLs);
    }];
    DEBUG_CLOUD(@"-moveItemsAtURLs:... is returning");
    return;
    
bail:
    if (completionHandler)
        completionHandler(movedURLs, errorURLs);
    
    DEBUG_CLOUD(@"-moveItemsAtURLs:... is returning");
}

- (NSOperation *)deleteItem:(OUIDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items, and this is the queue we'll invoke the completion handler on.

    // capture scope (might not be necessary since we aren't currently asynchronous here).
    completionHandler = [[completionHandler copy] autorelease];
    
    NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:fileItem];
        
        NSError *error = nil;
        __block BOOL success = NO;
        __block NSError *innerError = nil;
        
        [coordinator coordinateWritingItemAtURL:fileItem.fileURL options:NSFileCoordinatorWritingForDeleting error:&error byAccessor:^(NSURL *newURL){
            DEBUG_STORE(@"  coordinator issued URL to delete %@", newURL);
            
            NSError *deleteError = nil;
            if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&deleteError]) {
                NSLog(@"Error deleting %@: %@", [newURL absoluteString], [deleteError toPropertyList]);
                innerError = [deleteError retain];
                return;
            }
            
            // Recommended calling convention for this API (since it returns void) is to set a __block variable to success...
            success = YES;
        }];
        
        [coordinator release];

        if (!success) {
            OBASSERT(error || innerError);
            if (innerError)
                error = [innerError autorelease];
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
    
    [_actionOperationQueue addOperation:op];
    return op;
}

@synthesize fileItems = _fileItems;
@synthesize topLevelItems = _topLevelItems;

// NSMetadataItem passes URLs w/o the trailing slash when the really are directories. Use strings for keys instead of URLs and trim the trailing slash if it is there.
static NSString *_fileItemCacheKeyForURL(NSURL *url)
{
    return [[url absoluteString] stringByRemovingSuffix:@"/"];
}


static OUIDocumentStoreFileItem *_addFileItemWithURL(OUIDocumentStore *self, NSMutableDictionary *urlToExistingFileItem, NSMutableSet *fileItems, NSURL *fileURL, NSDate *date)
{
    OBPRECONDITION(fileItems);
    OBPRECONDITION(fileURL);

    // The caller should have verified that the URL has a valid file type for us, but we'll double-check.
    NSString *uti = [OFSFileInfo UTIForURL:fileURL];
    
    if (![self->_nonretained_delegate documentStore:self shouldIncludeFileItemWithFileType:uti]) {
        OBASSERT_NOT_REACHED("The caller should have verified that the URL has a valid file type for us");
        return nil;
    }
    
    OUIDocumentStoreFileItem *fileItem = [urlToExistingFileItem objectForKey:_fileItemCacheKeyForURL(fileURL)];
    
    // Applications may return nil if it no longer is interested in this file item (e.g. switched to viewing stencils)
    OBFinishPortingLater("Since the result of this is controlled by the filter UI in the document picker, we should have different API to pass in an immutable mapping of UTI->Class or otherwise ensure this is thread-safe.");
    if (![self->_nonretained_delegate documentStore:self fileItemClassForURL:fileURL])
        return nil;
    
    if (fileItem) { 
        DEBUG_STORE(@"Existing file item: %@", [fileItem shortDescription]);
        // The input lookup cache is immutable since we may end up scanning an iCloud document both via directory search and NSMetadataQuery, so we want to hit the cache twice and not create a duplicate.
        //NSLog(@"  reused file item %@ for %@", fileItem, fileURL);
        [fileItems addObject:fileItem];
    } else {
        fileItem = [self _newFileItemForURL:fileURL date:date];
        DEBUG_STORE(@"New file item %@ at %@ with scope %d", [fileItem shortDescription], fileItem.fileURL, fileItem.scope);
        OBASSERT(fileItem);
        
        // Register this in our cache. Otherwise if we are getting a totally new iCloud document, we might get one due to the filesystem scan and one due to the NSMetadataQuery.
        [urlToExistingFileItem setObject:fileItem forKey:_fileItemCacheKeyForURL(fileURL)];
        [fileItems addObject:fileItem];
        [fileItem release];
    }
    return fileItem;
}

// Called as part of a 'prepare' block. See the header doc for -[NSFileCoordinator prepare...] for discussion of why we pass NSFileCoordinatorReadingWithoutChanges for individual directories.
static void _scanDirectoryURL(OUIDocumentStore *self, NSFileCoordinator *coordinator, NSURL *directoryURL, NSMutableDictionary *urlToExistingFileItem, NSMutableSet *updatedFileItems)
{
    OBASSERT(![NSThread isMainThread]);
    
    __block BOOL readingSuccess = NO;
    NSError *readingError = nil;
    [coordinator coordinateReadingItemAtURL:directoryURL options:NSFileCoordinatorReadingWithoutChanges
                                      error:&readingError
                                 byAccessor:
     ^(NSURL *readURL){
         // We are reading directories that shouldn't be replaced wholesale by any other writers. BUT we'll sure want to know if they ever are. If so, we'll need to do URL surgery to make OUIDocumentStoreFileItems that have the URLs the should have, not relative URLs to readURL.
         OBASSERT(OFISEQUAL(readURL, directoryURL)); 
         
         readingSuccess = YES;
         
         NSMutableArray *scanDirectoryURLs = [NSMutableArray arrayWithObjects:directoryURL, nil];
         
         NSFileManager *fileManager = [NSFileManager defaultManager];
         
         while ([scanDirectoryURLs count] != 0) {
             NSURL *scanDirectoryURL = [[[scanDirectoryURLs lastObject] retain] autorelease]; // We're building a set, and it's faster to remove the last object than the first
             [scanDirectoryURLs removeLastObject];
             
             NSError *error = nil;
             NSArray *fileURLs = [fileManager contentsOfDirectoryAtURL:scanDirectoryURL includingPropertiesForKeys:[NSArray arrayWithObject:NSURLIsDirectoryKey] options:0 error:&error];
             if (!fileURLs)
                 NSLog(@"Unable to scan documents in %@: %@", scanDirectoryURL, [error toPropertyList]);
             else if ([fileURLs count] == 0) {
                 OBFinishPortingLater("Remove empty directories"); // I've gotten directories like "(A DOCUMENT BEING SAVED BY OmniOutliner-iPad)", maybe due to some other problem, but we need to prune empty directories somewhere.
             }
             
             for (NSURL *fileURL in fileURLs) {
                 NSString *uti = [OFSFileInfo UTIForURL:fileURL];
                 
                 // Recurse into non-document directories in ~/Documents. Not checking for OUIDocumentStoreFolderPathExtension here since I don't recall if documents sent to us from other apps via UIDocumentInteractionController end up inside ~/Documents or elsewhere (and it isn't working for me right now).
                 if (![self->_nonretained_delegate documentStore:self shouldIncludeFileItemWithFileType:uti]) {
                     NSNumber *isDirectory = nil;
                     NSError *resourceError = nil;
                     
                     if (![fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError])
                         NSLog(@"Unable to determine if %@ is a directory: %@", fileURL, [resourceError toPropertyList]);
                     else if ([isDirectory boolValue])
                         [scanDirectoryURLs addObject:fileURL];
                     continue;
                 }
                 
                 NSError *attributesError = nil;
                 NSDate *modificationDate = nil;
                 NSDictionary *attributes = [fileManager attributesOfItemAtPath:[fileURL path]  error:&attributesError];
                 if (!attributes)
                     NSLog(@"Error getting attributes for %@ -- %@", [fileURL absoluteString], [attributesError toPropertyList]);
                 else
                     modificationDate = [attributes fileModificationDate];
                 if (!modificationDate)
                     modificationDate = [NSDate date]; // Default to now if we can't get the attributes or they are bogus for some reason.
                 
                 // Files in our ubiquity container, found by directory scan, won't get sent a metadata item here, but will below (if they are in the query).
                 _addFileItemWithURL(self, urlToExistingFileItem, updatedFileItems, fileURL, modificationDate);
             }
         }
     }];
    
    if (!readingSuccess) {
        NSLog(@"Error scanning %@: %@", directoryURL, [readingError toPropertyList]);
        // We don't pass this up currently... should we make all the completion handlers deal with it? Add a main-thread delegate callback to present the error?
    }
}

// We perform the directory scan on a background thread using file coordination and then invoke the completion handler back on the main thread.
static void _scanDirectoryURLs(OUIDocumentStore *self, NSArray *directoryURLs, NSMutableDictionary *urlToExistingFileItem, NSMutableSet *updatedFileItems, void (^scanCompletionHandler)(void))
{
    OBPRECONDITION([NSThread isMainThread]);
    
    [self->_actionOperationQueue addOperationWithBlock:^{
        OBASSERT(![NSThread isMainThread]);

        DEBUG_STORE(@"Scanning directories %@", directoryURLs);

        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        __block BOOL prepareSuccess = NO;
        NSError *prepareError = nil;
        [coordinator prepareForReadingItemsAtURLs:directoryURLs options:0
                               writingItemsAtURLs:nil options:0
                                            error:&prepareError
                                       byAccessor:
         ^(void (^prepareCompletionHandler)(void)){
             prepareSuccess = YES;
             
             for (NSURL *directoryURL in directoryURLs)
                 _scanDirectoryURL(self, coordinator, directoryURL, urlToExistingFileItem, updatedFileItems);
             
             if (prepareCompletionHandler)
                 prepareCompletionHandler();
         }];
        
        [coordinator release];
        
        if (!prepareSuccess) {
            NSLog(@"Error preparing to scan %@: %@", directoryURLs, [prepareError toPropertyList]);
            // We don't pass this up currently... should we make all the completion handlers deal with it? Add a main-thread delegate callback to present the error?
        }
        
        if (scanCompletionHandler)
            [[NSOperationQueue mainQueue] addOperationWithBlock:scanCompletionHandler];
    }];
}

- (BOOL)hasFinishedInitialMetdataQuery;
{
#if USE_METADATA_QUERY
    // _metadataQuery will be nil if there is no iCloud account on the device or Documents & Data is disabled.
    return !_metadataQuery || _metadataInitialScanFinished;
#else
    return YES; // as finished as it is going to get!
#endif
}

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;
{
    // Need to know what class of file items to make.
    OBPRECONDITION(_nonretained_delegate);
    
    // Build an index to help in reusing file items
    NSMutableDictionary *urlToExistingFileItem = [[NSMutableDictionary alloc] init];
    for (OUIDocumentStoreFileItem *fileItem in _fileItems) {
        OBASSERT([urlToExistingFileItem objectForKey:_fileItemCacheKeyForURL(fileItem.fileURL)] == nil);
        [urlToExistingFileItem setObject:fileItem forKey:_fileItemCacheKeyForURL(fileItem.fileURL)];
    }
    DEBUG_STORE(@"urlToExistingFileItem = %@", urlToExistingFileItem);
    
    // Scan the existing documents directory, reusing file items when possible. We'll do the scan on a background coordinated read. The background queue should NOT mutate existing file items, since we don't want KVO firing on the background thread.
    NSMutableSet *updatedFileItems = [[NSMutableSet alloc] init];
    NSMutableArray *directoryURLs = [NSMutableArray array];
    
    // Scan our local ~/Documents if we have one.
    if (_directoryURL)
        [directoryURLs addObject:_directoryURL];
    
    // In addition to scanning our local Documents directory (on iPad, at least), we also want to scan our ubiquity container directly. We'll still ALSO scan our NSMetadataQuery, but this avoids cases where we put a document in iCloud and it "disappears" for a while due to the NSMetadataQuery not updating instantly.
    NSURL *ubiquityContainerURL = [[self class] _ubiquityContainerURL];
    if  (ubiquityContainerURL)
        [directoryURLs addObject:ubiquityContainerURL];
    
    _scanDirectoryURLs(self, directoryURLs, urlToExistingFileItem, updatedFileItems, ^{
        {
            // If you poke at the NSMetadataQuery before it sends out its initial 'finished scan' notification it will usually report zero results.
            if (_metadataQuery && _metadataInitialScanFinished) {
                [_metadataQuery disableUpdates];
                @try {
                    // Using the -results proxy is discouraged
                    NSUInteger metadataItemCount = [_metadataQuery resultCount];
                    DEBUG_METADATA(@"%ld items found via query", metadataItemCount);
                    
                    for (NSUInteger metadataItemIndex = 0; metadataItemIndex < metadataItemCount; metadataItemIndex++) {
                        NSMetadataItem *item = [_metadataQuery resultAtIndex:metadataItemIndex];
                        
                        NSURL *fileURL = [item valueForAttribute:NSMetadataItemURLKey];
                        OBASSERT([self scopeForFileURL:fileURL] == OUIDocumentStoreScopeUbiquitous);
                        
                        DEBUG_METADATA(@"item %@ %@", item, [fileURL absoluteString]);
                        DEBUG_METADATA(@"  %@", [item valuesForAttributes:[NSArray arrayWithObjects:NSMetadataUbiquitousItemHasUnresolvedConflictsKey, NSMetadataUbiquitousItemIsDownloadedKey, NSMetadataUbiquitousItemIsDownloadingKey, NSMetadataUbiquitousItemIsUploadedKey, NSMetadataUbiquitousItemIsUploadingKey, NSMetadataUbiquitousItemPercentDownloadedKey, NSMetadataUbiquitousItemPercentUploadedKey, NSMetadataItemFSContentChangeDateKey, nil]]);

                        NSDate *date = [item valueForAttribute:NSMetadataItemFSContentChangeDateKey];
                        if (!date) {
                            OBASSERT_NOT_REACHED("No date on metadata item");
                            date = [NSDate date];
                        }

                        // Unlike the local case, we don't recurse into directories here since the metadata query will do it for us anyway.
                        OUIDocumentStoreFileItem *fileItem = _addFileItemWithURL(self, urlToExistingFileItem, updatedFileItems, fileURL, date);
                        
                        [fileItem _updateWithMetadataItem:item];
                        
                    }
                } @finally {
                    [_metadataQuery enableUpdates];
                }
            }
            
#if 0 && defined(DEBUG_bungi)
            do {
                NSError *error = nil;
                NSURL *documentsURL = [[self class] _ubiquityDocumentsURL:&error];
                if (!documentsURL) {
                    // error already logged
                    break;
                }
                NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:documentsURL includingPropertiesForKeys:nil options:0 error:&error];
                if (!contents) {
                    NSLog(@"Error getting contents of %@: %@", [documentsURL absoluteString], [error toPropertyList]);
                    break;
                }
                NSLog(@"%@ -> %@", documentsURL, contents);
            } while (0);
#endif
            
            // Invalidate the old file items that are no longer found.
            for (NSString *cacheKey in urlToExistingFileItem) {
                OUIDocumentStoreFileItem *fileItem = [urlToExistingFileItem objectForKey:cacheKey];
                if ([updatedFileItems member:fileItem] == nil)
                    [fileItem _invalidate];
            }
        }
        
        BOOL fileItemsChanged = OFNOTEQUAL(_fileItems, updatedFileItems);
        if (fileItemsChanged) {
            [self willChangeValueForKey:OUIDocumentStoreFileItemsBinding];
            [_fileItems release];
            _fileItems = [[NSSet alloc] initWithSet:updatedFileItems];
            [self didChangeValueForKey:OUIDocumentStoreFileItemsBinding];
            
        }
        
        [urlToExistingFileItem release];;
        [updatedFileItems release];

        // Filter items into groups (and the remaining top-level items).
        {
            NSMutableSet *topLevelItems = [[NSMutableSet alloc] init];
            NSMutableDictionary *itemsByGroupName = [[NSMutableDictionary alloc] init];
            
            for (OUIDocumentStoreFileItem *fileItem in _fileItems) {
                NSURL *containerURL = [fileItem.fileURL URLByDeletingLastPathComponent];
                if (_isFolder(containerURL)) {
                    NSString *groupName = [containerURL lastPathComponent];
                    
                    NSMutableSet *itemsInGroup = [itemsByGroupName objectForKey:groupName];
                    if (!itemsInGroup) {
                        itemsInGroup = [[NSMutableSet alloc] init];
                        [itemsByGroupName setObject:itemsInGroup forKey:groupName];
                        [itemsInGroup release];
                    }
                    [itemsInGroup addObject:fileItem];
                } else {
                    [topLevelItems addObject:fileItem];
                }
            }
            
            // Build/update groups, now that we know the final set of items in each
            NSMutableDictionary *groupByName = [NSMutableDictionary dictionary];
            for (NSString *groupName in itemsByGroupName) {
                OUIDocumentStoreGroupItem *groupItem = [_groupItemByName objectForKey:groupName];
                if (!groupItem) {
                    groupItem = [[[OUIDocumentStoreGroupItem alloc] initWithDocumentStore:self] autorelease];
                    groupItem.name = groupName;
                }
                
                [groupByName setObject:groupItem forKey:groupName];
                groupItem.fileItems = [itemsByGroupName objectForKey:groupName];
                
                [topLevelItems addObject:groupItem];
            }
            [itemsByGroupName release];
            
            [_groupItemByName release];
            _groupItemByName = [groupByName copy];
            DEBUG_STORE(@"Scanned groups %@", _groupItemByName);
            DEBUG_STORE(@"Scanned top level items %@", _topLevelItems);
            
            if (OFNOTEQUAL(_topLevelItems, topLevelItems)) {
                [self willChangeValueForKey:OUIDocumentStoreTopLevelItemsBinding];
                [_topLevelItems release];
                _topLevelItems = [topLevelItems copy];
                [self didChangeValueForKey:OUIDocumentStoreTopLevelItemsBinding];
            }
            
            [topLevelItems release];
        }
        
        if ([_nonretained_delegate respondsToSelector:@selector(documentStore:scannedFileItems:)])
            [_nonretained_delegate documentStore:self scannedFileItems:_fileItems];
        
        [self _flushAfterInitialDocumentScanActions];
        if (completionHandler)
            completionHandler();
        
        // Now, after we've reported our results, check if there are any documents with the same names. We want document names to be unambiguous, following iWork's lead.
        [self _renameFileItemsToHaveUniqueFileNames];
    });
}

- (BOOL)hasDocuments;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after -startScanningDocuments
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items
    
    return [_fileItems count] != 0;
}

- (OUIDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after -startScanningDocuments
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items

    if (url == nil || ![url isFileURL])
        return nil;
    
    NSString *standardizedPathForURL = [[url path] stringByStandardizingPath];
    OBASSERT(standardizedPathForURL != nil);
    for (OUIDocumentStoreFileItem *fileItem in _fileItems) {
        NSString *fileItemPath = [[fileItem.fileURL path] stringByStandardizingPath];
        OBASSERT(fileItemPath != nil);
        
        DEBUG_STORE(@"- Checking file item: '%@'", fileItemPath);
        if ([fileItemPath compare:standardizedPathForURL] == NSOrderedSame)
            return fileItem;
    }
    DEBUG_STORE(@"Couldn't find file item for path: '%@'", standardizedPathForURL);
    DEBUG_STORE(@"Unicode: '%s'", [standardizedPathForURL cStringUsingEncoding:NSNonLossyASCIIStringEncoding]);
    return nil;
}

- (OUIDocumentStoreFileItem *)fileItemNamed:(NSString *)name;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after -startScanningDocuments
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items
    
    for (OUIDocumentStoreFileItem *fileItem in _fileItems)
        if ([fileItem.name isEqual:name])
            return fileItem;

    return nil;
}

static NSString *_standardizedPathForURL(NSURL *url)
{
    OBASSERT([url isFileURL]);
    NSString *urlPath = [[url absoluteURL] path];
    
    NSString *path = [[urlPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
    
    // In some cases this doesn't normalize /private/var/mobile and /var/mobile to the same thing.
    path = [path stringByRemovingPrefix:@"/var/mobile/"];
    path = [path stringByRemovingPrefix:@"/private/var/mobile/"];
    
    return path;
}

static BOOL _urlContainedByURL(NSURL *url, NSURL *containerURL)
{
    if (!containerURL)
        return NO;
    
    // -[NSFileManager contentsOfDirectoryAtURL:...], when given something in file://localhost/var/mobile/... will return file URLs with non-standarized paths like file://localhost/private/var/mobile/...  Terrible.
    OBASSERT([containerURL isFileURL]);
    
    NSString *urlPath = _standardizedPathForURL(url);
    NSString *containerPath = _standardizedPathForURL(containerURL);
    
    if (![containerPath hasSuffix:@"/"])
        containerPath = [containerPath stringByAppendingString:@"/"];
    
    return [urlPath hasPrefix:containerPath];
}

// This must be thread safe.
- (OUIDocumentStoreScope)scopeForFileURL:(NSURL *)fileURL;
{
    if (_urlContainedByURL(fileURL, _directoryURL))
        return OUIDocumentStoreScopeLocal;
    
    // OBFinishPorting: Is there a possible race condition between an item scan calling back to us and being foregrounded/backgrounded changing our container URL between something valid and nil?
    if (_urlContainedByURL(fileURL, [[self class] _ubiquityContainerURL]))
        return OUIDocumentStoreScopeUbiquitous;
        
    return OUIDocumentStoreScopeUnknown;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSString *)documentTypeForNewFiles;
{
    if ([_nonretained_delegate respondsToSelector:@selector(documentStoreDocumentTypeForNewFiles:)])
        return [_nonretained_delegate documentStoreDocumentTypeForNewFiles:self];
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentStoreEditableDocumentTypes:)]) {
        NSArray *editableTypes = [_nonretained_delegate documentStoreEditableDocumentTypes:self];
        
        OBASSERT([editableTypes count] < 2); // If there is more than one, we might pick the wrong one.
        
        return [editableTypes lastObject];
    }
    
    return nil;
}

- (NSURL *)urlForNewDocumentOfType:(NSString *)documentUTI;
{
    NSString *baseName = [_nonretained_delegate documentStoreBaseNameForNewFiles:self];
    if (!baseName) {
        OBASSERT_NOT_REACHED("No delegate? You probably want one to provide a better base untitled document name.");
        baseName = @"My Document";
    }
    return [self urlForNewDocumentWithName:baseName ofType:documentUTI];
}

- (NSURL *)urlForNewDocumentWithName:(NSString *)name ofType:(NSString *)documentUTI;
{
    OBPRECONDITION(documentUTI);
    
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)documentUTI, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    static NSString * const UntitledDocumentCreationCounterKey = @"OUIUntitledDocumentCreationCounter";
    
    NSURL *directoryURL = [[self class] userDocumentsDirectoryURL];
    NSUInteger counter = [[NSUserDefaults standardUserDefaults] integerForKey:UntitledDocumentCreationCounterKey];
    
    NSURL *fileURL = [self availableURLInDirectoryAtURL:directoryURL baseName:name extension:(NSString *)extension counter:&counter];
    CFRelease(extension);
    
    [[NSUserDefaults standardUserDefaults] setInteger:counter forKey:UntitledDocumentCreationCounterKey];
    return fileURL;
}

- (void)createNewDocument:(void (^)(NSURL *createdURL, NSError *error))handler;
{
    NSString *documentType = [self documentTypeForNewFiles];
    NSURL *newDocumentURL = [self urlForNewDocumentOfType:documentType];
    
    handler = [[handler copy] autorelease];
    
    [_nonretained_delegate createNewDocumentAtURL:newDocumentURL completionHandler:^(NSURL *createdURL, NSError *error){
        if (!createdURL) {
            if (handler)
                handler(createdURL, error);
            return;
        }
        
        // If iCloud is enabled, we want to store documents there by default (at least until we get a preference).
        if (![[self class] _ubiquityContainerURL]) {
            if (handler)
                handler(createdURL, nil);
            return;
        }
            
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *cloudError = nil;
            NSURL *destinationURL = [self _moveURL:createdURL toCloud:YES error:&cloudError];
            if (!destinationURL) {
                if (handler) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        handler(nil, cloudError); // Though we may now have a local document...  
                    });
                }
            } else {
                if (handler) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        handler(destinationURL, nil);
                    });
                }
            }
        });
    }];
}

// The documentation says to not call -setUbiquitous:itemAtURL:destinationURL:error: on the main thread to avoid possible deadlock.
- (void)moveFileItems:(NSSet *)fileItems toCloud:(BOOL)shouldBeInCloud completionHandler:(void (^)(OUIDocumentStoreFileItem *failingItem, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // since we'll send the completion handler back to the main thread, make sure we came from there
    
    // capture scope...
    completionHandler = [[completionHandler copy] autorelease];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OUIDocumentStoreFileItem *failingFileItem = nil;
        NSError *error = nil;

        for (OUIDocumentStoreFileItem *fileItem in fileItems) {
            error = nil;
            if (![self _moveURL:fileItem.fileURL toCloud:shouldBeInCloud error:&error]) {
                failingFileItem = fileItem;
                break;
            }
        }
    
        if (completionHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(failingFileItem, error);
            });
        }
    });
}
#endif

#pragma mark -
#pragma mark Internal

NSString * const OUIDocumentStoreFileItemContentsChangedNotification = @"OUIDocumentStoreFileItemContentsChanged";
NSString * const OUIDocumentStoreFileItemInfoKey = @"fileItem";

- (void)_fileItemContentsChanged:(OUIDocumentStoreFileItem *)fileItem;
{
    OBPRECONDITION(fileItem);
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fileItem forKey:OUIDocumentStoreFileItemInfoKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentStoreFileItemContentsChangedNotification object:self userInfo:userInfo];
    }];
}

#pragma mark -
#pragma mark Private

// The top level is useful for settings and non-document type stuff, but NSMetadataQuery will only look in the Documents folder.
+ (NSURL *)_ubiquityContainerURL;
{
    static NSString *fullContainerID = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // We don't use the bundle identifier since we want iPad and Mac apps to be able to share a container!
        NSString *cloudID = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIApplicationCloudID"];
        NSString *containerID = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIApplicationCloudContainerID"];
        
        OBASSERT(!((cloudID == nil) ^ (containerID == nil)));
        
        if (cloudID) {
            fullContainerID = [[NSString alloc] initWithFormat:@"%@.%@", cloudID, containerID];
        }
    });
    
    return [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:fullContainerID];
}

+ (NSURL *)_ubiquityDocumentsURL:(NSError **)outError;
{
    // Later the Documents directory will be automatically created, but we need to do it ourselves now.
    NSURL *containerURL = [self _ubiquityContainerURL];
    if (!containerURL) {
        // iCloud storage hasn't been enabled by the user, or the application hasn't defined the infoDictionary keys (isn't using iCloud at all).
        OBUserCancelledError(outError);
        return nil;
    }
    
    NSURL *documentsURL = [containerURL URLByAppendingPathComponent:@"Documents"];
    NSString *documentsPath = [[documentsURL absoluteURL] path];
    BOOL directory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:documentsPath isDirectory:&directory]) {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:documentsPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"Error creating ubiquitous documents directory \"%@\": %@", documentsPath, [error toPropertyList]);
            if (outError)
                *outError = error;
            return nil;
        }
    } else {
        OBASSERT(directory); // remove it if it is a file?
    }
    
    return documentsURL;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

+ (OUIDocumentStoreScope)_defaultScope;
{
    if ([self _ubiquityContainerURL])
        return OUIDocumentStoreScopeUbiquitous;
    return OUIDocumentStoreScopeLocal;
}

- (NSURL *)_containerURLForScope:(OUIDocumentStoreScope)scope error:(NSError **)outError;
{
    switch (scope) {
        case OUIDocumentStoreScopeUbiquitous:
            return [[self class] _ubiquityDocumentsURL:outError];
        default:
            OBASSERT_NOT_REACHED("Bad scope -- using local documents");
            // fall through
        case OUIDocumentStoreScopeLocal:
            OBASSERT(_directoryURL);
            if (_directoryURL)
                return _directoryURL;
            return [[self class] userDocumentsDirectoryURL];
    }
}

- (NSURL *)_urlForScope:(OUIDocumentStoreScope)scope folderName:(NSString *)folderName fileName:(NSString *)fileName error:(NSError **)outError;
{
    OBPRECONDITION(fileName);
    
    NSURL *url = [self _containerURLForScope:scope error:outError];
    if (!url)
        return nil;
    
    if (folderName)
        url = [url URLByAppendingPathComponent:folderName];
    
    return [url URLByAppendingPathComponent:fileName];
}

- (NSURL *)_moveURL:(NSURL *)sourceURL toCloud:(BOOL)shouldBeInCloud error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    
    NSURL *targetDocumentsURL;
    if (shouldBeInCloud) {
        if (!(targetDocumentsURL = [[self class] _ubiquityDocumentsURL:outError]))
            return NO;
    } else
        targetDocumentsURL = [[self class] userDocumentsDirectoryURL];
    
    NSNumber *sourceIsDirectory = nil;
    NSError *resourceError = nil;
    if (![sourceURL getResourceValue:&sourceIsDirectory forKey:NSURLIsDirectoryKey error:&resourceError]) {
        NSLog(@"Error checking if source URL %@ is a directory: %@", [sourceURL absoluteString], [resourceError toPropertyList]);
        // not fatal...
    }
    OBASSERT(sourceIsDirectory);

    NSURL *destinationURL = [targetDocumentsURL URLByAppendingPathComponent:[sourceURL lastPathComponent] isDirectory:[sourceIsDirectory boolValue]];
    DEBUG_STORE(@"Moving document: %@ -> %@ (shouldBeInCloud=%u)", sourceURL, destinationURL, shouldBeInCloud);
    
    // The documentation says to not call -setUbiquitous:itemAtURL:destinationURL:error: on the main thread to avoid possible deadlock.
    OBASSERT(![NSThread isMainThread]);
    
    // The documentation also says that this method does a coordinated move, so we don't need to (and in fact, experimentally, if we try we deadlock).
    if (![[NSFileManager defaultManager] setUbiquitous:shouldBeInCloud itemAtURL:sourceURL destinationURL:destinationURL error:outError])
        return nil;
    
    return destinationURL;
}
#endif

- (void)_startMetadataQuery;
{
    if (_metadataQuery)
        return;

#if !USE_METADATA_QUERY
    return;
#endif
    
    NSURL *containerURL = [[self class] _ubiquityContainerURL];
    if (!containerURL) {
        // There is no iCloud account, or it has Documents & Data disabled.
        return;
    }
    
    _metadataQuery = [[NSMetadataQuery alloc] init];
    [_metadataQuery setSearchScopes:[NSArray arrayWithObjects:NSMetadataQueryUbiquitousDocumentsScope, nil]];
    [_metadataQuery setPredicate:[NSPredicate predicateWithFormat:@"%K like '*'", NSMetadataItemFSNameKey]];
    DEBUG_METADATA(@"Query %@", _metadataQuery);
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_metadataQueryDidStartGatheringNotifiction:) name:NSMetadataQueryDidStartGatheringNotification object:_metadataQuery];
    [center addObserver:self selector:@selector(_metadataQueryDidGatheringProgressNotifiction:) name:NSMetadataQueryGatheringProgressNotification object:_metadataQuery];
    [center addObserver:self selector:@selector(_metadataQueryDidFinishGatheringNotifiction:) name:NSMetadataQueryDidFinishGatheringNotification object:_metadataQuery];
    [center addObserver:self selector:@selector(_metadataQueryDidUpdateNotifiction:) name:NSMetadataQueryDidUpdateNotification object:_metadataQuery];
    
    OBASSERT(_metadataInitialScanFinished == NO);
    if (![_metadataQuery startQuery])
        NSLog(@"metadata query start failed");
    
#if 1 && defined(DEBUG)
    [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:[[self class] _ubiquityContainerURL]];
#endif
}

- (void)_stopMetadataQuery;
{
    if (_metadataQuery == nil)
        return;
    
    [_metadataQuery stopQuery];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NSMetadataQueryDidStartGatheringNotification object:_metadataQuery];
    [center removeObserver:self name:NSMetadataQueryGatheringProgressNotification object:_metadataQuery];
    [center removeObserver:self name:NSMetadataQueryDidFinishGatheringNotification object:_metadataQuery];
    [center removeObserver:self name:NSMetadataQueryDidUpdateNotification object:_metadataQuery];
    
    _metadataInitialScanFinished = NO;
    [_metadataQuery release];
    _metadataQuery = nil;
}

- (void)_metadataQueryDidStartGatheringNotifiction:(NSNotification *)note;
{
    DEBUG_METADATA(@"note %@", note);
    //    NSLog(@"results = %@", [self.metadataQuery results]);
}

- (void)_metadataQueryDidGatheringProgressNotifiction:(NSNotification *)note;
{
    DEBUG_METADATA(@"note %@", note);
    DEBUG_METADATA(@"results = %@", [_metadataQuery results]);
}

- (void)_metadataQueryDidFinishGatheringNotifiction:(NSNotification *)note;
{
    DEBUG_METADATA(@"note %@", note);
    DEBUG_METADATA(@"results = %@", [_metadataQuery results]);
    
    _metadataInitialScanFinished = YES;
    
    [self scanItemsWithCompletionHandler:nil];
}

- (void)_metadataQueryDidUpdateNotifiction:(NSNotification *)note;
{
    DEBUG_METADATA(@"note %@", note);
    DEBUG_METADATA(@"results = %@", [_metadataQuery results]);
    
    [self scanItemsWithCompletionHandler:nil];
}

- (void)_flushAfterInitialDocumentScanActions;
{
    if (!self.hasFinishedInitialMetdataQuery)
        return;
    
    NSArray *actions = [_afterInitialDocumentScanActions autorelease];
    _afterInitialDocumentScanActions = nil;
    
    // The initial scan may have been *started* due to the metadata query finishing, but we do the scan of the filesystem on a background thread now. So, synchronize with that and then invoke these actions on the main thread.
    [_actionOperationQueue addOperationWithBlock:^{
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            for (void (^action)(void) in actions)
                action();
        }];
    }];
}

- (OUIDocumentStoreFileItem *)_newFileItemForURL:(NSURL *)fileURL date:(NSDate *)date;
{
    // This assumes that the choice of file item class is consistent for each URL (since we will reuse file item).  Could double-check in this loop that the existing file item has the right class if we ever want this to be dynamic.
    Class fileItemClass = [_nonretained_delegate documentStore:self fileItemClassForURL:fileURL];
    if (!fileItemClass) {
        // We have a UTI for this, but the delegate doesn't want it to show up in the listing (OmniGraffle templates, for example).
        return nil;
    }
    OBASSERT(OBClassIsSubclassOfClass(fileItemClass, [OUIDocumentStoreFileItem class]));
    
    OUIDocumentStoreFileItem *fileItem = [[fileItemClass alloc] initWithDocumentStore:self fileURL:fileURL date:date];

    //NSLog(@"  made new file item %@ for %@", fileItem, fileURL);
    return fileItem;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

- (void)_applicationDidEnterBackgroundNotification:(NSNotification *)note;
{
    // If running, stop the NSMetadataQuery for now. When we are reactivated the user may have added/removed their iCloud account
    DEBUG_STORE(@"Application did enter background");
    [self _stopMetadataQuery];
}

- (void)_applicationWillEnterForegroundNotification:(NSNotification *)note;
{
    // Restart our query, if possible. Or, just rescan the filesystem if iCloud is not enabled.
    DEBUG_STORE(@"Application will enter foreground");
    
    [self _startMetadataQuery];
    [self scanItemsWithCompletionHandler:nil];
}

#endif

- (NSURL *)_renameTargetURLForFileItem:(OUIDocumentStoreFileItem *)fileItem usedFilenames:(NSSet *)usedFilenames counter:(NSUInteger *)ioCounter;
{
    NSURL *currentURL = fileItem.fileURL;

    // Build a starting point for the rename, based on the item's folder/scope
    NSString *candidate;
    {
        NSString *containingFolderName = nil;
        {
            NSURL *containingFolderURL = [currentURL URLByDeletingLastPathComponent];
            if (_isFolder(containingFolderURL))
                containingFolderName = [[containingFolderURL lastPathComponent] stringByDeletingPathExtension];
        }
        
        // Try a bunch of heuristics about the best renaming operations.
        
        if (fileItem.scope == OUIDocumentStoreScopeLocal) {
            // Move local documents out of the way of iCloud documents
            NSString *localFileName = [currentURL lastPathComponent];
            NSString *localSuffix = NSLocalizedStringFromTableInBundle(@"local", @"OmniUI", OMNI_BUNDLE, @"Suffix to automatically apply to document having the same name as others, when the document is local");
            
            candidate = [localFileName stringByDeletingPathExtension];
            
            if (containingFolderName == nil)
                candidate = [candidate stringByAppendingFormat:@" (%@)", localSuffix];
        else
            candidate = [candidate stringByAppendingFormat:@" (%@, %@)", containingFolderName, localSuffix];
            
            candidate = [candidate stringByAppendingPathExtension:[localFileName pathExtension]];
        } else if (containingFolderName) {
            // Documents with the same name in different folders get the "(foldername)" appended.
            NSString *localFileName = [currentURL lastPathComponent];
            candidate = [localFileName stringByDeletingPathExtension];
            candidate = [candidate stringByAppendingFormat:@" (%@)", containingFolderName];
            candidate = [candidate stringByAppendingPathExtension:[localFileName pathExtension]];
        } else {
            // Just update the counter
            candidate = [currentURL lastPathComponent];
        }
    }
    
    // Then unique the candidate versus whatever else we have.
    NSString *fileName = candidate;
    NSString *baseName = nil;
    NSUInteger counter;
    OFSFileManagerSplitNameAndCounter([fileName stringByDeletingPathExtension], &baseName, &counter);
    
    fileName = [self availableFileNameWithBaseName:baseName extension:[fileName pathExtension] counter:&counter];
    
    return [[currentURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:fileName];
}

- (void)_renameFileItemsToHaveUniqueFileNames;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // A previous set of rename operations is still enqueued.
    if (_isRenamingFileItemsToHaveUniqueFileNames)
        return;
    
    NSMutableDictionary *nameToFileItems = [[NSMutableDictionary alloc] init];
    
    for (OUIDocumentStoreFileItem *fileItem in _fileItems) {
        NSMutableArray *items = [nameToFileItems objectForKey:fileItem.name];
        if (!items) {
            items = [NSMutableArray arrayWithObject:fileItem];
            [nameToFileItems setObject:items forKey:fileItem.name];
        } else
            [items addObject:fileItem];
    }
    
    for (NSString *name in nameToFileItems) {
        NSMutableArray *fileItems = [nameToFileItems objectForKey:name];
        NSUInteger fileItemCount = [fileItems count];
        if (fileItemCount < 2)
            continue;

        // Note that we actually started a rename
        _isRenamingFileItemsToHaveUniqueFileNames = YES;

        // Sort the items into a deterministic order (as best we can) so that two different devices will perform the same renames.
        // Also, let items in the cloud have higher precedence so that there is reduced chance of conflict.
        [fileItems sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            OUIDocumentStoreFileItem *fileItem1 = obj1;
            OUIDocumentStoreFileItem *fileItem2 = obj2;
            
            OUIDocumentStoreScope scope1 = fileItem1.scope;
            OUIDocumentStoreScope scope2 = fileItem2.scope;
            
            if (scope1 != scope2) {
                if (scope1 == OUIDocumentStoreScopeUbiquitous)
                    return NSOrderedAscending;
                if (scope2 == OUIDocumentStoreScopeUbiquitous)
                    return NSOrderedDescending;
                
                OBASSERT_NOT_REACHED("One of them has unknown scope?");
            }

            NSURL *fileURL1 = fileItem1.fileURL;
            NSURL *fileURL2 = fileItem2.fileURL;
            
            BOOL isFolder1 = _isFolder([fileURL1 URLByDeletingLastPathComponent]);
            BOOL isFolder2 = _isFolder([fileURL2 URLByDeletingLastPathComponent]);
            
            if (isFolder1 ^ isFolder2) {
                if (isFolder2)
                    return NSOrderedAscending;
                return NSOrderedDescending;
            }

            return [[fileURL1 absoluteString] compare:[fileURL2 absoluteString]];
        }];
        
        DEBUG_UNIQUE("Duplicate names found between %@", [fileItems arrayByPerformingSelector:@selector(shortDescription)]);
        
        // Leave the first item having its original name; issue rename operations for the others
        
        // We'll update a set of used names rather than optimistically updating the names on the items (in case there is an error/conflict).
        NSMutableSet *usedFilenames = [self _copyCurrentlyUsedFileNames];
        DEBUG_UNIQUE("Avoiding file names %@", usedFilenames);
        
        NSUInteger counter = 0;
        for (NSUInteger fileItemIndex = 1; fileItemIndex < fileItemCount; fileItemIndex++) {
            OUIDocumentStoreFileItem *fileItem = [fileItems objectAtIndex:fileItemIndex];
            
            NSURL *targetURL = [self _renameTargetURLForFileItem:fileItem usedFilenames:usedFilenames counter:&counter];
            DEBUG_UNIQUE("Moving %@ to %@", fileItem.fileURL, targetURL);
            
            // Mark this file name as used, though we won't have seen the file presenter notification for it yet.
            [usedFilenames addObject:[targetURL lastPathComponent]];
            
            [self performAsynchronousFileAccessUsingBlock:^{
                NSError *moveError = nil;
                NSURL *destinationURL = _coordinatedMoveItem(fileItem, [targetURL URLByDeletingLastPathComponent], [targetURL lastPathComponent], &moveError);
                if (!destinationURL) {
                    NSLog(@"Error performing rename for uniqueness of %@ to %@: %@", fileItem.fileURL, targetURL, [moveError toPropertyList]);
                }
            }];
        }
        
        [usedFilenames release];
    }
    
    [nameToFileItems release];
    
    // If we did end up staring a rename, queue up a block to turn off this flag (we'll avoid futher uniquing operations until this completes).
    if (_isRenamingFileItemsToHaveUniqueFileNames) {
        [_actionOperationQueue addOperationWithBlock:^{
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                DEBUG_UNIQUE("Finished");
                OBASSERT(_isRenamingFileItemsToHaveUniqueFileNames == YES);
                _isRenamingFileItemsToHaveUniqueFileNames = NO; 
            }];
        }];
    }
}

@end


#if 0

static dispatch_queue_t InstanceTrackingQueue;
static CFMutableArrayRef LiveInstances;

extern void OUILogOperationQueues(void);

static id (*_original_operationQueue_allocWithZone)(Class cls, SEL _cmd, NSZone *zone) = NULL;
static id _replacement_operationQueue_allocWithZone(Class cls, SEL _cmd, NSZone *zone)
{
    id queue = _original_operationQueue_allocWithZone(cls, _cmd, zone);
    
    void *ptr = queue; // don't retain this in the block.
    dispatch_async(InstanceTrackingQueue, ^{
        CFArrayAppendValue(LiveInstances, ptr);
    });
    
    return queue;
}

static unsigned OperationBacktraceKey;

static id (*_original_operation_allocWithZone)(Class cls, SEL _cmd, NSZone *zone) = NULL;
static id _replacement_operation_allocWithZone(Class cls, SEL _cmd, NSZone *zone)
{
    id operation = _original_operation_allocWithZone(cls, _cmd, zone);
    
    // Attach the callstack where operations were created (presuming this is close to where they were added, but we could switch to that instead).
    NSArray *symbols = [NSThread callStackSymbols];
    NSString *stackTrace = [symbols componentsJoinedByString:@"\n"];
    objc_setAssociatedObject(operation, &OperationBacktraceKey, stackTrace, OBJC_ASSOCIATION_RETAIN);
    
    return operation;
}

static void (*_original_operationQueue_dealloc)(id self, SEL _cmd) = NULL;
static void _replacement_operationQueue_dealloc(id self, SEL _cmd)
{
    void *ptr = self; // don't retain this in the block; especially important in -dealloc

    dispatch_async(InstanceTrackingQueue, ^{
        CFIndex idx = CFArrayGetFirstIndexOfValue(LiveInstances, CFRangeMake(0, CFArrayGetCount(LiveInstances)), ptr);
        assert(idx != kCFNotFound);
        CFArrayRemoveValueAtIndex(LiveInstances, idx);
    });
    
    _original_operationQueue_dealloc(self, _cmd);
}

static void _trackOperationQueues(void) __attribute__((constructor));
static void _trackOperationQueues(void)
{
    CFArrayCallBacks callbacks = {0};
    LiveInstances = CFArrayCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    
    Class NSOperationQueue = objc_getClass("NSOperationQueue");
    _original_operationQueue_allocWithZone = (typeof(_original_operationQueue_allocWithZone))OBReplaceMethodImplementation(object_getClass(NSOperationQueue), @selector(allocWithZone:), (IMP)_replacement_operationQueue_allocWithZone);
    _original_operationQueue_dealloc = (typeof(_original_operationQueue_dealloc))OBReplaceMethodImplementation(NSOperationQueue, @selector(dealloc), (IMP)_replacement_operationQueue_dealloc);
    
    Class NSOperation = objc_getClass("NSOperation");
    _original_operation_allocWithZone = (typeof(_original_operation_allocWithZone))OBReplaceMethodImplementation(object_getClass(NSOperation), @selector(allocWithZone:), (IMP)_replacement_operation_allocWithZone);

    InstanceTrackingQueue = dispatch_queue_create("com.omnigroup.LiveInstanceTracking", NULL);
    
    NSLog(@"instance tracking on %p", OUILogOperationQueues); // avoiding this being optimized out
}

static NSString *DotQuotedString(NSString *string)
{
    string = [string stringByReplacingAllOccurrencesOfString:@"\\" withString:@"\\\\"]; // quote any backslashes
    string = [string stringByReplacingAllOccurrencesOfString:@"\"" withString:@"\\\""]; // quote any doublequotes
    
    return string;
}

void OUILogOperationQueues(void)
{
    dispatch_sync(InstanceTrackingQueue, ^{
        // This presumes the application is deadlocked; otherwise we may get inconsistent information as the graph evolves.
        
        NSMutableString *graph = [NSMutableString string];
        [graph appendString:@"graph NSOperationQueues {\n"];
        {
            // Queues and their operations
            for (NSOperationQueue *operationQueue in (NSArray *)LiveInstances) {
                // Only emit queues with operations to get rid of cruft
                NSArray *operations = [operationQueue operations];
                if ([operations count] == 0)
                    continue;
                
                NSString *label = operationQueue.name;
                
                if ([operationQueue isSuspended])
                    label = [label stringByAppendingString:@" SUSPENDED"];
                
                NSInteger maxConcurrent = [operationQueue maxConcurrentOperationCount];
                if (maxConcurrent != NSOperationQueueDefaultMaxConcurrentOperationCount) {
                    label = [label stringByAppendingFormat:@" MAX:%ld", maxConcurrent];
                }
                
                [graph appendFormat:@"\tq%p [label=\"%@\"];\n", operationQueue, DotQuotedString(label)];
                
                NSOperation *previousOp = nil;
                for (NSOperation *op in operations) {
                    NSString *color;
                    
                    if ([op isExecuting])
                        color = @"lightgreen";
                    else if ([op isFinished])
                        color = @"lightblue";
                    else if ([op isReady])
                        color = @"white";
                    else if ([op isCancelled])
                        color = @"darkgray";
                    else
                        color = @"lightgray";
                    
                    NSString *operationLabel = objc_getAssociatedObject(op, &OperationBacktraceKey);
                    
                    [graph appendFormat:@"\top%p [shape=box,color=%@,label=\"%@\"];\n", op, color, DotQuotedString(operationLabel)];
                    [graph appendFormat:@"\tq%p -> op%p [arrowhead=normal];\n", operationQueue, op];
                    
                    if (previousOp) {
                        // Ordering is a partial dependency, depending on dispatch width.
                        [graph appendFormat:@"\top%p -> op%p [arrowhead=normal,style=dashed];\n", previousOp, op];
                    }
                    previousOp = op;
                }
            }
            
            // Operation dependencies
            for (NSOperationQueue *operationQueue in (NSArray *)LiveInstances) {
                for (NSOperation *op in [operationQueue operations]) {
                    for (NSOperation *dependency in op.dependencies) {
                        [graph appendFormat:@"\top%p -> op%p;\n", op, dependency];
                    }
                }
            }
        }
        [graph appendString:@"}\n"];
        
        NSLog(@"\n%@\n", graph);
        
        NSURL *graphURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"NSOperationQueues.dot"];
        NSData *graphData = [graph dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        if (![graphData writeToURL:graphURL options:0 error:&error])
            NSLog(@"Unable to write to %@: %@", graphURL, [error toPropertyList]);
        else
            NSLog(@"Graph written to %@", graphURL);
    });
}

#endif
