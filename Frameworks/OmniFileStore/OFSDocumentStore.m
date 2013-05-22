// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStore.h>

#import <OmniFileStore/OFSDocumentStoreDelegate.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniFileStore/OFSDocumentStoreLocalDirectoryScope.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFileStore/Errors.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFUTI.h>

#import "OFSDocumentStoreItem-Internal.h"
#import "OFSDocumentStoreFileItem-Internal.h"
#import "OFSDocumentStore-Internal.h"

#import <Foundation/NSOperation.h>
#import <Foundation/NSFileCoordinator.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <CoreServices/CoreServices.h>
#else
#import <MobileCoreServices/MobileCoreServices.h>
#endif

#import <sys/stat.h> // For S_IWUSR

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

RCS_ID("$Id$");

OBDEPRECATED_METHOD(-createNewDocument:); // -createNewDocumentInScope:completionHandler:
OBDEPRECATED_METHOD(-urlForNewDocumentOfType:); // could write a wrapper that asks the scope, but it has this now.
OBDEPRECATED_METHOD(-documentStore:scannedFileItems:); // -documentStore:addedFileItems:

@implementation OFSDocumentStore
{
    // NOTE: There is no setter for this; we currently make some calls to the delegate from a background queue and just use the ivar.
    __weak id <OFSDocumentStoreDelegate> _weak_delegate;
    
    NSMutableArray *_afterInitialDocumentScanActions;
    
    BOOL _isScanningItems;
    NSUInteger _deferScanRequestCount;
    NSMutableArray *_deferredScanCompletionHandlers;
    
    NSOperationQueue *_actionOperationQueue;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    // Make sure apps clean up their plists
    OBASSERT([[[NSBundle mainBundle] infoDictionary] objectForKey:@"NSUbiquitousDisplaySet"] == nil);
    OBASSERT([[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIApplicationCloudID"] == nil);
    OBASSERT([[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIApplicationCloudContainerID"] == nil);
    OBASSERT([[NSUserDefaults standardUserDefaults] objectForKey:@"OFSDocumentStoreUserWantsUbiquity"] == nil);
    OBASSERT([[NSUserDefaults standardUserDefaults] objectForKey:@"OFSDocumentStoreDisableUbiquity"] == nil);
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

- (void)applicationDidEnterBackground;
{
    DEBUG_STORE(@"Application did enter background");

    /*
     NOTE: We used to temporarily remove the file items as file presenters here. This hits race conditions though.
     In particular, if a document is open and edited and the app is backgrounded, the save will send -relinquishPresentedItemToWriter: to the file item. The save is async and thus this method could get called while it was ongoing. Removing the file item as a presenter while it was in the middle of -relinquishPresentedItemToWriter: would make the reacquire block never get called!
     Instead, we now leave the file items registered all the time. This does mean that when we get foregrounded again, if syncing has been disabled, the file items may get poked with deletions/moves as the underlying files disappear.
     */
}

- (void)applicationWillEnterForegroundWithCompletionHandler:(void (^)(void))completionHandler;
{
    DEBUG_STORE(@"Application will enter foreground");
    
    if (completionHandler)
        completionHandler();
}

#endif

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

static unsigned ScopeContext;

- initWithDelegate:(id <OFSDocumentStoreDelegate>)delegate;
{
    OBPRECONDITION(delegate);
    OBPRECONDITION([NSThread isMainThread]); // Signing up for KVO, starting metadata queries
    
    if (!(self = [super init]))
        return nil;

    _weak_delegate = delegate;
    
    _scopes = [[NSArray alloc] init];
    
    _actionOperationQueue = [[NSOperationQueue alloc] init];
    [_actionOperationQueue setName:@"OFSDocumentStore file actions"];
    [_actionOperationQueue setMaxConcurrentOperationCount:1];
    
    return self;
}

- (void)dealloc;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#endif
    
    for (OFSDocumentStoreScope *scope in _scopes) {
        [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, hasFinishedInitialScan) context:&ScopeContext];
        [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) context:&ScopeContext];
    }
    
    OBASSERT([_actionOperationQueue operationCount] == 0);
}

- (void)addScope:(OFSDocumentStoreScope *)scope;
{
    OBPRECONDITION(scope.documentStore == self); // should be expecting to be added to us
    OBPRECONDITION([_scopes indexOfObjectIdenticalTo:scope] == NSNotFound);
    OBPRECONDITION([_scopes indexOfObjectPassingTest:^BOOL(OFSDocumentStoreScope *otherScope, NSUInteger idx, BOOL *stop) {
        return OFISEQUAL(scope.identifier, otherScope.identifier); // Identifiers should be unique
    }] == NSNotFound);
    
    [scope addObserver:self forKeyPath:OFValidateKeyPath(scope, hasFinishedInitialScan) options:0 context:&ScopeContext];
    [scope addObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) options:0 context:&ScopeContext];

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if ([scope isTrash])
        _trashScope = scope;
#endif

    NSArray *scopes = [_scopes arrayByAddingObject:scope];
    [self willChangeValueForKey:OFValidateKeyPath(self, scopes)];
    _scopes = [scopes copy];
    [self didChangeValueForKey:OFValidateKeyPath(self, scopes)];

    if ([scope respondsToSelector:@selector(wasAddedToDocumentStore)])
        [scope wasAddedToDocumentStore];
}

- (void)removeScope:(OFSDocumentStoreScope *)scope;
{
    OBPRECONDITION(scope.documentStore == self); // should be expecting to be added to us
    
    NSUInteger scopeIndex = [_scopes indexOfObjectIdenticalTo:scope];
    if (scopeIndex == NSNotFound) {
        OBASSERT_NOT_REACHED("Removing scope that wasn't added");
        return;
    }
    
    if ([scope respondsToSelector:@selector(willBeRemovedFromDocumentStore)])
        [scope willBeRemovedFromDocumentStore];

    [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, hasFinishedInitialScan) context:&ScopeContext];
    [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) context:&ScopeContext];
    
    NSMutableArray *scopes = [_scopes mutableCopy];
    [scopes removeObjectAtIndex:scopeIndex];
    
    [self willChangeValueForKey:OFValidateKeyPath(self, scopes)];
    _scopes = [scopes copy];
    [self didChangeValueForKey:OFValidateKeyPath(self, scopes)];

    [self _updateMergedFileItems];
}

- (OFSDocumentStoreScope *)defaultUsableScope;
{
    // Return the first working scope. Callers can remember a different scope in a preference (and we presume the more important a scope is to the caller, the closer to the front of the array it is).

    for (OFSDocumentStoreScope *candidate in _scopes)
        if (candidate.documentsURL)
            return candidate;
        else
            OBASSERT_NOT_REACHED("We should no longer have scopes with nil docuemnt URLs");
    
    OBASSERT_NOT_REACHED("No usable scopes registered");
    return nil;
}

- (OFSDocumentStoreScope *)scopeForFileName:(NSString *)fileName inFolder:(NSString *)folder;
{
    OBPRECONDITION([NSThread isMainThread]);

    for (OFSDocumentStoreScope *scope in _scopes) {
        if ([scope fileItemWithName:fileName inFolder:folder])
            return scope;
    }
    
    return nil;
}

- (Class)fileItemClassForURL:(NSURL *)fileURL; // Defaults to asking the delegate. The URL may not exist yet!
{
    id <OFSDocumentStoreDelegate> delegate = _weak_delegate;
    OBPRECONDITION(delegate);
    
    // Nil means we don't want it to show up.
    return [delegate documentStore:self fileItemClassForURL:fileURL];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (BOOL)canViewFileTypeWithIdentifier:(NSString *)fileType;
{
    id <OFSDocumentStoreDelegate> delegate = _weak_delegate;
    OBPRECONDITION(delegate);

    return [delegate documentStore:self canViewFileTypeWithIdentifier:fileType];
}

- (OFSDocumentStoreFileItem *)preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;
{
    id <OFSDocumentStoreDelegate> delegate = _weak_delegate;

    if (delegate && [delegate respondsToSelector:@selector(documentStore:preferredFileItemForNextAutomaticDownload:)])
        return [delegate documentStore:self preferredFileItemForNextAutomaticDownload:fileItems];
    return nil;
}
#endif

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;
{
    if (!_afterInitialDocumentScanActions)
        _afterInitialDocumentScanActions = [[NSMutableArray alloc] init];
    [_afterInitialDocumentScanActions addObject:[action copy]];
     
    // ... might be able to call it right now
    [self _flushAfterInitialDocumentScanActions];
}

// Allow external objects to synchronize with our operations.
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;
{
    OBPRECONDITION(_actionOperationQueue);
    
    OBFinishPortingLater("Get rid of the queue in this class now that scopes have queues?");
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

#if 0
- (void)moveDocumentFromURL:(NSURL *)fromURL toScope:(OFSDocumentStoreScope *)scope inFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // We'll invoke the completion handler on the main thread
    
    if (!completionHandler)
        completionHandler = ^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
            NSLog(@"Error adding document from %@: %@", fromURL, [error toPropertyList]);
        };
    
    completionHandler = [completionHandler copy]; // preserve scope
    
    // Convenience for dispatching the completion handler to the main queue.
    void (^callCompletionHandlerOnMainQueue)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) = ^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
        OBPRECONDITION(![NSThread isMainThread]);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(duplicateFileItem, error);
        }];
    };
    callCompletionHandlerOnMainQueue = [callCompletionHandlerOnMainQueue copy];
    
    if (![scope documentsURL:NULL])
        scope = self.defaultScope;
    
    // We cannot decide on the destination URL w/o synchronizing with the action queue. In particular, if you try to duplicate "A" and "A 2", both operations could pick "A 3".
    [self performAsynchronousFileAccessUsingBlock:^{
        NSURL *toURL = nil;
        NSString *fileName = [fromURL lastPathComponent];
        NSString *baseName = nil;
        NSUInteger counter;
        [[fileName stringByDeletingPathExtension] splitName:&baseName andCounter:&counter];
        
        fileName = [self _availableFileNameWithBaseName:baseName extension:[fileName pathExtension] counter:&counter scope:scope];
        
        NSError *error = nil;
        toURL = [self _urlForScope:scope folderName:folderName fileName:fileName error:&error];
        if (!toURL) {
            callCompletionHandlerOnMainQueue(nil, error);
            return;
        }
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block BOOL success = NO;
        __block NSError *innerError = nil;
        
        [coordinator coordinateWritingItemAtURL:fromURL options:NSFileCoordinatorWritingForMoving
                               writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing
                                          error:&error byAccessor:
         ^(NSURL *newSourceURL, NSURL *newDestinationURL) {
             NSError *moveError = nil;
             if (![[NSFileManager defaultManager] moveItemAtURL:newSourceURL toURL:newDestinationURL error:&moveError]) {
                 NSLog(@"Error moving %@ -> %@: %@", newSourceURL, newDestinationURL, [moveError toPropertyList]);
                 innerError = moveError;
                 return;
             }
             
             [coordinator itemAtURL:newSourceURL didMoveToURL:newDestinationURL];
             success = YES;
         }];
        
        
        if (!success) {
            OBASSERT(error || innerError);
            if (innerError)
                error = innerError;
        }
                
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (success)
                _addItemAndNotifyHandler(self, completionHandler, toURL, scope.isUbiquitous, nil);
            else
                _addItemAndNotifyHandler(self, completionHandler, nil, NO, error);
        }];
    }];
}
#endif

