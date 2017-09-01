// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentExternalScopeManager.h"

#import <OmniDocumentStore/ODSExternalScope.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSScope-Subclass.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFFileEdit.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>

#import "OUIDocumentAppController-Internal.h"
#import "OUIDocumentInbox.h"

RCS_ID("$Id$")

@interface OUIDocumentExternalScopeManager ()
@property (atomic) BOOL savePending;
@end

@interface OUIDocumentExternalFilePresenter : NSObject <NSFilePresenter>
- (instancetype)initWithFileItem:(ODSFileItem *)fileItem;
- (void)registerPresenter;
- (void)unregisterPresenter;
@end

@implementation OUIDocumentExternalScopeManager
{
    ODSStore *_documentStore;
    NSMutableDictionary *_externalScopes;
    NSMutableSet *_externalFilePresenters;
    OFPreference *_externalDocumentsPreference;
    NSOperationQueue *_externalQueue;
}

- (instancetype)initWithDocumentStore:(ODSStore *)documentStore preferenceKey:(NSString *)preferenceKey; // @"OUIExternalDocuments"
{
    self = [super init];
    if (self == nil)
        return nil;
    
    _documentStore = documentStore;
    _externalDocumentsPreference = [OFPreference preferenceForKey:preferenceKey];
    _externalFilePresenters = [[NSMutableSet alloc] init];
    _externalQueue = [[NSOperationQueue alloc] init];
    _externalScopes = [[NSMutableDictionary alloc] init];
    
    [self _loadExternalScopes];
    
    for (ODSScope *scope in [_externalScopes allValues]) {
        [_documentStore addScope:scope];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];

    return self;
}

- (instancetype)initWithDocumentStore:(ODSStore *)documentStore;
{
    return [self initWithDocumentStore:documentStore preferenceKey:@"OUIExternalDocuments"];
}

- (instancetype)init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return [self initWithDocumentStore:nil];
}

- (void)importExternalDocumentFromURL:(NSURL *)url;
{
    if (url == nil)
        return;
    
    OUIDocumentPickerViewController *scopeViewController = [OUIDocumentAppController controller].documentPicker.selectedScopeViewController;
    OBASSERT(scopeViewController != nil);
    [_externalQueue addOperationWithBlock:^{
        // First we need to make sure the resource is completely available
        NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [fileCoordinator coordinateReadingItemAtURL:url options:0 error:NULL byAccessor:^(NSURL *newURL) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                // Now we need to get access to it as a security-scoped resource
                NSURL *securedURL = nil;
                if ([url startAccessingSecurityScopedResource])
                    securedURL = url;
                
                // We treat imported documents much like inbox items: we want to unpack the contents of zip files
                [OUIDocumentInbox cloneInboxItem:url toScope:scopeViewController.selectedScope completionHandler:^(ODSFileItem *newFileItem, NSError *errorOrNil) {
                    [securedURL stopAccessingSecurityScopedResource];
                    OUIDocumentPicker *documentPicker = [OUIDocumentAppController controller].documentPicker;
                    [documentPicker.selectedScopeViewController ensureSelectedFilterMatchesFileItem:newFileItem];
                }];
            }];
        }];
    }];
}

