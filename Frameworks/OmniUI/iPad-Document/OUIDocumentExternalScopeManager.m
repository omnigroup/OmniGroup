// Copyright 2015 Omni Development, Inc. All rights reserved.
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
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFFileEdit.h>
#import <OmniFoundation/OFPreference.h>

#import "OUIDocumentAppController.h"
#import "OUIDocumentAppController-Internal.h"
#import "OUIDocumentInbox.h"
#import "OUIDocumentPicker.h"
#import "OUIDocumentPickerViewController.h"

RCS_ID("$Id$")

@implementation OUIDocumentExternalScopeManager
{
    ODSStore *_documentStore;
    NSMutableDictionary *_externalScopes;
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
    [self _loadExternalScopes];

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
                NSURL *securedURL = url;
                if (![securedURL startAccessingSecurityScopedResource])
                    securedURL = nil;
                
                // We treat imported documents much like inbox items: we want to unpack the contents of zip files
                [OUIDocumentInbox cloneInboxItem:url toScope:scopeViewController.selectedScope completionHandler:^(ODSFileItem *newFileItem, NSError *errorOrNil) {
                    [securedURL stopAccessingSecurityScopedResource];
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
    
    BOOL isDirectory;
    NSDate *userModificationDate;
    
    [url startAccessingSecurityScopedResource];
    OFFileEdit *fileEdit = [[OFFileEdit alloc] initWithFileURL:url error:NULL];
    
    if (fileEdit != nil) {
        isDirectory = fileEdit.isDirectory;
        userModificationDate = fileEdit.fileModificationDate;
        if (isDirectory)
            url = OFURLWithTrailingSlash(url);
    } else {
        // File hasn't been downloaded yet
        isDirectory = NO;
        userModificationDate = [NSDate date];
    }
    [url stopAccessingSecurityScopedResource];
    
    Class fileItemClass = [[OUIDocumentAppController controller] documentStore:nil fileItemClassForURL:url];
    ODSFileItem *fileItem = [[fileItemClass alloc] initWithScope:externalScope fileURL:url isDirectory:isDirectory fileEdit:fileEdit userModificationDate:userModificationDate];
    if (fileEdit == nil) {
        // File hasn't been downloaded yet
#ifdef DEBUG_kc
        [url startAccessingSecurityScopedResource];
        NSDictionary *promisedFileAttributes = [url promisedItemResourceValuesForKeys:@[NSURLIsDirectoryKey, NSURLAttributeModificationDateKey, NSURLUbiquitousItemContainerDisplayNameKey, NSURLUbiquitousItemDownloadRequestedKey, NSURLUbiquitousItemDownloadingStatusKey] error:NULL];
        [url stopAccessingSecurityScopedResource];
        NSLog(@"File still downloading: url=%@, status=%@", url, promisedFileAttributes);
#endif
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
        
        // TODO: Rename the source document at fromURL to use the base name before moving it to the cloud
        UIDocumentPickerViewController *pickerViewController = [[UIDocumentPickerViewController alloc] initWithURL:fromURL inMode:UIDocumentPickerModeMoveToService];
        addDocumentCompletionBlock = [addDocumentCompletionBlock copy];
        [[OUIDocumentAppController controller] _presentExternalDocumentPicker:pickerViewController completionBlock:^(NSURL *url) {
            OUIDocumentExternalScopeManager *strongSelf = weakSelf;
            ODSExternalScope *strongScope = weakScope;
            if (strongSelf != nil && strongScope != nil && url != nil) {
                ODSFileItem *fileItem = [strongSelf _fileItemFromExternalURL:url inExternalScope:strongScope];
                addDocumentCompletionBlock(fileItem, nil);
            } else {
                addDocumentCompletionBlock(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
            }
        }];
    };
    
    externalScope.itemsDidChangeBlock = ^(NSSet *fileItems) {
        if (weakSelf != nil)
            [_externalDocumentsPreference setArrayValue:[weakSelf _externalScopeBookmarks]];
    };
    
    [_documentStore addScope:externalScope];
    _externalScopes[containerDisplayName] = externalScope;
    return externalScope;
}

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
            NSError *bookmarkError = nil;
            BOOL securedURL = [url startAccessingSecurityScopedResource];
            NSData *bookmarkData = [url bookmarkDataWithOptions:0 /* docs say to use NSURLBookmarkCreationWithSecurityScope, but SDK says not available on iOS */ includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkError];
            if (securedURL)
                [url stopAccessingSecurityScopedResource];
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

- (void)_loadExternalScopes;
{
    _externalQueue = [[NSOperationQueue alloc] init];
    _externalScopes = [[NSMutableDictionary alloc] init];
    
    // Always create our default external scope
    [self _externalScopeForURL:nil];
    
    // Load from the persistent preference
    NSArray *itemBookmarks = [_externalDocumentsPreference arrayValue];
    for (NSData *bookmarkData in itemBookmarks) {
        NSURL *resolvedURL = [NSURL URLByResolvingBookmarkData:bookmarkData options:0 relativeToURL:nil bookmarkDataIsStale:NULL error:NULL];
        if (resolvedURL != nil) {
            ODSExternalScope *externalScope = [self _externalScopeForURL:resolvedURL];
            [self _fileItemFromExternalURL:resolvedURL inExternalScope:externalScope];
        }
    }
}

- (void)linkExternalDocumentFromURL:(NSURL *)url;
{
    if (url == nil)
        return;
    
    ODSExternalScope *externalScope = [self _externalScopeForURL:url];
    ODSFileItem *fileItem = [self _fileItemFromExternalURL:url inExternalScope:externalScope];
    if (fileItem != nil) {
        OUIDocumentPicker *documentPicker = [OUIDocumentAppController controller].documentPicker;
        [documentPicker.selectedScopeViewController ensureSelectedFilterMatchesFileItem:fileItem];
        [documentPicker navigateToContainerForItem:fileItem animated:YES];
    }
}

@end
