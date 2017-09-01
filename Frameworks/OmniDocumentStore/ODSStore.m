// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSStore.h>

#import <OmniDocumentStore/ODSStoreDelegate.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniDocumentStore/ODSLocalDirectoryScope.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/OFWeakReference.h>

#import "ODSItem-Internal.h"
#import "ODSFileItem-Internal.h"
#import "ODSStore-Internal.h"

#import <Foundation/NSOperation.h>
#import <Foundation/NSFileCoordinator.h>
#import <MobileCoreServices/MobileCoreServices.h>

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

OBDEPRECATED_METHOD(-createNewDocument:);
OBDEPRECATED_METHOD(-createdNewDocument:templateURL:completionHandler:);
OBDEPRECATED_METHOD(-urlForNewDocumentOfType:); // could write a wrapper that asks the scope, but it has this now.
OBDEPRECATED_METHOD(-documentStore:scannedFileItems:); // -documentStore:addedFileItems:

OBDEPRECATED_METHOD(-documentStore:fileWithURL:andDate:willMoveToURL:);
OBDEPRECATED_METHOD(-documentStore:fileWithURL:andDate:finishedMoveToURL:successfully:);


NSString *ODSPathExtensionForFileType(NSString *fileType, BOOL *outIsPackage)
{
    OBPRECONDITION(fileType);
    
    NSString *extension = OFPreferredPathExtensionForUTI(fileType);
    OBASSERT(extension);
    OBASSERT([extension hasPrefix:@"dyn."] == NO, "UTI not registered in the Info.plist?");
    
    if (outIsPackage) {
        BOOL isPackage = OFTypeConformsTo(fileType, kUTTypePackage);
        OBASSERT_IF(!isPackage, !OFTypeConformsTo(fileType, kUTTypeFolder), "Types should be declared as conforming to kUTTypePackage, not kUTTypeFolder");
        *outIsPackage = isPackage;
    }
    
    return extension;
}

@implementation ODSStore
{
    // NOTE: There is no setter for this; we currently make some calls to the delegate from a background queue and just use the ivar.
    __weak id <ODSStoreDelegate> _weak_delegate;
    
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

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

static unsigned ScopeContext;

- initWithDelegate:(id <ODSStoreDelegate>)delegate;
{
    OBPRECONDITION(delegate);
    OBPRECONDITION([NSThread isMainThread]); // Signing up for KVO, starting metadata queries
    
    if (!(self = [super init]))
        return nil;

    _weak_delegate = delegate;
    
    _scopes = [[NSArray alloc] init];
    
    _actionOperationQueue = [[NSOperationQueue alloc] init];
    [_actionOperationQueue setName:@"ODSStore file actions"];
    [_actionOperationQueue setMaxConcurrentOperationCount:1];
#ifdef OMNI_ASSERTIONS_ON
#define BadDelegate(sel) OBASSERT_NOT_IMPLEMENTED(_weak_delegate, sel)
    BadDelegate(createNewDocumentAtURL:completionHandler:); // Use the createdNewDocument:templateURL:completionHandler: instead
    BadDelegate(createNewDocumentAtURL:completionHandler:); // Use the createdNewDocument:templateURL:completionHandler: instead
#endif

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    for (ODSScope *scope in _scopes) {
        [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, hasFinishedInitialScan) context:&ScopeContext];
        [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) context:&ScopeContext];
    }
    
    OBASSERT([_actionOperationQueue operationCount] == 0);
}

- (void)addScope:(ODSScope *)scope;
{
    OBPRECONDITION(scope.documentStore == self); // should be expecting to be added to us
    OBPRECONDITION([_scopes indexOfObjectIdenticalTo:scope] == NSNotFound);
    OBPRECONDITION([_scopes indexOfObjectPassingTest:^BOOL(ODSScope *otherScope, NSUInteger idx, BOOL *stop) {
        return OFISEQUAL(scope.identifier, otherScope.identifier); // Identifiers should be unique
    }] == NSNotFound);
    
    [scope addObserver:self forKeyPath:OFValidateKeyPath(scope, hasFinishedInitialScan) options:0 context:&ScopeContext];
    [scope addObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) options:0 context:&ScopeContext];

    if ([scope isTrash])
        _trashScope = scope;
    else if ([scope isTemplate])
        _templateScope = scope;

    NSArray *scopes = [_scopes arrayByAddingObject:scope];
    [self willChangeValueForKey:OFValidateKeyPath(self, scopes)];
    _scopes = [scopes copy];
    [self didChangeValueForKey:OFValidateKeyPath(self, scopes)];

    if ([scope respondsToSelector:@selector(wasAddedToDocumentStore)])
        [scope wasAddedToDocumentStore];
}