- (ODSFileItem *)_fileItemFromExternalURL:(NSURL *)url inExternalScope:(ODSExternalScope *)externalScope;
{
    if (externalScope == nil)
        return nil;
    
    ODSFileItem *existingFileItem = [externalScope fileItemWithURL:url];
    if (existingFileItem != nil)
        return existingFileItem;
    
    BOOL originalIsDirectory;
    NSDate *originalUserModificationDate;
    OFFileEdit *originalFileEdit;
    {
        NSURL *securedURL = nil;
        if ([url startAccessingSecurityScopedResource])
            securedURL = url;
        originalFileEdit = [[OFFileEdit alloc] initWithFileURL:url error:NULL];
        if (originalFileEdit != nil) {
            originalIsDirectory = originalFileEdit.isDirectory;
            originalUserModificationDate = originalFileEdit.fileModificationDate;
            // Make sure the url is actually readable by us before we return a file item for it
            __autoreleasing NSError *readError = nil;
            NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initWithURL:url options:0 error:&readError];
            if (fileWrapper == nil) {
                NSLog(@"Cannot read %@%@: %@", url, (securedURL != nil ? @" [secured]" : @""), [readError toPropertyList]);
                [securedURL stopAccessingSecurityScopedResource];
                return nil;
            }
        } else {
            // File hasn't been downloaded yet
            originalIsDirectory = NO;
            originalUserModificationDate = [NSDate date];
        }
        [securedURL stopAccessingSecurityScopedResource];
    }

    Class fileItemClass = [[OUIDocumentAppController controller] documentStore:nil fileItemClassForURL:url];
    ODSFileItem *fileItem = [[fileItemClass alloc] initWithScope:externalScope fileURL:url isDirectory:originalIsDirectory fileEdit:originalFileEdit userModificationDate:originalUserModificationDate];
    if (originalFileEdit == nil) {
        // File hasn't been downloaded yet
        fileItem.isDownloaded = NO;
        fileItem.isDownloading = YES;
        OBASSERT(_externalQueue != nil);
        [_externalQueue addOperationWithBlock:^{
            NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [fileCoordinator coordinateReadingItemAtURL:url options:0 error:NULL byAccessor:^(NSURL *newURL) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    fileItem.isDownloading = NO;
                    fileItem.isDownloaded = YES;
                    NSURL *securedURL = nil;
                    if ([url startAccessingSecurityScopedResource])
                        securedURL = url;
                    OFFileEdit *fileEdit = [[OFFileEdit alloc] initWithFileURL:url error:NULL];
                    [securedURL stopAccessingSecurityScopedResource];
                    fileItem.fileEdit = fileEdit;
                    fileItem.userModificationDate = fileEdit.fileModificationDate;
                    [[NSNotificationCenter defaultCenter] postNotificationName:ODSFileItemFinishedDownloadingNotification object:_documentStore userInfo:@{ODSFileItemInfoKey:fileItem}];
                }];
            }];
        }];
    }

    OUIDocumentExternalFilePresenter *presenter = [[OUIDocumentExternalFilePresenter alloc] initWithFileItem:fileItem];
    [_externalFilePresenters addObject:presenter];
    [presenter registerPresenter];
    [externalScope addExternalFileItem:fileItem];

    return fileItem;
}

