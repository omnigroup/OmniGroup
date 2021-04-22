// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
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
@import OmniFoundation;

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

NS_ASSUME_NONNULL_BEGIN

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
    
#ifdef OMNI_ASSERTIONS_ON
#define BadDelegate(sel) OBASSERT_NOT_IMPLEMENTED(delegate, sel)
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

    if ([scope isTemplate])
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

- (Class)fileItemClassForURL:(NSURL *)fileURL;
{
    return [ODSFileItem class];
}

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;
{
    if (!_afterInitialDocumentScanActions)
        _afterInitialDocumentScanActions = [[NSMutableArray alloc] init];
    [_afterInitialDocumentScanActions addObject:[action copy]];
     
    // ... might be able to call it right now
    [self _flushAfterInitialDocumentScanActions];
}

- (void)moveItems:(NSSet <__kindof ODSFileItem *> *)items fromScope:(ODSScope *)fromScope toScope:(ODSScope *)toScope inFolder:(ODSFolderItem *)parentFolder completionHandler:(void (^ _Nullable)(NSSet <__kindof ODSFileItem *> * _Nullable movedFileItems, NSArray <NSError *> * _Nullable errorsOrNil))completionHandler;
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

        [toScope takeItems:items toFolder:parentFolder ignoringFileItems:nil completionHandler:^(NSSet <__kindof ODSFileItem *> * _Nullable movedFileItems, NSArray <NSError *> * _Nullable errorsOrNil) {
            OBASSERT([NSThread isMainThread]);
            [fromScope finishRelinquishingMovedItems:movedFileItems];
            if (completionHandler)
                completionHandler(movedFileItems, errorsOrNil);
        }];
    } else {
        [toScope moveItems:items toFolder:parentFolder completionHandler:^(NSSet <__kindof ODSFileItem *> * _Nullable movedFileItems, NSArray <NSError *> * _Nullable errorsOrNil){
            OBASSERT([NSThread isMainThread]);
            if (completionHandler)
                completionHandler(movedFileItems, errorsOrNil);
        }];
    }
}

- (void)makeFolderFromItems:(NSSet <__kindof ODSFileItem *> *)items inParentFolder:(ODSFolderItem *)parentFolder ofScope:(ODSScope *)scope completionHandler:(void (^)(ODSFolderItem * _Nullable createdFolder, NSArray <NSError *> * _Nullable errorsOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // since we'll send the completion handler back to the main thread, make sure we came from there
    OBPRECONDITION(scope);
    OBPRECONDITION(!parentFolder || parentFolder.relativePath);
    OBPRECONDITION([items all:^BOOL(ODSItem *item) { return item.scope == scope; }], "Can only create folders from items in the specified scope");

    completionHandler = [completionHandler copy];

    [scope makeFolderFromItems:items inParentFolder:parentFolder completionHandler:^(ODSFolderItem * _Nullable createdFolder, NSArray <NSError *> * _Nullable errorsOrNil){
        OBASSERT([NSThread isMainThread]);
        if (completionHandler)
            completionHandler(createdFolder, errorsOrNil);
    }];
}

- (void)scanItemsWithCompletionHandler:(void (^ _Nullable)(void))completionHandler;
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
        
    OBFinishPortingLater("<bug:///147936> (iOS-OmniOutliner Bug: Not scanning here... - in -[ODSStore scanItemsWithCompletionHandler:])");
    if (completionHandler) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:completionHandler];
    }
}

- (void)startDeferringScanRequests;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    _deferScanRequestCount++;
    DEBUG_STORE(@"_deferScanRequestCount = %ld", _deferScanRequestCount);
}

- (void)stopDeferringScanRequests:(void (^ _Nullable)(void))completionHandler;
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

- (nullable ODSFileItem *)fileItemWithURL:(NSURL *)url;
{
    // We have a union of the scanned items, but it is better to let the scopes handle this than to have the logic in two spots.
    for (ODSScope *scope in _scopes) {
        ODSFileItem *fileItem = [scope fileItemWithURL:url];
        if (fileItem)
            return fileItem;
    }
    return nil;
}

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary *)change context:(void * _Nullable)context;
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
        [self willChangeValueForKey:OFValidateKeyPath(self, mergedFileItems)];
        _mergedFileItems = [[NSMutableSet alloc] initWithSet:mergedFileItems];
        [self didChangeValueForKey:OFValidateKeyPath(self, mergedFileItems)];
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
    // The initial scan may have been *started* due to the metadata query finishing, but we do the scan of the filesystem on a background thread now. Invoke these actions on the main thread.
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        for (void (^action)(void) in actions)
            action();
    }];
}

- (void)_fileItem:(ODSFileItem *)fileItem willMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    id <ODSStoreDelegate> delegate = _weak_delegate;
    if ([delegate respondsToSelector:@selector(documentStore:fileItem:willMoveToURL:)])
        [delegate documentStore:self fileItem:fileItem willMoveToURL:newURL];
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

NS_ASSUME_NONNULL_END