- (void)removeScope:(ODSScope *)scope;
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

- (ODSScope *)defaultUsableScope;
{
    // Return the first working scope. Callers can remember a different scope in a preference (and we presume the more important a scope is to the caller, the closer to the front of the array it is).

    for (ODSScope *candidate in _scopes)
        if (candidate.documentsURL)
            return candidate;
        else
            OBASSERT_NOT_REACHED("We should no longer have scopes with nil docuemnt URLs");
    
    OBASSERT_NOT_REACHED("No usable scopes registered");
    return nil;
}

- (Class)fileItemClassForURL:(NSURL *)fileURL; // Defaults to asking the delegate. The URL may not exist yet!
{
    id <ODSStoreDelegate> delegate = _weak_delegate;
    OBPRECONDITION(delegate);
    
    // Nil means we don't want it to show up.
    return [delegate documentStore:self fileItemClassForURL:fileURL];
}

- (BOOL)canViewFileTypeWithIdentifier:(NSString *)fileType;
{
    id <ODSStoreDelegate> delegate = _weak_delegate;
    OBPRECONDITION(delegate);

    return [delegate documentStore:self canViewFileTypeWithIdentifier:fileType];
}

- (ODSFileItem *)preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;
{
    id <ODSStoreDelegate> delegate = _weak_delegate;

    if (delegate && [delegate respondsToSelector:@selector(documentStore:preferredFileItemForNextAutomaticDownload:)])
        return [delegate documentStore:self preferredFileItemForNextAutomaticDownload:fileItems];
    return nil;
}

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
    
    OBFinishPortingLater("<bug:///147878> (iOS-OmniOutliner Engineering: ODSStore.m, performAsynchronousFileAccessUsingBlock: Get rid of the queue in this class now that scopes have queues?)");
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

- (void)moveItems:(NSSet *)items fromScope:(ODSScope *)fromScope toScope:(ODSScope *)toScope inFolder:(ODSFolderItem *)parentFolder completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // since we'll send the completion handler back to the main thread, make sure we came from there
    OBPRECONDITION(fromScope);
    OBPRECONDITION([items all:^BOOL(ODSItem *item) { return item.scope == fromScope; }]);
    OBPRECONDITION(toScope);
    OBPRECONDITION(parentFolder.scope == toScope);
    
    completionHandler = [completionHandler copy];
    
    if (fromScope != toScope) {
        NSMutableArray *relinquishErrors = [[NSMutableArray alloc] init];

        for (ODSItem *item in items) {
            __autoreleasing NSError *error;
            if (![fromScope prepareToRelinquishItem:item error:&error])
                [relinquishErrors addObject:error];
        }

        if (relinquishErrors.count != 0) {
            if (completionHandler != NULL)
                completionHandler(nil, relinquishErrors);
            return;
        }

        [toScope takeItems:items toFolder:parentFolder ignoringFileItems:nil completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil) {
            OBASSERT([NSThread isMainThread]);
            [fromScope finishRelinquishingMovedItems:movedFileItems];
            if (completionHandler)
                completionHandler(movedFileItems, errorsOrNil);
        }];
    } else {
        [toScope moveItems:items toFolder:parentFolder completionHandler:^(NSSet *movedFileItems, NSArray *errorsOrNil){
            OBASSERT([NSThread isMainThread]);
            if (completionHandler)
                completionHandler(movedFileItems, errorsOrNil);
        }];
    }
}