- (ODSExternalScope *)_externalScopeForContainerDisplayName:(NSString *)containerDisplayName;
{
    if (_externalScopes[containerDisplayName] != nil)
        return _externalScopes[containerDisplayName];
    
    ODSExternalScope *externalScope = [[ODSExternalScope alloc] initWithDocumentStore:_documentStore];
    externalScope.identifier = containerDisplayName;
    externalScope.displayName = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ Documents", @"OmniUIDocument", OMNI_BUNDLE, @"Location label format for external documents"), containerDisplayName];
    
    __block __weak ODSExternalScope *weakScope = externalScope;
    __block __weak OUIDocumentExternalScopeManager *weakSelf = self;
    externalScope.addDocumentBlock = ^(ODSFolderItem *folderItem, NSString *baseName, NSString *fileType, NSURL *fromURL, ODSStoreAddOption option, void (^addDocumentCompletionBlock)(ODSFileItem *duplicateFileItem, NSError *error)) {
        if (folderItem != weakScope.rootFolder) {
            OBASSERT_NOT_REACHED("This external scope only expects to have a root folder");
            addDocumentCompletionBlock(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
            return;
        }
        
        // Copy the source document at fromURL to use a temporary path (using the provided base name) before moving it to the cloud
        if (!baseName)
            baseName = [[fromURL lastPathComponent] stringByDeletingPathExtension];

        NSFileManager *manager = [NSFileManager defaultManager];

        NSString *temporaryPath;
        {
            NSString *extension = OFPreferredPathExtensionForUTI(fileType);
            NSString *targetFileName = [baseName stringByAppendingPathExtension:extension];
            temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:targetFileName];
            __autoreleasing NSError *uniqueFilenameError = nil;
            temporaryPath = [manager uniqueFilenameFromName:temporaryPath allowOriginal:YES create:NO error:&uniqueFilenameError];
            if (temporaryPath == nil) {
                addDocumentCompletionBlock(nil, uniqueFilenameError);
                return;
            }
        }

        NSURL *moveSourceURL = [NSURL fileURLWithPath:temporaryPath];
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block NSURL *writtenURL = nil;
        __block NSError *innerError = nil;
        __autoreleasing NSError *error = nil;
        [coordinator coordinateReadingItemAtURL:fromURL options:0
                               writingItemAtURL:moveSourceURL options:NSFileCoordinatorWritingForReplacing
                                          error:&error byAccessor:
         ^(NSURL *newReadingURL, NSURL *newWritingURL) {
             // if the file is one of our package formats, we need to make it flat so that we can trust the external document provider to handle it safely
             ODSFileItem *fileItemToFlatten = [weakScope makeFileItemForURL:newReadingURL
                                                                isDirectory:NO
                                                                   fileEdit:nil
                                                       userModificationDate:[NSDate date]];
             NSData *flattenedData = [fileItemToFlatten dataForWritingToExternalStorage];
             if (flattenedData) {
                 if (![[NSFileManager defaultManager] createFileAtPath:newWritingURL.path contents:flattenedData attributes:nil]) {
                     NSLog(@"Could not save %@ to external scope %@", newWritingURL, weakScope);
                 }
             } else {
                 __autoreleasing NSError *copyError = nil;
                 if (![manager copyItemAtURL:newReadingURL toURL:newWritingURL error:&copyError]) {
                     [copyError log:@"Error copying %@ to %@", newReadingURL, newWritingURL];
                     innerError = copyError;
                     return;
                 }
             }
             
             writtenURL = newWritingURL;
         }];

        if (writtenURL == nil) {
            OBASSERT(error || innerError);
            if (innerError)
                error = innerError;
            addDocumentCompletionBlock(nil, error);
            return;
        }

        // Move the copied document to an external container
        UIDocumentPickerViewController *pickerViewController = [[UIDocumentPickerViewController alloc] initWithURL:writtenURL inMode:UIDocumentPickerModeMoveToService];
        addDocumentCompletionBlock = [addDocumentCompletionBlock copy];
        [[OUIDocumentAppController controller] _presentExternalDocumentPicker:pickerViewController completionBlock:^(NSURL *url) {
            OUIDocumentExternalScopeManager *strongSelf = weakSelf;
            ODSExternalScope *strongScope = weakScope;
            if (strongSelf != nil && strongScope != nil && url != nil) {
                ODSFileItem *fileItem = [strongSelf _fileItemFromExternalURL:url inExternalScope:strongScope];
                addDocumentCompletionBlock(fileItem, nil);

                // Move the original document to the trash
                __autoreleasing NSError *trashError = nil;
                __autoreleasing NSURL *actualTrashURL;
                if (![ODSScope trashItemAtURL:fromURL resultingItemURL:&actualTrashURL error:&trashError]) {
                    // Would be nice to explain why this copy didn't land in the trash, but we did copy the item and don't want to return failure.  We don't want to remove the file since we don't trust the external item to stay valid, so let's just log and leave it where it is.
                    NSLog(@"Unable to move original file at %@ to trash: %@", [fromURL absoluteString], trashError);
                } else {
                    if (!actualTrashURL) {
                        actualTrashURL = fromURL;
                    }
                    // append (copy) to the end of the filename so it's clearer what this thing is and why it's in the trash
                    NSString *betterTrashFileName = [actualTrashURL lastPathComponent];
                    NSString *extension = [betterTrashFileName pathExtension];
                    betterTrashFileName = [betterTrashFileName stringByDeletingPathExtension];
                    betterTrashFileName = [betterTrashFileName stringByAppendingString:NSLocalizedStringFromTableInBundle(@" (Copy)",  @"OmniUIDocument", OMNI_BUNDLE, @"Filename appendage to indicate file is a copy of a file that has been moved to a different location")];
                    betterTrashFileName = [betterTrashFileName stringByAppendingPathExtension:extension];
                    NSString *pathToTrash = [actualTrashURL path];
                    pathToTrash = [pathToTrash stringByDeletingLastPathComponent];
                    pathToTrash = [pathToTrash stringByAppendingPathComponent:betterTrashFileName];
                    __autoreleasing NSError *moveError = nil;
                    [[NSFileManager defaultManager] moveItemAtURL:actualTrashURL toURL:[NSURL fileURLWithPath:pathToTrash] error:&moveError];
                }
            } else {
                addDocumentCompletionBlock(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
            }
        }];
    };
    
    externalScope.itemsDidChangeBlock = ^(NSSet *fileItems) {
        OUIDocumentExternalScopeManager *strongSelf = weakSelf;
        [strongSelf _deregisterStaleFilePresenters];
        [strongSelf _queueSaveExternalScopes];
    };
    
    _externalScopes[containerDisplayName] = externalScope;
    return externalScope;
}

// No matter what the URL is, we always pass the same display name, and we always return the one external scope. Why do we have an array? Why do we pass this URL in?
- (ODSExternalScope *)_externalScopeForURL:(NSURL *)url;
{
    NSString *displayName = NSLocalizedStringFromTableInBundle(@"Other", @"OmniUIDocument", OMNI_BUNDLE, @"Generic name for location of external documents");
    return [self _externalScopeForContainerDisplayName:displayName];
}

- (NSArray *)_externalScopeBookmarks;
{
    NSMutableSet *newBookmarks = [[NSMutableSet alloc] init];
    for (ODSExternalScope *externalScope in [_externalScopes objectEnumerator]) {
        for (ODSFileItem *fileItem in externalScope.fileItems) {
            NSURL *url = fileItem.fileURL;
            __autoreleasing NSError *bookmarkError = nil;
            NSURL *securedURL = nil;
            if ([url startAccessingSecurityScopedResource])
                securedURL = url;
            NSData *bookmarkData = [url bookmarkDataWithOptions:0 /* docs say to use NSURLBookmarkCreationWithSecurityScope, but SDK says not available on iOS */ includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkError];
            [securedURL stopAccessingSecurityScopedResource];
            if (bookmarkData != nil) {
                [newBookmarks addObject:bookmarkData];
            } else {
#ifdef DEBUG
                NSLog(@"Unable to create bookmark for %@: %@", url, [bookmarkError toPropertyList]);
#endif
            }
        }
    }
    return [newBookmarks allObjects];
}

- (NSSet *)_activeURLs;
{
    NSMutableSet *activeURLs = [[NSMutableSet alloc] init];
    for (ODSExternalScope *externalScope in [_externalScopes objectEnumerator]) {
        for (ODSFileItem *fileItem in externalScope.fileItems) {
            NSURL *url = fileItem.fileURL;
            [activeURLs addObject:url];
        }
    }
    return activeURLs;
}

- (void)_deregisterStaleFilePresenters;
{
    NSSet *activeURLs = [self _activeURLs];
    [self _deregisterFilePresentersNotMatchingActiveURLs:activeURLs];
    OBPOSTCONDITION(_externalFilePresenters.count == activeURLs.count);
}

- (void)_deregisterAllFilePresenters;
{
    [self _deregisterFilePresentersNotMatchingActiveURLs:[NSSet set]];
    OBPOSTCONDITION(_externalFilePresenters.count == 0);
}

- (void)_deregisterFilePresentersNotMatchingActiveURLs:(NSSet *)activeURLs;
{
    NSSet *filePresenters = [_externalFilePresenters copy];
    for (OUIDocumentExternalFilePresenter *filePresenter in filePresenters) {
        if (![activeURLs containsObject:filePresenter.presentedItemURL]) {
            [filePresenter unregisterPresenter];
            [_externalFilePresenters removeObject:filePresenter];
        }
    }
}

- (void)_loadExternalScopes;
{
    // Make a snapshot of our external bookmarks
    NSArray *itemBookmarks = [[_externalDocumentsPreference arrayValue] copy];

    // Reset any external scopes that already exist.  We're going to reload their contents from our bookmarks.
    [self _deregisterAllFilePresenters];
    for (ODSExternalScope *externalScope in [_externalScopes objectEnumerator]) {
        [externalScope setFileItems:[NSSet set] itemMoved:NO];
    }

    // Always create our default external scope, even if we don't have any bookmarks
    [self _externalScopeForURL:nil];
    
    // Resolve our bookmarks and turn them into file items
    for (NSData *bookmarkData in itemBookmarks) {
        NSURL *resolvedURL = [NSURL URLByResolvingBookmarkData:bookmarkData options:0 relativeToURL:nil bookmarkDataIsStale:NULL error:NULL];
        if (resolvedURL != nil) {
#ifdef DEBUG_kc
            NSLog(@"-[%@ %@]: resolvedURL=[%@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd), [resolvedURL absoluteString]);
#endif
            ODSExternalScope *externalScope = [self _externalScopeForURL:resolvedURL];
            [self _fileItemFromExternalURL:resolvedURL inExternalScope:externalScope];
        }
    }

    // If resolving our bookmarks discovered that a file moved or was deleted, we should save its new state now
    [self _saveExternalScopes];
}

- (void)_queueSaveExternalScopes;
{
    if (self.savePending)
        return;

    self.savePending = YES;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        if (self.savePending)
            [self _saveExternalScopes];
    }];
}