#if 0
- (void)moveItemsAtURLs:(NSSet *)urls toCloudFolderInScope:(OFSDocumentStoreScope *)ubiquitousScope withName:(NSString *)folderNameOrNil completionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBASSERT(ubiquitousScope);
    
    NSMutableDictionary *movedURLs = [NSMutableDictionary dictionary];
    NSMutableDictionary *errorURLs = [NSMutableDictionary dictionary];
    
    // Early out for no-ops
    if ([urls count] == 0) {
        if (completionHandler)
            completionHandler(movedURLs, errorURLs);
        return;
    }
    
    // <bug:///80920> (Can we rename iCloud items that aren't yet fully (or at all) downloaded? [engineering])
    
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
        NSURL *containerURL = [ubiquitousScope documentsURL:&error];
        if (!containerURL) {
            NSLog(@"-moveItemsAtURLs:... failed to get ubiquity container URL: %@", error);
            if (completionHandler)
                completionHandler(movedURLs, errorURLs);
            return;
        }
        
        // TODO: We might be creating a directory in the ubiquity container. To we need to do a coordinated read/write of this non-document directory in case there is an incoming folder creation from the cloud? This seems like a pretty small hole, but still...
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
                
                NSLog(@"-moveItemsAtURLs:... failed to create cloud directory %@: %@", destinationDirectoryURL, error);
                if (completionHandler)
                    completionHandler(movedURLs, errorURLs);
                return;
            }
        }
    }
    
    OBASSERT([_actionOperationQueue maxConcurrentOperationCount] == 1); // Or else we'll try to mutate movedURLs and errorURLs from multiple threads simultaneously
    
    [_actionOperationQueue addOperationWithBlock:^{
        // Theoretically, we could create a temporary concurrent queue and perform these moves simultaneously, but then I'd have to synchronize on collecting the movedURLs and errorURLs.
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
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self scanItemsWithCompletionHandler:^{
                    if (completionHandler)
                        completionHandler(movedURLs, errorURLs);
                }];
            }];
        }
    }];
    
    DEBUG_CLOUD(@"-moveItemsAtURLs:... is returning");
}
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)moveFileItems:(NSSet *)fileItems toScope:(OFSDocumentStoreScope *)scope completionHandler:(void (^)(OFSDocumentStoreFileItem *failingItem, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // since we'll send the completion handler back to the main thread, make sure we came from there
    OBPRECONDITION(scope);
    
    completionHandler = [completionHandler copy];
        
    for (OFSDocumentStoreFileItem *fileItem in fileItems) {
        __autoreleasing NSError *error;
        OBASSERT(fileItem.scope != scope, "Don't try to move items within the same scope");
        if (![fileItem.scope prepareToMoveFileItem:fileItem toScope:scope error:&error]) {
            if (completionHandler)
                completionHandler(fileItem, error);
            return;
        }
    }

    [scope moveFileItems:fileItems completionHandler:^(OFSDocumentStoreFileItem *failingFileItem, NSError *errorOrNil){
        OBASSERT([NSThread isMainThread]);
        if (completionHandler)
            completionHandler(failingFileItem, errorOrNil);
    }];
}

#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#if 0
- (void)makeGroupWithFileItems:(NSSet *)fileItems completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
{
    OBFinishPorting;
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with document store notifications about updating items
    
    OBFinishPortingLater("Should we rescan before finding an available path, or depend on the caller to know things are up to date?");
    OBPRECONDITION(_fileItems); // Make sure we've done a local scan. It might be out of date, so maybe we should scan here too.
    
    OBFinishPorting; // Add a hasFinishedInitialQuery property to the concrete scope protocol?
    //OBPRECONDITION(self.hasFinishedInitialMetdataQuery); // We can't unique against the cloud until we know what is there

    // Find an available folder placeholder name. First, build up a list of all the folder URLs we know about based on our file items.
    NSMutableSet *folderFilenames = [NSMutableSet set];
    for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
        NSURL *containingURL = [fileItem.fileURL URLByDeletingLastPathComponent];
        if (OFSIsFolder(containingURL)) // Might be ~/Documents or a ubiquity container
            [folderFilenames addObject:[containingURL lastPathComponent]];
    }
    
    NSString *baseName = NSLocalizedStringFromTableInBundle(@"Folder", @"OmniFileStore", OMNI_BUNDLE, @"Base name for document picker folder names");
    NSUInteger counter = 0;
    NSString *folderName = _availableName(folderFilenames, baseName, OFSDocumentStoreFolderPathExtension, &counter);
    
    [self moveItems:fileItems toFolderNamed:folderName completionHandler:completionHandler];
}
#endif