- (void)makeFolderFromItems:(NSSet *)items inParentFolder:(ODSFolderItem *)parentFolder ofScope:(ODSScope *)scope completionHandler:(void (^)(ODSFolderItem *createdFolder, NSArray *errorsOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // since we'll send the completion handler back to the main thread, make sure we came from there
    OBPRECONDITION(scope);
    OBPRECONDITION(!parentFolder || parentFolder.relativePath);
    OBPRECONDITION([items all:^BOOL(ODSItem *item) { return item.scope == scope; }], "Can only create folders from items in the specified scope");

    completionHandler = [completionHandler copy];

    [scope makeFolderFromItems:items inParentFolder:parentFolder completionHandler:^(ODSFolderItem *createdFolder, NSArray *errorsOrNil){
        OBASSERT([NSThread isMainThread]);
        if (completionHandler)
            completionHandler(createdFolder, errorsOrNil);
    }];
}

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
        OBFinishPortingLater("<bug:///147936> (iOS-OmniOutliner Bug: Not scanning here... - in -[ODSStore scanItemsWithCompletionHandler:])");
        
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

- (ODSFileItem *)fileItemWithURL:(NSURL *)url;
{
    // We have a union of the scanned items, but it is better to let the scopes handle this than to have the logic in two spots.
    for (ODSScope *scope in _scopes) {
        ODSFileItem *fileItem = [scope fileItemWithURL:url];
        if (fileItem)
            return fileItem;
    }
    return nil;
}

- (NSString *)documentTypeForNewFilesOfType:(ODSDocumentType)type;
{
    id <ODSStoreDelegate> delegate = _weak_delegate;

    switch (type) {
        case ODSDocumentTypeNormal:
            if ([delegate respondsToSelector:@selector(documentStoreDocumentTypeForNewFiles:)])
                return [delegate documentStoreDocumentTypeForNewFiles:self];
            break;
        case ODSDocumentTypeTemplate:
            if ([delegate respondsToSelector:@selector(documentStoreDocumentTypeForNewTemplateFiles:)])
                return [delegate documentStoreDocumentTypeForNewTemplateFiles:self];
            break;
        case ODSDocumentTypeOther:
            if ([delegate respondsToSelector:@selector(documentStoreDocumentTypeForNewOtherFiles:)])
                return [delegate documentStoreDocumentTypeForNewOtherFiles:self];
            break;
        default:
            OBFinishPortingLater("Is there a new document type we don't know about?");
            break;
    }

    if ([delegate respondsToSelector:@selector(documentStoreEditableDocumentTypes:)]) {
        NSArray *editableTypes = [delegate documentStoreEditableDocumentTypes:self];

        OBASSERT([editableTypes count] < 2); // If there is more than one, we might pick the wrong one.

        return [editableTypes lastObject];
    }

    return nil;
}

- (NSString *)defaultFilenameForDocumentType:(ODSDocumentType)type isDirectory:(BOOL *)outIsDirectory;
{
    NSString *documentType = [self documentTypeForNewFilesOfType:type];
    
    id <ODSStoreDelegate> delegate = _weak_delegate;
    NSString *baseName;
    if (type == ODSDocumentTypeTemplate)
        baseName = [delegate documentStoreBaseNameForNewTemplateFiles:self];
    else
        baseName = [delegate documentStoreBaseNameForNewFiles:self];
    if (!baseName) {
        OBASSERT_NOT_REACHED("No delegate? You probably want one to provide a better base untitled document name.");
        baseName = @"My Document";
    }
    
    NSString *pathExtension = ODSPathExtensionForFileType(documentType, outIsDirectory);
    
    return [baseName stringByAppendingPathExtension:pathExtension];
}

- (NSString *)documentTypeForNewFiles;
{
    return [self documentTypeForNewFilesOfType:ODSDocumentTypeNormal];
}

- (NSURL *)temporaryURLForCreatingNewDocumentOfType:(ODSDocumentType)type;
{
    BOOL isDirectory;
    NSString *documentType = [self documentTypeForNewFilesOfType:type];
    NSString *pathExtension = ODSPathExtensionForFileType(documentType, &isDirectory);
    
    NSString *temporaryFilename = [OFXMLCreateID() stringByAppendingPathExtension:pathExtension];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:temporaryFilename] isDirectory:isDirectory];
}