- (void)_saveExternalScopes;
{
    self.savePending = NO;
    [_externalDocumentsPreference setArrayValue:[self _externalScopeBookmarks]];
}

- (ODSFileItem *)fileItemFromExternalDocumentURL:(NSURL *)url
{
    if (url == nil) {
        return nil;
    }

    ODSExternalScope *externalScope = [self _externalScopeForURL:url];
    ODSFileItem *fileItem = [self _fileItemFromExternalURL:url inExternalScope:externalScope];
    return fileItem;
}

- (void)linkExternalDocumentFromURL:(NSURL *)url;
{
    ODSFileItem *fileItem = [self fileItemFromExternalDocumentURL:url];

    if (fileItem != nil) {
        OUIDocumentPicker *documentPicker = [OUIDocumentAppController controller].documentPicker;
        [documentPicker.selectedScopeViewController ensureSelectedFilterMatchesFileItem:fileItem];
        [documentPicker navigateToContainerForItem:fileItem dismissingAnyOpenDocument:YES animated:YES];
    }
}

- (void)_applicationDidEnterBackground:(NSNotification *)notification;
{
    [self _deregisterAllFilePresenters];

    if (self.savePending)
        [self _saveExternalScopes];
}

- (void)_applicationWillEnterForeground:(NSNotification *)notification;
{
    [self _loadExternalScopes];
}