#if 0
- (void)moveItems:(NSSet *)fileItems toFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
{
    // Disabled for now. This needs to be updated for the renaming changes, to do the coordinated moves on the background queue, and to wait for the individual moves to fire before firing the group completion handler (if possible).
    OBFinishPortingLater("No group support");
    if (completionHandler)
        completionHandler(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
                          
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with document store notifications about updating items, and this is the queue we'll invoke the completion handler on.
    
    OBFinishPortingLater("Can we rename OmniPresence items that aren't yet fully (or at all) downloaded?");

    // capture scope (might not be necessary since we aren't currently asynchronous here).
    completionHandler = [[completionHandler copy] autorelease];

    // This is similar to the document renaming path, but we already know that no other renaming should be needed (and we are doing multiple items).    
    for (OFSDocumentStoreFileItem *fileItem in fileItems) {
        NSURL *sourceURL = fileItem.fileURL;

        // Make a destination in a folder under the same container scope as the original item
        NSURL *destinationDirectoryURL;
        {
            NSError *error = nil;
            NSURL *containerURL = [fileItem.scope documentsURL:&error];
            if (!containerURL) {
                if (completionHandler)
                    completionHandler(nil, error);
                return;
            }
            
            // TODO: We might be creating a directory in the ubiquity container. To we need to do a coordinated read/write of this non-document directory in case there is an incoming folder creation from the cloud? This seems like a pretty small hole, but still...
            destinationDirectoryURL = [containerURL URLByAppendingPathComponent:folderName isDirectory:YES];
            if (![[NSFileManager defaultManager] directoryExistsAtPath:[destinationDirectoryURL path]]) {
                if (![[NSFileManager defaultManager] createDirectoryAtURL:destinationDirectoryURL withIntermediateDirectories:YES/*shouldn't be necessary...*/ attributes:nil error:&error]) {
                    if (completionHandler)
                        completionHandler(nil, error);
                    return;
                }
            }
        }
        
        NSURL *destinationURL = _destinationURLForMove(fileItem, sourceURL, destinationDirectoryURL, [sourceURL lastPathComponent]);
        
        OBFinishPortingLater("This should be jumping to our background queue once we get back to working on folder support.");
        _coordinatedMoveItem(self, fileItem, sourceURL, destinationURL, nil/*completionQueue*/, nil/*completionHandler*/);
    }
    
    [self scanItemsWithCompletionHandler:^{
        OFSDocumentStoreGroupItem *group = [_groupItemByName objectForKey:folderName];
        OBASSERT(group);
        
        if (completionHandler)
            completionHandler(group, nil);
    }];
}
#endif

#endif

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Capture state
    completionHandler = [completionHandler copy];
    
    if (_isScanningItems || _deferScanRequestCount > 0) {
        DEBUG_STORE(@"Deferring scan, _isScanningItems:%d _deferScanRequestCount:%lu completionHandler:%@", _isScanningItems, _deferScanRequestCount, completionHandler);
        
        if (_deferScanRequestCount > 0 && completionHandler == nil) {
            // Can totally skip this one. We'll do a scan when the counter goes to zero
            return;
        }
        
        // There is an in-flight scan already. We want to get its state back before we start another scanning operaion.
        if (!_deferredScanCompletionHandlers)
            _deferredScanCompletionHandlers = [[NSMutableArray alloc] init];
        if (!completionHandler)
            completionHandler = ^{}; // want to make sure a scan actually happens
        [_deferredScanCompletionHandlers addObject:completionHandler];
        return;
    }
    
    _isScanningItems = YES;
        
    [self performAsynchronousFileAccessUsingBlock:^{
        OBFinishPortingLater("Not scanning here...");
        
        if (completionHandler)
            [[NSOperationQueue mainQueue] addOperationWithBlock:completionHandler];
    }];
}