- (void)moveNewTemporaryDocumentAtURL:(NSURL *)fileURL toScope:(ODSScope *)scope folder:(ODSFolderItem *)folder documentType:(ODSDocumentType)type completionHandler:(void (^)(ODSFileItem *createdFileItem, NSError *error))handler;
{
    NSString *documentType = [self documentTypeForNewFilesOfType:type];

    id <ODSStoreDelegate> delegate = _weak_delegate;
    NSString *baseName = nil;
    // LMTODO: incorporate "other"
    switch (type) {
        case ODSDocumentTypeTemplate:
            baseName = [delegate documentStoreBaseNameForNewTemplateFiles:self];
            break;
        case ODSDocumentTypeNormal:
            baseName = [delegate documentStoreBaseNameForNewFiles:self];
            break;
        case ODSDocumentTypeOther:
            if ([delegate respondsToSelector:@selector(documentStoreBaseNameForNewOtherFiles:)]) {
                baseName = [delegate documentStoreBaseNameForNewOtherFiles:self];
            } else {
                baseName = [delegate documentStoreBaseNameForNewFiles:self];
            }
            break;
        default:
            break;
    }
    if (!baseName) {
        OBASSERT_NOT_REACHED("No delegate? You probably want one to provide a better base untitled document name.");
        baseName = @"My Document";
    }
    
    [scope addDocumentInFolder:folder baseName:baseName fileType:documentType fromURL:fileURL option:ODSStoreAddByMovingTemporarySourceToAvailableDestinationURL completionHandler:handler];
}

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (context == &ScopeContext) {
        ODSScope *scope = object;
        OBASSERT([scope isKindOfClass:[ODSScope class]]);
        
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
    for (ODSScope *scope in _scopes)
        [mergedFileItems unionSet:scope.fileItems];

    if (OFNOTEQUAL(_mergedFileItems, mergedFileItems)) {
        NSSet *addedFileItems;
        
        id <ODSStoreDelegate> delegate = self->_weak_delegate;

        if ([delegate respondsToSelector:@selector(documentStore:addedFileItems:)]) {
            NSMutableSet *items = [[NSMutableSet alloc] initWithSet:mergedFileItems];
            if (_mergedFileItems)
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
    for (ODSScope *scope in _scopes) {
        if (!scope.hasFinishedInitialScan)
            return NO;
    }
    
    return YES;
}

- (void)_flushAfterInitialDocumentScanActions;
{
    if (![self _allScopesHaveFinishedInitialScan] || [self.scopes count] == 0) // there's no legitimate way to have no scopes, so we must just not have them set up yet.
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

- (void)_fileItem:(ODSFileItem *)fileItem willMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    id <ODSStoreDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentStore:fileItem:willMoveToURL:)])
        [delegate documentStore:self fileItem:fileItem willMoveToURL:newURL];
}

- (void)_fileItemEdit:(ODSFileItemEdit *)fileItemEdit willCopyToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    id <ODSStoreDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentStore:fileItemEdit:willCopyToURL:)])
        [delegate documentStore:self fileItemEdit:fileItemEdit willCopyToURL:newURL];
}

- (void)_fileItemEdit:(ODSFileItemEdit *)fileItemEdit finishedCopyToURL:(NSURL *)destinationURL withFileItemEdit:(ODSFileItemEdit *)destinationFileItemEditOrNil;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    id <ODSStoreDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentStore:fileItemEdit:finishedCopyToURL:withFileItemEdit:)])
        [delegate documentStore:self fileItemEdit:fileItemEdit finishedCopyToURL:destinationURL withFileItemEdit:destinationFileItemEditOrNil];
}

- (void)_willRemoveFileItems:(NSArray <ODSFileItem *> *)fileItems;
{
    OBPRECONDITION([NSThread isMainThread]);

    id <ODSStoreDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(documentStore:willRemoveFileItemAtURL:)]) {
        for (ODSFileItem *item in fileItems)
            [delegate documentStore:self willRemoveFileItemAtURL:item.fileURL];
    }
}

@end