@end

@interface OUIDocumentExternalFilePresenter ()
@property (atomic, copy) NSURL *fileURL;
@end

@implementation OUIDocumentExternalFilePresenter
{
    ODSFileItem *_fileItem;
}

static NSOperationQueue *presentedItemOperationQueue;

+ (void)initialize;
{
    OBINITIALIZE;

    presentedItemOperationQueue = [[NSOperationQueue alloc] init];
}

- (instancetype)initWithFileItem:(ODSFileItem *)fileItem;
{
    self = [super init];
    if (self == nil)
        return nil;

    _fileItem = fileItem;
    _fileURL = fileItem.fileURL;

    return self;
}

- (void)registerPresenter;
{
    [NSFileCoordinator addFilePresenter:self];
}

- (void)unregisterPresenter;
{
    [NSFileCoordinator removeFilePresenter:self];
}

#pragma mark - NSFilePresenter protocol

- (NSURL *)presentedItemURL;
{
    return _fileURL;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    return presentedItemOperationQueue;
}

- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
{
    self.fileURL = newURL;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_fileItem.scope completedMoveOfFileItem:_fileItem toURL:newURL];
    }];
}

- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError * __nullable errorOrNil))completionHandler;
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_fileItem.scope deleteItems:[NSSet setWithArray:@[_fileItem]] completionHandler:^(NSSet *deletedFileItems, NSArray *errorsOrNil) {
            NSError *errorOrNil = nil;
            if (deletedFileItems.count == 0 && errorsOrNil.count != 0) {
                errorOrNil = errorsOrNil[0];
            }
            completionHandler(errorOrNil);
        }];
    }];
}

@end