- (void)startDeferringScanRequests;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    _deferScanRequestCount++;
    DEBUG_STORE(@"_deferScanRequestCount = %ld", _deferScanRequestCount);
}

- (void)stopDeferringScanRequests:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_deferScanRequestCount > 0);
    
    if (_deferScanRequestCount == 0) {
        OBASSERT_NOT_REACHED("Underflow scan defer count");
        if (completionHandler)
            completionHandler();
    }
    
    _deferScanRequestCount--;
    DEBUG_STORE(@"_deferScanRequestCount = %ld", _deferScanRequestCount);

    if (_deferScanRequestCount == 0) {
        [self scanItemsWithCompletionHandler:completionHandler];
    }
}

- (OFSDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
{
    // We have a union of the scanned items, but it is better to let the scopes handle this than to have the logic in two spots.
    for (OFSDocumentStoreScope *scope in _scopes) {
        OFSDocumentStoreFileItem *fileItem = [scope fileItemWithURL:url];
        if (fileItem)
            return fileItem;
    }
    return nil;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSString *)documentTypeForNewFiles;
{
    id <OFSDocumentStoreDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(documentStoreDocumentTypeForNewFiles:)])
        return [delegate documentStoreDocumentTypeForNewFiles:self];
    
    if ([delegate respondsToSelector:@selector(documentStoreEditableDocumentTypes:)]) {
        NSArray *editableTypes = [delegate documentStoreEditableDocumentTypes:self];
        
        OBASSERT([editableTypes count] < 2); // If there is more than one, we might pick the wrong one.
        
        return [editableTypes lastObject];
    }
    
    return nil;
}

- (void)createNewDocumentInScope:(OFSDocumentStoreScope *)scope completionHandler:(void (^)(OFSDocumentStoreFileItem *createdFileItem, NSError *error))handler;
{
    NSString *documentType = [self documentTypeForNewFiles];

    OFSDocumentStoreScopeDocumentCreationAction action = ^(void (^actionHandler)(NSURL *targetURL, NSError *errorOrNil)){
        actionHandler = [actionHandler copy];
        
        id <OFSDocumentStoreDelegate> delegate = _weak_delegate;

        NSString *baseName = [delegate documentStoreBaseNameForNewFiles:self];
        if (!baseName) {
            OBASSERT_NOT_REACHED("No delegate? You probably want one to provide a better base untitled document name.");
            baseName = @"My Document";
        }
        
        OBFinishPortingLater("Allow creating documents in folders");
        NSURL *newDocumentURL = [scope urlForNewDocumentInFolderAtURL:nil baseName:baseName fileType:documentType];

        [delegate createNewDocumentAtURL:newDocumentURL completionHandler:^(NSError *errorOrNil){
            if (actionHandler) {
                if (errorOrNil)
                    actionHandler(nil, errorOrNil);
                else
                    actionHandler(newDocumentURL, nil);
            }
        }];
    };
    [scope performDocumentCreationAction:action handler:handler];
}

#endif

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (context == &ScopeContext) {
        OFSDocumentStoreScope *scope = object;
        OBASSERT([scope isKindOfClass:[OFSDocumentStoreScope class]]);
        
        if ([keyPath isEqualToString:OFValidateKeyPath(scope,fileItems)]) {
            [self _updateMergedFileItems];
            return;
        }
        if ([keyPath isEqualToString:OFValidateKeyPath(scope,hasFinishedInitialScan)]) {
            [self _flushAfterInitialDocumentScanActions];
            return;
        }
        
        OBASSERT_NOT_REACHED("Unhandled key");
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Private

- (void)_updateMergedFileItems;
{
    NSMutableSet *mergedFileItems = [[NSMutableSet alloc] init];
    for (OFSDocumentStoreScope *scope in _scopes)
        [mergedFileItems unionSet:scope.fileItems];

    if (OFNOTEQUAL(_mergedFileItems, mergedFileItems)) {
        NSSet *addedFileItems;
        
        id <OFSDocumentStoreDelegate> delegate = self->_weak_delegate;

        if ([delegate respondsToSelector:@selector(documentStore:addedFileItems:)]) {
            NSMutableSet *items = [[NSMutableSet alloc] initWithSet:mergedFileItems];
            [items minusSet:_mergedFileItems];
            if ([items count])
                addedFileItems = [items copy];
        }
        
        [self willChangeValueForKey:OFValidateKeyPath(self, mergedFileItems)];
        _mergedFileItems = [[NSMutableSet alloc] initWithSet:mergedFileItems];
        [self didChangeValueForKey:OFValidateKeyPath(self, mergedFileItems)];
        
        if (addedFileItems)
            [delegate documentStore:self addedFileItems:addedFileItems];
    }
    
    [self _flushAfterInitialDocumentScanActions];
    
    // We are done scanning -- see if any other scan requests have piled up while we were running and start one if so.
    // We do need to rescan (rather than just calling all the queued completion handlers) since the caller might have queued more filesystem changing operations between the two scan requests.
    _isScanningItems = NO;
    if (_deferScanRequestCount == 0 && [_deferredScanCompletionHandlers count] > 0) {
        void (^nextCompletionHandler)(void) = [_deferredScanCompletionHandlers objectAtIndex:0];
        [_deferredScanCompletionHandlers removeObjectAtIndex:0];
        [self scanItemsWithCompletionHandler:nextCompletionHandler];
    }
}

- (BOOL)_allScopesHaveFinishedInitialScan;
{
    for (OFSDocumentStoreScope *scope in _scopes) {
        if (!scope.hasFinishedInitialScan)
            return NO;
    }
    
    return YES;
}

- (void)_flushAfterInitialDocumentScanActions;
{
    if (![self _allScopesHaveFinishedInitialScan])
        return;
    
    if (_afterInitialDocumentScanActions) {
        NSArray *actions = _afterInitialDocumentScanActions;
        _afterInitialDocumentScanActions = nil;
        [self _performActions:actions];
    }
}

- (void)_performActions:(NSArray *)actions;
{
    // The initial scan may have been *started* due to the metadata query finishing, but we do the scan of the filesystem on a background thread now. So, synchronize with that and then invoke these actions on the main thread.
    [_actionOperationQueue addOperationWithBlock:^{
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            for (void (^action)(void) in actions)
                action();
        }];
    }];
}


// Called by file items when they move -- we just dispatch to our delegate (on iOS this lets the document picker move the previews along for local and incoming moves).
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    id <OFSDocumentStoreDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentStore:fileWithURL:andDate:didMoveToURL:)])
        [delegate documentStore:self fileWithURL:oldURL andDate:date didMoveToURL:newURL];
}

- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    id <OFSDocumentStoreDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentStore:fileWithURL:andDate:didCopyToURL:andDate:)])
        [delegate documentStore:self fileWithURL:oldURL andDate:date didCopyToURL:newURL andDate:newDate];
}

@end
