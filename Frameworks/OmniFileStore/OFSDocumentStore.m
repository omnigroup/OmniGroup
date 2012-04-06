// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStore.h>

#import <OmniFileStore/OFSFeatures.h>

#if OFS_DOCUMENT_STORE_SUPPORTED

#import <OmniFileStore/OFSDocumentStoreDelegate.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniFileStore/Errors.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFNetReachability.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniUnzip/OUUnzipArchive.h>

#import "OFSShared_Prefix.h"
#import "OFSDocumentStoreItem-Internal.h"
#import "OFSDocumentStoreFileItem-Internal.h"
#import "OFSDocumentStore-Internal.h"

#import <Foundation/NSOperation.h>
#import <Foundation/NSFileCoordinator.h>
#import <Foundation/NSMetadata.h>

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
OBDEPRECATED_METHOD(-documentStore:scopeForNewDocumentAtURL:); // New documents are always adds to default scope. Restored sample documents are always added to local scope. Pass in nil to one of the -addDocumentWithScope:... methods for the default scope. 
OBDEPRECATED_METHOD(-documentStore:shouldIncludeFileItemWithFileType:); // should instead set a predicate on your documentPicker's DocumentStoreFilter when it's created to narrow which files are displayed.
OBDEPRECATED_METHOD(-userFileExistsWithFileNameOfURL:); // Instead use -scopeForFileName:inFolder:. If nil, then the file diesn't exist.
OBDEPRECATED_METHOD(-addDocumentFromURL:option:completionHandler:); // Should use a method that allows scope to be passed in. (ex. -addDocumentWithScope:inFolderNamed:baseName:fromURL:option:completionHandler: or -addDocumentWithScope:inFolderNamed:fromURL:option:completionHandler:)

static NSOperationQueue *NotificationCompletionQueue = nil;

NSString * const OFSDocumentStoreUbiquityEnabledChangedNotification = @"OFSDocumentStoreUbiquityEnabledChanged";

NSString * const OFSDocumentStoreFileItemsBinding = @"fileItems";
NSString * const OFSDocumentStoreTopLevelItemsBinding = @"topLevelItems";

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
static NSString * const DocumentInteractionInbox = @"Inbox";
#endif

// iWork uses ".../Foo.folder/Document.ext" for grouping in the document picker.
static NSString * const OFSDocumentStoreFolderPathExtension = @"folder";

static BOOL _isFolder(NSURL *URL)
{
    return [[URL pathExtension] caseInsensitiveCompare:OFSDocumentStoreFolderPathExtension] == NSOrderedSame;
}

static NSString *_folderFilename(NSURL *fileURL)
{
    NSURL *containerURL = [fileURL URLByDeletingLastPathComponent];
    if (_isFolder(containerURL))
        return [containerURL lastPathComponent];
    return nil;
}

static NSString *_availableName(NSSet *usedFileNames, NSString *baseName, NSString *extension, NSUInteger *ioCounter);
#if defined(OMNI_ASSERTIONS_ON) || !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
static OFSDocumentStoreScope *_scopeForFileURL(NSDictionary *scopeToContainerURL, NSURL *fileURL);
static NSDictionary *_scopeToContainerURL(OFSDocumentStore *docStore);
#endif

@interface OFSDocumentStore ()
+ (NSURL *)_ubiquityContainerURL;
- (OFSDocumentStoreScope *)_defaultScope;
- (NSArray *)_scanItemsDirectoryURLs;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSURL *)_moveURL:(NSURL *)sourceURL toCloud:(BOOL)shouldBeInCloud error:(NSError **)outError;
#endif
- (NSURL *)_urlForScope:(OFSDocumentStoreScope *)scope folderName:(NSString *)folderName fileName:(NSString *)fileName error:(NSError **)outError;

- (void)_ubiquityAllowedPreferenceChanged:(NSNotification *)note;
- (void)_startMetadataQuery;
- (void)_stopMetadataQuery;
- (void)_metadataQueryDidStartGatheringNotifiction:(NSNotification *)note;
- (void)_metadataQueryDidGatheringProgressNotifiction:(NSNotification *)note;
- (void)_metadataQueryDidFinishGatheringNotifiction:(NSNotification *)note;
- (void)_metadataQueryDidUpdateNotifiction:(NSNotification *)note;

- (void)_flushAfterInitialDocumentScanActions;

- (OFSDocumentStoreFileItem *)_newFileItemForURL:(NSURL *)fileURL date:(NSDate *)date;

- (NSString *)_singleTopLevelEntryNameInArchive:(OUUnzipArchive *)archive directory:(BOOL *)directory error:(NSError **)error;
- (NSString *)_fileTypeForDocumentInArchive:(OUUnzipArchive *)archive error:(NSError **)error; // returns the UTI, or nil if there was an error

// File name uniquing
- (NSMutableSet *)_copyCurrentlyUsedFileNames:(OFSDocumentStoreScope *)scope;
- (NSMutableSet *)_copyCurrentlyUsedFileNames:(OFSDocumentStoreScope *)scope ignoringFileURL:(NSURL *)fileURLToIgnore;
- (void)_addCurrentlyUsedFileNames:(NSMutableSet *)fileNames inScope:(OFSDocumentStoreScope *)scope ignoringFileURL:(NSURL *)fileURLToIgnore;
- (NSString *)_availableFileNameWithBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter scope:(OFSDocumentStoreScope *)scope;
- (NSURL *)_availableURLInDirectoryAtURL:(NSURL *)directoryURL baseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter scope:(OFSDocumentStoreScope *)scope;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSURL *)_availableURLWithFileName:(NSString *)fileName;
#endif
- (NSURL *)_renameTargetURLForFileItem:(OFSDocumentStoreFileItem *)fileItem usedFilenames:(NSSet *)usedFilenames counter:(NSUInteger *)ioCounter;
- (void)_checkFileItemsForUniqueFileNames;
- (NSOperation *)_renameFileItemsToHaveUniqueFileNames:(NSMutableArray *)fileItems withScope:(OFSDocumentStoreScope *)scope;

@end

@implementation OFSDocumentStore
{
    // NOTE: There is no setter for this; we currently make some calls to the delegate from a background queue and just use the ivar.
    id <OFSDocumentStoreDelegate> _nonretained_delegate;
    
    BOOL _lastNotifiedUbiquityEnabled;
    
    NSMetadataQuery *_metadataQuery;
    BOOL _metadataInitialScanFinished;
    NSMutableArray *_afterInitialDocumentScanActions;
    NSMutableArray *_afterMetadataUpdateActions;
    NSUInteger _metadataUpdateVersionNumber;
    
    BOOL _isScanningItems;
    NSUInteger _deferScanRequestCount;
    NSMutableArray *_deferredScanCompletionHandlers;
    
    BOOL _isRenamingFileItemsToHaveUniqueFileNames;
    
    NSMutableSet *_fileItems;
    NSDictionary *_groupItemByName;
    
    NSMutableSet *_topLevelItems;
    
    NSOperationQueue *_actionOperationQueue;
    
    NSArray *_ubiquitousScopes;
    OFSDocumentStoreScope *_localScope;
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    OFNetReachability *_netReachability; // Only set up if we have a metadata query running.
#endif
}

OFPreference *OFSDocumentStoreDisableUbiquityPreference = nil; // Even if ubiquity is enabled, don't ask the user -- just pretend we don't see it.
static OFPreference *OFSDocumentStoreUserWantsUbiquityPreference = nil; // If ubiquity is on, the user still might want to not use it, but have the option to turn it on later.

+ (void)initialize;
{
    OBINITIALIZE;

    OFSDocumentStoreDisableUbiquityPreference = [[OFPreference preferenceForKey:@"OFSDocumentStoreDisableUbiquity"] retain];
    OFSDocumentStoreUserWantsUbiquityPreference = [[OFPreference preferenceForKey:@"OFSDocumentStoreUserWantsUbiquity"] retain];
    
    // A concurrent queue for simple operations that just serve as dependencies to note completion for other operations.
    NotificationCompletionQueue = [[NSOperationQueue alloc] init];
    [NotificationCompletionQueue setName:@"OFSFileStore notification completion notification queue"];
}

+ (BOOL)shouldPromptForUbiquityAccess;
{
    if ([self _ubiquityContainerURL] == nil) {
        // The user might have turned off ubiquity while we were in the background/not running. Wipe our previous result of prompting the user so we'll ask again if it the user turns it back on in the future.
        [OFSDocumentStoreUserWantsUbiquityPreference restoreDefaultValue];
        return NO;
    }
    
    if ([OFSDocumentStoreUserWantsUbiquityPreference hasNonDefaultValue]) {
        OBASSERT([[OFSDocumentStoreUserWantsUbiquityPreference objectValue] isKindOfClass:[NSNumber class]]);
        return NO;
    } else {
        OBASSERT([[OFSDocumentStoreUserWantsUbiquityPreference objectValue] isEqual:@"query"]);
        return YES;
    }
}

+ (BOOL)canPromptForUbiquityAccess;
{
    return ([self _ubiquityContainerURL] != nil);
}

+ (void)didPromptForUbiquityAccessWithResult:(BOOL)allowUbiquityAccess
{
    // Instances listen for changes to this preference and will start/stop their metadata query appropriately.
    [OFSDocumentStoreUserWantsUbiquityPreference setBoolValue:allowUbiquityAccess];
}

+ (BOOL)isUbiquityAccessEnabled;
{
    if ([self _ubiquityContainerURL] == nil)
        return NO;
    
    if ([OFSDocumentStoreUserWantsUbiquityPreference hasNonDefaultValue]) {
        id value = [OFSDocumentStoreUserWantsUbiquityPreference objectValue];
        OBASSERT(value);
        return [value boolValue];
    } else {
        // For some reason we haven't asked the user yet. This can be a valid path so there is no assertion here -- for example, if the user launchs an app on iOS for the first time by tapping a document in Mail, we want to immediately open the document and not prompt the user for iCloud enabledness.
        return NO;
    }
}

+ (NSArray *)defaultUbiquitousScopes;
{
    return [[[NSArray alloc] initWithObjects:[OFSDocumentStoreScope defaultUbiquitousScope], nil] autorelease];
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

- (void)applicationDidEnterBackground;
{
    // If running, stop the NSMetadataQuery for now. When we are reactivated the user may have added/removed their iCloud account
    DEBUG_STORE(@"Application did enter background");
    [self _stopMetadataQuery];
    
    // If iCloud or Documents & Data is turned off while we are in the background, file items might disappear. When foregrounded, they'd get a -presentedItemDidChange before the scan happened that told us they were gone and they'd generate errors trying to look up their modification date.
    for (OFSDocumentStoreFileItem *fileItem in _fileItems)
        [fileItem _suspendFilePresenter];
}

- (void)applicationWillEnterForegroundWithCompletionHandler:(void (^)(void))completionHandler;
{
    // Restart our query, if possible. Or, just rescan the filesystem if iCloud is not enabled.
    DEBUG_STORE(@"Application will enter foreground");
    
    completionHandler = [[completionHandler copy] autorelease];
    
    [self _startMetadataQuery];
    
    [self _postUbiquityEnabledChangedIfNeeded];
    
    void (^scanFinished)(void) = ^{
        for (OFSDocumentStoreFileItem *fileItem in _fileItems)
            [fileItem _resumeFilePresenter];
        
        if (completionHandler)
            completionHandler();
    };
    
    if (_metadataQuery) {
        // We'll get a scan provoked by NSMetadataQueryDidFinishGatheringNotification 
        [self addAfterInitialDocumentScanAction:scanFinished];
    } else {
        [self scanItemsWithCompletionHandler:scanFinished];
    }
}

#endif

- (OFSDocumentStoreScope *)scopeForFileName:(NSString *)fileName inFolder:(NSString *)folder;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Look through _fileItems for file with fileName in folder.
    for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
        NSString *itemFileName = [fileItem.fileURL lastPathComponent];
        NSString *itemFolderName = [self folderNameForFileURL:fileItem.fileURL];
        
        // Check fileName and folder.
        if (([itemFolderName localizedCaseInsensitiveCompare:folder] == NSOrderedSame) &&
            ([itemFileName localizedCaseInsensitiveCompare:fileName] == NSOrderedSame)) {
            return fileItem.scope;
        }
    }
    
    return nil;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- initWithDirectoryURL:(NSURL *)directoryURL containerScopes:(NSArray *)containerScopes delegate:(id <OFSDocumentStoreDelegate>)delegate scanCompletionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION(delegate);
    
    if (!(self = [super init]))
        return nil;

    _nonretained_delegate = delegate;
    
    if (containerScopes)
        _ubiquitousScopes = [containerScopes copy];
    
    if (directoryURL)
        _localScope = [[OFSDocumentStoreScope alloc] initLocalScopeWithURL:directoryURL];
        
    _actionOperationQueue = [[NSOperationQueue alloc] init];
    [_actionOperationQueue setName:@"OFSDocumentStore file actions"];
    [_actionOperationQueue setMaxConcurrentOperationCount:1];
    
#if 0 && defined(DEBUG)
    if (_directoryURL)
        [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:_directoryURL];
#endif

    [OFPreference addObserver:self selector:@selector(_ubiquityAllowedPreferenceChanged:) forPreference:OFSDocumentStoreUserWantsUbiquityPreference];
    
    [self _startMetadataQuery];
                                    
    _lastNotifiedUbiquityEnabled = [[self class] isUbiquityAccessEnabled]; // Initial state

    // The metadata query, if started, will provoke our initial scan at some point in the future. We don't want to call the passed in completion handler until then since the scan would be incomplete.
    if (_metadataQuery) {
        if (completionHandler)
            [self addAfterInitialDocumentScanAction:completionHandler];
    } else {
        // Otherwise, go ahead and scan right away.
        [self scanItemsWithCompletionHandler:completionHandler];
    }
    
    return self;
}

@synthesize ubiquitousScopes = _ubiquitousScopes, localScope = _localScope;

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;
{
    if (!_afterInitialDocumentScanActions)
        _afterInitialDocumentScanActions = [[NSMutableArray alloc] init];
    [_afterInitialDocumentScanActions addObject:[[action copy] autorelease]];
     
    // ... might be able to call it right now
    [self _flushAfterInitialDocumentScanActions];
}

- (NSUInteger)metadataUpdateVersionNumber;
{
    return _metadataUpdateVersionNumber;
}

- (void)addAfterMetadataUpdateAction:(void (^)(void))action;
{
    if (!_afterMetadataUpdateActions)
        _afterMetadataUpdateActions = [[NSMutableArray alloc] init];
    [_afterMetadataUpdateActions addObject:[[action copy] autorelease]];
}

- (void)dealloc;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#endif
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [_netReachability release];
#endif

    [_metadataQuery release];
    
    for (OFSDocumentStoreFileItem *fileItem in _fileItems)
        [fileItem _invalidate];
    [_fileItems release];
    
    for (NSString *groupName in _groupItemByName)
        [[_groupItemByName objectForKey:groupName] _invalidate];
    [_groupItemByName release];
    
    [_topLevelItems release];
    [_afterInitialDocumentScanActions release];
        
    OBASSERT([_actionOperationQueue operationCount] == 0);
    [_actionOperationQueue release];
    
    [_deferredScanCompletionHandlers release];
    
    [_ubiquitousScopes dealloc];
    [_localScope dealloc];
    
    [super dealloc];
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
    block = [[block copy] autorelease];

    NSOperationQueue *queue = [NSOperationQueue currentQueue];
    OBASSERT(queue);
    OBASSERT(queue != _actionOperationQueue);
    
    [self performAsynchronousFileAccessUsingBlock:^{
        [queue addOperationWithBlock:block];
    }];
}

static BOOL _performAdd(NSURL *fromURL, NSURL *toURL, OFSDocumentStoreScope *scope, BOOL isReplacing, NSError **outError)
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
    
    return YES;
}

// Helper that can be used for methods that create a file item and don't need/want to do a full scan.
static void _addItemAndNotifyHandler(OFSDocumentStore *self, void (^handler)(OFSDocumentStoreFileItem *createdFileItem, NSError *error), NSURL *createdURL, NSError *error)
{
    // As we modify our _fileItem set here and fire KVO, this should be on the main thread.
    OBPRECONDITION([NSThread isMainThread]);
    
    // We just successfully wrote a new document; there is no need to do a full scan (though one may fire anyway if the metadata query launches due to this being in iCloud). Still, we want to get back to the UI as soon as possible by calling the completion handler w/o waiting for the scan.
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
            deletedFileItem = [[fileItem retain] autorelease];
            fileItem = nil; // Ignore this one and make another for the newly replacing file
        }
        
        if (fileItem)
            fileItem.date = date;
        else {
            addedFileItem = [[self _newFileItemForURL:createdURL date:date] autorelease];
            fileItem = addedFileItem;
        }
        
        if (!fileItem) {
            OBASSERT_NOT_REACHED("Some error in the delegate where we created a file of a type we don't display?");
        }
        
        if (deletedFileItem) {
            // Assuming for now that we don't create items inside groups.
            OBASSERT(OFNOTEQUAL([[createdURL URLByDeletingLastPathComponent] pathExtension], OFSDocumentStoreFolderPathExtension));
            OBASSERT([self->_fileItems member:deletedFileItem] == deletedFileItem);
            OBASSERT([self->_topLevelItems member:deletedFileItem] == deletedFileItem);
            
            NSSet *removed = [[NSSet alloc] initWithObjects:&deletedFileItem count:1];
            
            [self willChangeValueForKey:OFSDocumentStoreFileItemsBinding withSetMutation:NSKeyValueMinusSetMutation usingObjects:removed];
            [self->_fileItems minusSet:removed];
            [self didChangeValueForKey:OFSDocumentStoreFileItemsBinding withSetMutation:NSKeyValueMinusSetMutation usingObjects:removed];
            
            [self willChangeValueForKey:OFSDocumentStoreTopLevelItemsBinding withSetMutation:NSKeyValueMinusSetMutation usingObjects:removed];
            [self->_topLevelItems minusSet:removed];
            [self didChangeValueForKey:OFSDocumentStoreTopLevelItemsBinding withSetMutation:NSKeyValueMinusSetMutation usingObjects:removed];
            
            [removed release];
        }
        
        if (addedFileItem) {
            // Assuming for now that we don't create items inside groups.
            OBASSERT(OFNOTEQUAL([[createdURL URLByDeletingLastPathComponent] pathExtension], OFSDocumentStoreFolderPathExtension));
            OBASSERT([self->_fileItems member:addedFileItem] == nil);
            OBASSERT([self->_topLevelItems member:addedFileItem] == nil);
            
            NSSet *added = [[NSSet alloc] initWithObjects:&addedFileItem count:1];
            
            [self willChangeValueForKey:OFSDocumentStoreFileItemsBinding withSetMutation:NSKeyValueUnionSetMutation usingObjects:added];
            [self->_fileItems unionSet:added];
            [self didChangeValueForKey:OFSDocumentStoreFileItemsBinding withSetMutation:NSKeyValueUnionSetMutation usingObjects:added];
            
            [self willChangeValueForKey:OFSDocumentStoreTopLevelItemsBinding withSetMutation:NSKeyValueUnionSetMutation usingObjects:added];
            [self->_topLevelItems unionSet:added];
            [self didChangeValueForKey:OFSDocumentStoreTopLevelItemsBinding withSetMutation:NSKeyValueUnionSetMutation usingObjects:added];
            
            [added release];
        }
    }
    
    if (handler)
        handler(fileItem, error);
}

- (void)addDocumentWithScope:(OFSDocumentStoreScope *)scope inFolderNamed:(NSString *)folderName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    [self addDocumentWithScope:scope inFolderNamed:folderName baseName:nil fromURL:fromURL option:option completionHandler:completionHandler];
}

// Explicit scope version is useful if, for example, the document picker has an open directory and restores a sample document (which would have unknown scope), we should probably put it in that open folder with the default scope.
// Enqueues an operationon the document store's background serial action queue. The completion handler will be called with the resulting file item, nil file item and an error.
- (void)addDocumentWithScope:(OFSDocumentStoreScope *)scope inFolderNamed:(NSString *)folderName baseName:(NSString *)baseName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // We'll invoke the completion handler on the main thread
    
    // Don't copy in random files that the user tapped on in the WebDAV browser or that higher level UI didn't filter out.
    BOOL canView = ([_nonretained_delegate documentStore:self fileItemClassForURL:fromURL] != Nil);
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    NSString *fileType = OFUTIForFileURLPreferringNative(fromURL, NULL);
    canView &= (fileType != nil) && [_nonretained_delegate documentStore:self canViewFileTypeWithIdentifier:fileType];
#endif
    if (!canView) {
        if (completionHandler) {
            NSError *error = nil;
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
            NSLog(@"Error adding document from %@: %@", fromURL, [error toPropertyList]);
        };
    
    completionHandler = [[completionHandler copy] autorelease]; // preserve scope
    
    // Convenience for dispatching the completion handler to the main queue.
    void (^callCompletaionHandlerOnMainQueue)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) = ^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
        OBPRECONDITION(![NSThread isMainThread]);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(duplicateFileItem, error);
        }];
    };
    callCompletaionHandlerOnMainQueue = [[callCompletaionHandlerOnMainQueue copy] autorelease];
    
    if (![scope documentsURL:NULL])
        scope = [self _defaultScope];
    
    // We cannot decide on the destination URL w/o synchronizing with the action queue. In particular, if you try to duplicate "A" and "A 2", both operations could pick "A 3".
    [self performAsynchronousFileAccessUsingBlock:^{
        NSURL *toURL = nil;
        NSString *toFileName = (baseName) ? [baseName stringByAppendingPathExtension:[[fromURL lastPathComponent] pathExtension]] : [fromURL lastPathComponent];
        BOOL isReplacing = NO;
        
        if (option == OFSDocumentStoreAddNormally) {
            // Use the given file name.
            NSError *error = nil;
            toURL = [self _urlForScope:scope folderName:folderName fileName:toFileName error:&error];
            if (!toURL) {
                callCompletaionHandlerOnMainQueue(nil, error);
                return;
            }
        }
        else if (option == OFSDocumentStoreAddByRenaming) {
            // Generate a new file name.
            NSString *toBaseName = nil;
            NSUInteger counter;
            [[toFileName stringByDeletingPathExtension] splitName:&toBaseName andCounter:&counter];
            
            toFileName = [self _availableFileNameWithBaseName:toBaseName extension:[toFileName pathExtension] counter:&counter scope:scope];
            
            NSError *error = nil;
            toURL = [self _urlForScope:scope folderName:folderName fileName:toFileName error:&error];
            if (!toURL) {
                callCompletaionHandlerOnMainQueue(nil, error);
                return;
            }
        }
        else if (option == OFSDocumentStoreAddByReplacing) {
            // Use the given file name, but ensure that it does not exist in the documents directory.
            NSError *error = nil;
            toURL = [self _urlForScope:scope folderName:folderName fileName:toFileName error:&error];
            if (!toURL) {
                callCompletaionHandlerOnMainQueue(nil, error);
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
        NSError *error = nil;
        BOOL success = _performAdd(fromURL, toURL, scope, isReplacing, &error);
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (success)
                _addItemAndNotifyHandler(self, completionHandler, toURL, nil);
            else
                _addItemAndNotifyHandler(self, completionHandler, nil, error);
        }];
    }];
}

- (void)moveDocumentFromURL:(NSURL *)fromURL toScope:(OFSDocumentStoreScope *)scope inFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // We'll invoke the completion handler on the main thread
    
    if (!completionHandler)
        completionHandler = ^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
            NSLog(@"Error adding document from %@: %@", fromURL, [error toPropertyList]);
        };
    
    completionHandler = [[completionHandler copy] autorelease]; // preserve scope
    
    // Convenience for dispatching the completion handler to the main queue.
    void (^callCompletionHandlerOnMainQueue)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error) = ^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
        OBPRECONDITION(![NSThread isMainThread]);
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(duplicateFileItem, error);
        }];
    };
    callCompletionHandlerOnMainQueue = [[callCompletionHandlerOnMainQueue copy] autorelease];
    
    if (![scope documentsURL:NULL])
        scope = [self _defaultScope];
    
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
        
        [coordinator coordinateReadingItemAtURL:fromURL options:NSFileCoordinatorWritingForMoving
                               writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing
                                          error:&error byAccessor:
         ^(NSURL *newSourceURL, NSURL *newDestinationURL) {
             NSError *moveError = nil;
             if (![[NSFileManager defaultManager] moveItemAtURL:newSourceURL toURL:newDestinationURL error:&moveError]) {
                 NSLog(@"Error moving %@ -> %@: %@", newSourceURL, newDestinationURL, [moveError toPropertyList]);
                 innerError = [moveError retain];
                 return;
             }
             
             [coordinator itemAtURL:newSourceURL didMoveToURL:newDestinationURL];
             success = YES;
         }];
        
        [coordinator release];
        
        if (!success) {
            OBASSERT(error || innerError);
            if (innerError)
                error = [innerError autorelease];
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (success)
                _addItemAndNotifyHandler(self, completionHandler, toURL, nil);
            else
                _addItemAndNotifyHandler(self, completionHandler, nil, error);
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
static NSOperation *_coordinatedMoveItem(OFSDocumentStore *self, OFSDocumentStoreFileItem *fileItem, NSURL *sourceURL, NSURL *destinationURL, NSOperationQueue *completionQueue, void (^completionHandler)(NSURL *destinationURL, NSError *errorOrNil))
{
    OBPRECONDITION(![NSThread isMainThread]); // We should be on the action queue
    OBPRECONDITION((completionQueue == nil) == (completionHandler == nil)); // both or neither
    
    DEBUG_STORE(@"Moving item %@ from %@ to %@", [fileItem shortDescription], sourceURL, destinationURL);
    
    // Make sure the completion handler has already been promoted to the heap. The caller should have done that before jumping to the _actionOperationQueue.
    OBASSERT((id)completionHandler == [[completionHandler copy] autorelease]);

    __block NSOperation *presenterNotificationBlock = nil;
    NSError *coordinatorError = nil;
    
#ifdef DEBUG_STORE_ENABLED
    for (id <NSFilePresenter> presenter in [NSFileCoordinator filePresenters]) {
        NSLog(@"  presenter %@ at %@", [(id)presenter shortDescription], presenter.presentedItemURL);
    }
#endif

    // Pass our file item so that it will not receive presenter notifications (we are in charge of sending those). Note we assume that the coordination request will block until all previously queued notifications for this presenter have finished. The definitely would if we passed nil since the 'relinquish' block would need to unblock the coordinator, but here we are telling coordinator to not ask us to relinquish...
    NSFileCoordinator *coordinator = [[[NSFileCoordinator alloc] initWithFilePresenter:fileItem] autorelease];
    
    // Radar 10686553: Coordinated renaming to fix filename case provokes accomodate for deletion
    // If the two paths only differ based on case, we'll rename to a unique name first. Terrible.
    if ([[sourceURL path] localizedCaseInsensitiveCompare:[destinationURL path]] == NSOrderedSame) {
        OFSDocumentStoreScope *scope = [self scopeForFileURL:sourceURL];
        NSString *fileName = [sourceURL lastPathComponent];
        NSString *baseName = nil;
        NSUInteger counter;
        [[fileName stringByDeletingPathExtension] splitName:&baseName andCounter:&counter];

        NSString *temporaryFileName = [self _availableFileNameWithBaseName:baseName extension:[fileName pathExtension] counter:&counter scope:scope];
        NSURL *temporaryURL = _destinationURLForMove(sourceURL, [sourceURL URLByDeletingLastPathComponent], temporaryFileName);
        DEBUG_STORE(@"  doing temporary rename to avoid NSFileCoordinator bug %@ -> %@", sourceURL, temporaryURL);

        [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving
                               writingItemAtURL:temporaryURL options:NSFileCoordinatorWritingForReplacing
                                          error:&coordinatorError
                                     byAccessor:
         ^(NSURL *newURL1, NSURL *newURL2){
             if ((presenterNotificationBlock = [_checkRenamePreconditions(fileItem, sourceURL, newURL1, completionQueue, completionHandler) retain]))
                 return;
             
             NSFileManager *fileManager = [NSFileManager defaultManager];
             
             NSError *moveError = nil;
             if (![fileManager moveItemAtURL:newURL1 toURL:newURL2 error:&moveError]) {
                 NSLog(@"Error moving \"%@\" to \"%@\": %@", [newURL1 absoluteString], [newURL2 absoluteString], [moveError toPropertyList]);
                 presenterNotificationBlock = [_completeCoordinatedMoveItem(fileItem, nil/*destinationURL*/, moveError, completionQueue, completionHandler) retain];
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

         if ((presenterNotificationBlock = [_checkRenamePreconditions(fileItem, sourceURL, newURL1, completionQueue, completionHandler) retain]))
             return;
         
         NSFileManager *fileManager = [NSFileManager defaultManager];
         
         NSError *moveError = nil;
         if (![fileManager moveItemAtURL:newURL1 toURL:newURL2 error:&moveError]) {
             NSLog(@"Error moving \"%@\" to \"%@\": %@", [newURL1 absoluteString], [newURL2 absoluteString], [moveError toPropertyList]);
             presenterNotificationBlock = [_completeCoordinatedMoveItem(fileItem, nil/*destinationURL*/, moveError, completionQueue, completionHandler) retain];
             return;
         }
         
         // Experimentally, we do need to call -itemAtURL:didMoveToURL:, even if we are specifying a move via our options AND if we get passed a presenter, we can't call it directly but need to post that on the presenter queue. Without this, we get various oddities if we have back to back coordinated move operations were the first passes a nil presenter (so notifications are queued -- this could happen if iCloud is initiating a move) and the second passes a non-nil presenter (so there are no notifications queued). The -itemAtURL:didMoveToURL: call will cause the second coordination request to block at least until the queued -presentedItemDidMoveToURL: is invoked, but it will NOT wait for the 'reacquire' block to execute. But, at least all the messages seem to be enqueued, so doing an enqueued notification here means our update will appear after all the notifications from the first coordinator.
         [coordinator itemAtURL:sourceURL didMoveToURL:destinationURL];
         
         presenterNotificationBlock = [_completeCoordinatedMoveItem(fileItem, destinationURL, nil/*error*/, completionQueue, completionHandler) retain];

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
        return [presenterNotificationBlock autorelease];
    }
}

- (void)renameFileItem:(OFSDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionQueue:(NSOperationQueue *)completionQueue handler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
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
    // scanItemsWithCompletionHandler: now ignores the 'Inbox' so we should never get into this situation.
    OBASSERT(![OFSDocumentStore isURLInInbox:containingDirectoryURL]);
#endif
    
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)fileType, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *destinationFileName = [baseName stringByAppendingPathExtension:(NSString *)extension];
    CFRelease(extension);
    
    NSURL *sourceURL = fileItem.fileURL;
    NSURL *destinationURL = _destinationURLForMove(sourceURL, containingDirectoryURL, destinationFileName);
    OFSDocumentStoreScope *scope = [self scopeForFileURL:sourceURL];

    [self performAsynchronousFileAccessUsingBlock:^{

        // Check if there is a file item with this name in any folder, in the relevant scopes, that is the same or differs only in case. Ignore the source URL so that the user can make capitalization/accent corrections in file names w/o getting a self-conflict.
        NSSet *usedFileNames = [[self _copyCurrentlyUsedFileNames:scope ignoringFileURL:sourceURL] autorelease];
        for (NSString *usedFileName in usedFileNames) {
            if ([usedFileName localizedCaseInsensitiveCompare:destinationFileName] == NSOrderedSame) {
                if (completionHandler) {
                    [completionQueue addOperationWithBlock:^{
                        NSError *error = nil;
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

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)makeGroupWithFileItems:(NSSet *)fileItems completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items
    
    OBFinishPortingLater("Should we rescan before finding an available path, or depend on the caller to know things are up to date?");
    OBPRECONDITION(_fileItems); // Make sure we've done a local scan. It might be out of date, so maybe we should scan here too.
    OBPRECONDITION(self.hasFinishedInitialMetdataQuery); // We can't unique against iCloud until whe know what is there

    // Find an available folder placeholder name. First, build up a list of all the folder URLs we know about based on our file items.
    NSMutableSet *folderFilenames = [NSMutableSet set];
    for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
        NSURL *containingURL = [fileItem.fileURL URLByDeletingLastPathComponent];
        if (_isFolder(containingURL)) // Might be ~/Documents or a ubiquity container
            [folderFilenames addObject:[containingURL lastPathComponent]];
    }
    
    NSString *baseName = NSLocalizedStringFromTableInBundle(@"Folder", @"OmniFileStore", OMNI_BUNDLE, @"Base name for document picker folder names");
    NSUInteger counter = 0;
    NSString *folderName = _availableName(folderFilenames, baseName, OFSDocumentStoreFolderPathExtension, &counter);
    
    [self moveItems:fileItems toFolderNamed:folderName completionHandler:completionHandler];
}

- (void)moveItems:(NSSet *)fileItems toFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
{
    // Disabled for now. This needs to be updated for the renaming changes, to do the coordinated moves on the background queue, and to wait for the individual moves to fire before firing the group completion handler (if possible).
    OBFinishPortingLater("No group support");
    if (completionHandler)
        completionHandler(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
                          
#if 0
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items, and this is the queue we'll invoke the completion handler on.
    
    OBFinishPortingLater("Can we rename iCloud items that aren't yet fully (or at all) downloaded?");

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
#endif
}

#endif

- (void)moveItemsAtURLs:(NSSet *)urls toCloudFolderInScope:(OFSDocumentStoreScope *)ubiquitousScope withName:(NSString *)folderNameOrNil completionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBASSERT(ubiquitousScope);
    
    NSMutableDictionary *movedURLs = [NSMutableDictionary dictionary];
    NSMutableDictionary *errorURLs = [NSMutableDictionary dictionary];
    
    // Early out for no-ops
    if ([urls count] == 0)
        goto bail;
    
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
        NSURL *containerURL = [ubiquitousScope documentsURL:&error];
        if (!containerURL) {
            NSLog(@"-moveItemsAtURLs:... failed to get ubiquity container URL: %@", error);
            goto bail;
        }
        
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
                
                NSLog(@"-moveItemsAtURLs:... failed to create cloud directory %@: %@", destinationDirectoryURL, error);
                goto bail;
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
    return;
    
bail:
    if (completionHandler)
        completionHandler(movedURLs, errorURLs);
    
    DEBUG_CLOUD(@"-moveItemsAtURLs:... is returning");
}

- (void)deleteItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items, and this is the queue we'll invoke the completion handler on.

    // capture scope (might not be necessary since we aren't currently asynchronous here).
    completionHandler = [[completionHandler copy] autorelease];
    
    [_actionOperationQueue addOperationWithBlock:^{
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
}

@synthesize fileItems = _fileItems;
@synthesize topLevelItems = _topLevelItems;

static NSString *_fileItemCacheKeyForURL(NSURL *url)
{
    OBPRECONDITION(url);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // NSFileManager will return /private/var URLs even when passed a standardized (/var) URL. Our cache keys should always be in one space.
    // -URLByStandardizingPath only works if the URL exists, so we could only normalize the parent URL (which should be a longer-lived container) and then append the last path component (so that /var/mobile vs /var/private/mobile differences won't hurt).
    // But, even easier is to drop everything before "/mobile/", leaving the application sandbox or the ubiquity container.
    NSString *urlString = [url absoluteString];
    
    NSUInteger urlStringLength = [urlString length];
    OBASSERT(urlStringLength > 0);
    NSRange cacheKeyRange = NSMakeRange(0, urlStringLength);

    NSRange mobileRange = [urlString rangeOfString:@"/mobile/"];
    OBASSERT(mobileRange.length > 0);
    if (mobileRange.length > 0) {
        cacheKeyRange = NSMakeRange(NSMaxRange(mobileRange), urlStringLength - NSMaxRange(mobileRange));
        OBASSERT(NSMaxRange(cacheKeyRange) == urlStringLength);
    }
        
    // NSMetadataItem passes non-directory URLs when the really are directories. Trim the trailing slash if it is there.
    if ([urlString characterAtIndex:urlStringLength - 1] == '/')
        cacheKeyRange.length--;
    
    NSString *cacheKey = [urlString substringWithRange:cacheKeyRange];
    
    OBASSERT([cacheKey hasSuffix:@"/"] == NO);
    OBASSERT([cacheKey containsString:@"/private/var"] == NO);

    return cacheKey;
#else
    OBFinishPortingLater("Figure out how to build cache keys on the Mac"); // have the old version here that doesn't work right for NSURLs that don't currently exist
    
    // NSFileManager will return /private/var URLs even when passed a standardized (/var) URL. Our cache keys should always be in one space.
    url = [url URLByStandardizingPath];
    
    // NSMetadataItem passes URLs w/o the trailing slash when the really are directories. Use strings for keys instead of URLs and trim the trailing slash if it is there.
    return [[url absoluteString] stringByRemovingSuffix:@"/"];
#endif
}

// We no longer use an NSFileCoordinator when scanning the documents directory. NSFileCoordinator doesn't make writers of documents wait if there is a coordinator of their containing directory, so this doesn't help. We *could*, as we find documents, do a coordinated read on each document to make sure we get its most recent timestamp, but this seems wasteful in most cases.
static void _scanDirectoryURL(OFSDocumentStore *self, NSURL *directoryURL, void (^itemBlock)(NSFileManager *fileManager, NSURL *fileURL))
{
    OBASSERT(![NSThread isMainThread]);
    
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
            NSError *error = nil;
            
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
            // We never want to acknowledge files in the inbox directly. Instead they'll be dealt with when they're handed to us via document interaction and moved.
            if ([[self class] isURLInInbox:fileURL])
                continue;
#endif
            
            NSString *uti = OFUTIForFileURLPreferringNative(fileURL, &error);
            if (!uti) {
                OBASSERT_NOT_REACHED("Could not determine UTI for file URL");
                NSLog(@"Could not determine UTI for URL %@: %@", fileURL, [error toPropertyList]);
                continue;
            }
            
            // Recurse into non-document directories in ~/Documents. Not checking for OFSDocumentStoreFolderPathExtension here since I don't recall if documents sent to us from other apps via UIDocumentInteractionController end up inside ~/Documents or elsewhere (and it isn't working for me right now).
            if (!UTTypeConformsTo((CFStringRef)uti, kUTTypePackage)) {
                // The delegate might not want a file item for this URL, but if it's a directory might want ones for its descendants
                NSNumber *isDirectory = nil;
                NSError *resourceError = nil;
                
                if (![fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError])
                    NSLog(@"Unable to determine if %@ is a directory: %@", fileURL, [resourceError toPropertyList]);
                
                // We only want to scan inside directories that aren't used for UI groups.
                if (([isDirectory boolValue]) && (!_isFolder(fileURL))) {
                    [scanDirectoryURLs addObject:fileURL];
                    
                    // We don't want to create an item if the fileURL points to a directory.
                    continue;
                }
            }
            
            
            itemBlock(fileManager, fileURL);
        }
    }
}

// We perform the directory scan on a background thread using file coordination and then invoke the completion handler back on the main thread.
static void _scanDirectoryURLs(OFSDocumentStore *self,
                               NSArray *directoryURLs,
                               void (^itemBlock)(NSFileManager *fileManager, NSURL *fileURL),
                               void (^scanFinished)(void))
{
    OBPRECONDITION(![NSThread isMainThread]);
    
    DEBUG_STORE(@"Scanning directories %@", directoryURLs);
    
    for (NSURL *directoryURL in directoryURLs) {
        DEBUG_STORE(@"Scanning %@", directoryURL);
#if 0 && defined(DEBUG)
        [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:directoryURL];
#endif
        _scanDirectoryURL(self, directoryURL, itemBlock);
    }
         
    if (scanFinished)
        [[NSOperationQueue mainQueue] addOperationWithBlock:scanFinished];
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

static NSDate *_modificationDateForFileURL(NSFileManager *fileManager, NSURL *fileURL)
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

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Need to know what class of file items to make.
    OBPRECONDITION(_nonretained_delegate);
    
    // Capture state
    completionHandler = [[completionHandler copy] autorelease];
    
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
    
    NSArray *directoryURLs = [self _scanItemsDirectoryURLs];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        
        // Build a map of document URLs to modification dates for all the found URLs. We don't deal with file items in the scan since we need to update the _fileItems set on the foreground once the scan is finished and since we'd need to snapshot the existing file items for reuse on the foreground. The gap between these could let other operations in that might add/remove file items. When we are merging this scanned dictionary into the results, we'll need to be careful of that (in particular, other creators of files items like the -addDocumentFromURL:... method
        NSMutableDictionary *urlToModificationDate = [[NSMutableDictionary alloc] init];
        
        void (^itemBlock)(NSFileManager *fileManager, NSURL *fileURL) = ^(NSFileManager *fileManager, NSURL *fileURL){
            NSDate *modificationDate = _modificationDateForFileURL(fileManager, fileURL);
            
            // Files in our ubiquity container, found by directory scan, won't get sent a metadata item here, but will below (if they are in the query).
            [urlToModificationDate setObject:modificationDate forKey:fileURL];
        };
        
        void (^scanFinished)(void) = ^{
            OBASSERT([NSThread isMainThread]);
            
            // Build a lookup table of our existing file items and a set for the new file items.
            NSMutableDictionary *cacheKeyToFileItem = [[NSMutableDictionary alloc] init];
            NSMutableSet *updatedFileItems = [[NSMutableSet alloc] init];;
            
            for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
                OBASSERT([cacheKeyToFileItem objectForKey:_fileItemCacheKeyForURL(fileItem.presentedItemURL)] == nil);
                [cacheKeyToFileItem setObject:fileItem forKey:_fileItemCacheKeyForURL(fileItem.presentedItemURL)];
            }
            DEBUG_STORE(@"cacheKeyToFileItem = %@", cacheKeyToFileItem);

            {
                // Apply metadata to the scanned items. The results of NSMetadataQuery can lag behind the filesystem operations, particularly if they are invoked locally.
                // If you poke at the NSMetadataQuery before it sends out its initial 'finished scan' notification it will usually report zero results.
                NSMutableDictionary *cacheKeyToMetadataItem = [[NSMutableDictionary alloc] init];
                if (_metadataQuery && _metadataInitialScanFinished) {
                    [_metadataQuery disableUpdates];
                    @try {
                        // Using the -results proxy is discouraged
                        NSUInteger metadataItemCount = [_metadataQuery resultCount];
                        DEBUG_METADATA(@"%ld items found via query", metadataItemCount);
                        
#ifdef OMNI_ASSERTIONS_ON
                        NSDictionary *scopeToContainerURL = _scopeToContainerURL(self);
#endif
                        for (NSUInteger metadataItemIndex = 0; metadataItemIndex < metadataItemCount; metadataItemIndex++) {
                            NSMetadataItem *item = [_metadataQuery resultAtIndex:metadataItemIndex];
                            
                            NSURL *fileURL = [item valueForAttribute:NSMetadataItemURLKey];
                            OBASSERT([_scopeForFileURL(scopeToContainerURL, fileURL) isUbiquitous]);
                            
                            // NOTE: The NSMetadataItem ubiquity related keys are not reliable.
                            // Radar 10957039: Missing NSMetadataQuery updates when downloading changes to ubiquitous document
                            // The final update can be missing; for flat files the download percent can get stuck < 100% and for wrappers the 'downloaded' flag can get stuck on NO.
                            // For non-downloaded items, we do want the size/date attributes, though, since our local file might just be a stub.
                            // See -[OFSDocumentStoreFileItem _updateWithMetadataItem:] also, were we need to ignore these attributes on the metadata item.
                            DEBUG_METADATA(@"item %@ %@", item, [fileURL absoluteString]);
                            DEBUG_METADATA(@"  %@", [item valuesForAttributes:[NSArray arrayWithObjects:NSMetadataUbiquitousItemHasUnresolvedConflictsKey, NSMetadataUbiquitousItemIsDownloadedKey, NSMetadataUbiquitousItemIsDownloadingKey, NSMetadataUbiquitousItemIsUploadedKey, NSMetadataUbiquitousItemIsUploadingKey, NSMetadataUbiquitousItemPercentDownloadedKey, NSMetadataUbiquitousItemPercentUploadedKey, NSMetadataItemFSContentChangeDateKey, NSMetadataItemFSSizeKey, nil]]);
                            
                            NSString *cacheKey = _fileItemCacheKeyForURL(fileURL);
                            
                            // -_updateUbiquitousItemWithMetadataItem: will get called below for every scanned item (those in urlToModificationDate) that also has a metadata item (which we are registering here). Don't redundantly call -_updateUbiquitousItemWithMetadataItem: here.
                            // We might find a metadata item for something that is about to be deleted, so we can't easily assert that the metadata item we find has a matching entry in urlToModificationDate.
                            
                            [cacheKeyToMetadataItem setObject:item forKey:cacheKey];
                        }
                    } @finally {
                        [_metadataQuery enableUpdates];
                    }
                }
                
                // Update or create file items
                for (NSURL *fileURL in urlToModificationDate) {
                    NSString *cacheKey = _fileItemCacheKeyForURL(fileURL);
                    OFSDocumentStoreFileItem *fileItem = [cacheKeyToFileItem objectForKey:cacheKey];
                    
                    NSMetadataItem *metadataItem = [cacheKeyToMetadataItem objectForKey:cacheKey];
                    NSDate *modificationDate = [urlToModificationDate objectForKey:fileURL];
                    
                    BOOL isNewItem = NO;
                    
                    if (!fileItem) {
                        fileItem = [self _newFileItemForURL:fileURL date:modificationDate];
                        [updatedFileItems addObject:fileItem];
                        [fileItem release];
                        isNewItem = YES;
                    } else {
                        [updatedFileItems addObject:fileItem];
                    }
                    
                    DEBUG_METADATA(@"Updating metadata properties on file item %@", [fileItem shortDescription]);
                    if (metadataItem) {
                        [fileItem _updateUbiquitousItemWithMetadataItem:metadataItem]; // Use the date in the NSMetadataItem (as well as other info) instead of the local filesystem modification date
                        
                        if (isNewItem)
                            [self _possiblyRequestDownloadOfNewlyAddedUbiquitousFileItem:fileItem metadataItem:metadataItem];
                    } else
                        [fileItem _updateLocalItemWithModificationDate:modificationDate];
                }
                [urlToModificationDate release];
                [cacheKeyToMetadataItem release];
            }
            
            // Invalidate the old file items that are no longer found.
            for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
                if ([updatedFileItems member:fileItem] == nil) {
                    DEBUG_STORE(@"File item %@ has disappeared, invalidating", [fileItem shortDescription]);
                    [fileItem _invalidate];
                }
            }            
            
            BOOL fileItemsChanged = OFNOTEQUAL(_fileItems, updatedFileItems);
            if (fileItemsChanged) {
                [self willChangeValueForKey:OFSDocumentStoreFileItemsBinding];
                [_fileItems release];
                _fileItems = [[NSMutableSet alloc] initWithSet:updatedFileItems];
                [self didChangeValueForKey:OFSDocumentStoreFileItemsBinding];
                
            }
            
            [cacheKeyToFileItem release];
            [updatedFileItems release];

            // Filter items into groups (and the remaining top-level items).
            {
                NSMutableSet *topLevelItems = [[NSMutableSet alloc] init];
                NSMutableDictionary *itemsByGroupName = [[NSMutableDictionary alloc] init];
                
                for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
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
                    OFSDocumentStoreGroupItem *groupItem = [_groupItemByName objectForKey:groupName];
                    if (!groupItem) {
                        groupItem = [[[OFSDocumentStoreGroupItem alloc] initWithDocumentStore:self] autorelease];
                        groupItem.name = groupName;
                    }
                    
                    [groupByName setObject:groupItem forKey:groupName];
                    groupItem.fileItems = [itemsByGroupName objectForKey:groupName];
                    
                    [topLevelItems addObject:groupItem];
                }
                [itemsByGroupName release];
                
                // Invalidate the any groups that we no longer need
                for (NSString *groupName in _groupItemByName) {
                    if ([groupByName objectForKey:groupName] == nil) {
                        OFSDocumentStoreGroupItem *groupItem = [_groupItemByName objectForKey:groupName];
                        DEBUG_STORE(@"Group \"%@\" no longer needed, invalidating %@", groupName, [groupItem shortDescription]);
                        [groupItem _invalidate];
                    }
                }
                
                [_groupItemByName release];
                _groupItemByName = [groupByName copy];
                DEBUG_STORE(@"Scanned groups %@", _groupItemByName);
                DEBUG_STORE(@"Scanned top level items %@", [[_topLevelItems allObjects] arrayByPerformingSelector:@selector(shortDescription)]);
                
                if (OFNOTEQUAL(_topLevelItems, topLevelItems)) {
                    [self willChangeValueForKey:OFSDocumentStoreTopLevelItemsBinding];
                    [_topLevelItems release];
                    _topLevelItems = [[NSMutableSet alloc] initWithSet:topLevelItems];
                    [self didChangeValueForKey:OFSDocumentStoreTopLevelItemsBinding];
                }
                
                [topLevelItems release];
            }
            
            if ([_nonretained_delegate respondsToSelector:@selector(documentStore:scannedFileItems:)])
                [_nonretained_delegate documentStore:self scannedFileItems:_fileItems];
            
            [self _flushAfterInitialDocumentScanActions];
            if (completionHandler)
                completionHandler();
            
            // Now, after we've reported our results, check if there are any documents with the same names. We want document names to be unambiguous, following iWork's lead.
            [self _checkFileItemsForUniqueFileNames];
            
            // We are done scanning -- see if any other scan requests have piled up while we were running and start one if so.
            // We do need to rescan (rather than just calling all the queued completion handlers) since the caller might have queued more filesystem changing operations between the two scan requests.
            _isScanningItems = NO;
            if (_deferScanRequestCount == 0 && [_deferredScanCompletionHandlers count] > 0) {
                void (^nextCompletionHandler)(void) = [[[_deferredScanCompletionHandlers objectAtIndex:0] retain] autorelease];
                [_deferredScanCompletionHandlers removeObjectAtIndex:0];
                [self scanItemsWithCompletionHandler:nextCompletionHandler];
            }
        };
        
        
        _scanDirectoryURLs(self, directoryURLs, itemBlock, scanFinished);
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

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

static BOOL _getBoolResourceValue(NSURL *url, NSString *key, BOOL *outValue, NSError **outError)
{
    NSError *error = nil;
    NSNumber *numberValue = nil;
    if (![url getResourceValue:&numberValue forKey:key error:&error]) {
        NSLog(@"Error getting resource key %@ for %@: %@", key, url, [error toPropertyList]);
        if (outError)
            *outError = error;
        return NO;
    }
    
    *outValue = [numberValue boolValue];
    return YES;
}


// Migrates all the existing documents in one scope to another (either by copying or moving), preserving their folder structure.
- (void)migrateDocumentsInScope:(OFSDocumentStoreScope *)sourceScope toScope:(OFSDocumentStoreScope *)destinationScope byMoving:(BOOL)shouldMove completionHandler:(void (^)(NSDictionary *migratedURLs, NSDictionary *errorURLs))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(sourceScope);
    OBPRECONDITION(destinationScope);
    OBPRECONDITION(sourceScope != destinationScope);
    
    completionHandler = [[completionHandler copy] autorelease];
    
    NSURL *sourceDocumentsURL = [sourceScope documentsURL:NULL];
    NSURL *destinationDocumentsURL = [destinationScope documentsURL:NULL];
    OBASSERT(sourceDocumentsURL);
    OBASSERT(destinationDocumentsURL);
    
    [self performAsynchronousFileAccessUsingBlock:^{
        DEBUG_STORE(@"Migrating documents from %@ to %@ by %@", sourceDocumentsURL, destinationDocumentsURL, shouldMove ? @"moving" : @"copying");
        
        NSMutableDictionary *migratedURLs = [NSMutableDictionary dictionary]; // sourceURL -> destURL
        NSMutableDictionary *errorURLs = [NSMutableDictionary dictionary]; // sourceURL -> error
        
        // Gather the names to avoid (only from the destination).
        NSMutableSet *usedFileNames = [NSMutableSet set];
        [self _addCurrentlyUsedFileNames:usedFileNames inScope:destinationScope ignoringFileURL:nil];
        DEBUG_STORE(@"  usedFileNames = %@", usedFileNames);
        
        // Process all the local documents, moving them into the ubiquity container.
        _scanDirectoryURL(self, sourceDocumentsURL, ^(NSFileManager *fileManager, NSURL *sourceURL){
            // If we are moving from a ubiquitous scope, skip any files that aren't fully downloaded or are in conflict. The higher level code prompts the user (obviously a race condition between the two, but unlikely).
            if (sourceScope.isUbiquitous) {
                NSError *error = nil;
                
                BOOL downloaded, hasConflicts;
                
                if (!_getBoolResourceValue(sourceURL, NSURLUbiquitousItemIsDownloadedKey, &downloaded, &error) ||
                    !_getBoolResourceValue(sourceURL, NSURLUbiquitousItemHasUnresolvedConflictsKey, &hasConflicts, &error)) {
                    [errorURLs setObject:error forKey:sourceURL];
                    return;
                }

                if (!downloaded || hasConflicts)
                    return;
            }
            
            NSString *sourceFileName = [sourceURL lastPathComponent];
            NSUInteger counter = 0;
            NSString *destinationName = _availableName(usedFileNames, [sourceFileName stringByDeletingPathExtension], [sourceFileName pathExtension], &counter);
            
            NSString *folderName = [[sourceURL URLByDeletingLastPathComponent] lastPathComponent];
            if (OFNOTEQUAL([folderName pathExtension], OFSDocumentStoreFolderPathExtension))
                folderName = nil;
            
            NSURL *destinationURL = destinationDocumentsURL;
            if (folderName)
                destinationURL = [destinationURL URLByAppendingPathComponent:folderName];
            destinationURL = [destinationURL URLByAppendingPathComponent:destinationName];
            
            __block BOOL migrateSuccess = NO;
            __block NSError *migrateError = nil;

            __block NSDate *sourceDate = nil;
            __block NSDate *destinationDate = nil;
            
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];

            if (shouldMove) {
                [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving
                                       writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForReplacing error:&migrateError byAccessor:
                 ^(NSURL *newURL1, NSURL *newURL2){
                     migrateSuccess = [fileManager moveItemAtURL:newURL1 toURL:newURL2 error:&migrateError];
                     
                     sourceDate = [_modificationDateForFileURL(fileManager, newURL2) retain];
                     destinationDate = [sourceDate retain];
                 }];
            } else {
                [coordinator coordinateReadingItemAtURL:sourceURL options:0
                                       writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForReplacing error:&migrateError byAccessor:
                 ^(NSURL *newURL1, NSURL *newURL2){
                     migrateSuccess = [fileManager copyItemAtURL:newURL1 toURL:newURL2 error:&migrateError];

                     sourceDate = [_modificationDateForFileURL(fileManager, newURL1) retain];
                     destinationDate = [_modificationDateForFileURL(fileManager, newURL2) retain];
                 }];
            }
            
            [coordinator release];
            
            if (!migrateSuccess) {
                [errorURLs setObject:migrateError forKey:sourceURL];
                DEBUG_STORE(@"  error moving %@: %@", sourceURL, [migrateError toPropertyList]);
            } else {
                if (!shouldMove) { // The file item hears about moves via NSFilePresenter and tells us
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [self _fileWithURL:sourceURL andDate:[sourceDate autorelease] didCopyToURL:destinationURL andDate:[destinationDate autorelease]];
                    }];
                } else {
                    [sourceDate release];
                    [destinationDate release];
                }
                
                [migratedURLs setObject:destinationURL forKey:sourceURL];
                DEBUG_STORE(@"  migrated %@ to %@", sourceURL, destinationURL);
                
                // Now we need to avoid this file name.
                [usedFileNames addObject:[destinationURL lastPathComponent]];
            }
        });
             
        
        if (completionHandler) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionHandler(migratedURLs, errorURLs);
            }];
        }
    }];
}
#endif

- (BOOL)hasDocuments;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after -startScanningDocuments
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items
    
    return [_fileItems count] != 0;
}

- (OFSDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after -startScanningDocuments
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items

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

- (OFSDocumentStoreFileItem *)fileItemNamed:(NSString *)name;
{
    OBPRECONDITION(_fileItems != nil); // Don't call this API until after -startScanningDocuments
    OBPRECONDITION([NSThread isMainThread]); // Synchronize with NSMetadataQuery notifications updating items
    
    for (OFSDocumentStoreFileItem *fileItem in _fileItems)
        if ([fileItem.name isEqual:name])
            return fileItem;

    return nil;
}

// This must be thread safe.
- (OFSDocumentStoreScope *)scopeForFileURL:(NSURL *)fileURL;
{
    if (!fileURL)
        return nil;
    
    if ([_localScope isFileInContainer:fileURL])
        return _localScope;
    for (OFSDocumentStoreScope *ubiquitousScope in _ubiquitousScopes)
        if ([ubiquitousScope isFileInContainer:fileURL])
            return ubiquitousScope;
    
    return [self _defaultScope];
}
 
- (NSString *)folderNameForFileURL:(NSURL *)fileURL;
{
    return _folderFilename(fileURL);
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

// This always returns a URL in the device's ~/Documents sandbox directory. After creation, the document may be moved into the iCloud container by -createNewDocument:
- (NSURL *)urlForNewDocumentWithName:(NSString *)name ofType:(NSString *)documentUTI;
{
    OBPRECONDITION(documentUTI);
    
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)documentUTI, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    static NSString * const UntitledDocumentCreationCounterKey = @"OUIUntitledDocumentCreationCounter";
    
    NSURL *directoryURL = [[self class] userDocumentsDirectoryURL];
    NSUInteger counter = [[NSUserDefaults standardUserDefaults] integerForKey:UntitledDocumentCreationCounterKey];
    
    NSURL *fileURL = [self _availableURLInDirectoryAtURL:directoryURL baseName:name extension:(NSString *)extension counter:&counter scope:_localScope];
    CFRelease(extension);
    
    [[NSUserDefaults standardUserDefaults] setInteger:counter forKey:UntitledDocumentCreationCounterKey];
    return fileURL;
}

- (void)createNewDocument:(void (^)(OFSDocumentStoreFileItem *createdFileItem, NSError *error))handler;
{
    // Put this in the _actionOperationQueue so we seralize with any previous in-flight scans that may update our set of file items (which could change the generated name for a new document).
    
    handler = [[handler copy] autorelease];

    [_actionOperationQueue addOperationWithBlock:^{
        NSString *documentType = [self documentTypeForNewFiles];
        NSURL *newDocumentURL = [self urlForNewDocumentOfType:documentType];
        
        // We create documents in the ~/Documents directory at first and then if iCloud is on (and the delegate allows it), we move them into iCloud.
        OBASSERT(![[self scopeForFileURL:newDocumentURL] isUbiquitous]);
        
        [_nonretained_delegate createNewDocumentAtURL:newDocumentURL completionHandler:^(NSURL *createdURL, NSError *error){
            if (!createdURL) {
                _addItemAndNotifyHandler(self, handler, nil, error);
                return;
            }
            
            // Check if we should move the new document into iCloud, and do so.
            OFSDocumentStoreScope *scope = [self _defaultScope];
            if ([scope isUbiquitous]) {
                NSError *containerError = nil;
                
                NSURL *containerURL = [scope documentsURL:&containerError];
                if (!containerURL) {
                    _addItemAndNotifyHandler(self, handler, nil, containerError);
                    return;
                }
                
                [_actionOperationQueue addOperationWithBlock:^{
                    NSError *cloudError = nil;
                    NSURL *destinationURL = [self _moveURL:createdURL toCloud:YES error:&cloudError];
                    
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        if (!destinationURL) {
                            _addItemAndNotifyHandler(self, handler, nil, cloudError); // Though we may now have a local document...
                        } else {
                            _addItemAndNotifyHandler(self, handler, destinationURL, nil);
                        }
                    }];
                }];
            } else {
                _addItemAndNotifyHandler(self, handler, newDocumentURL, nil);
            }
        }];
    }];
}

// The documentation says to not call -setUbiquitous:itemAtURL:destinationURL:error: on the main thread to avoid possible deadlock.
- (void)moveFileItems:(NSSet *)fileItems toCloud:(BOOL)shouldBeInCloud completionHandler:(void (^)(OFSDocumentStoreFileItem *failingItem, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // since we'll send the completion handler back to the main thread, make sure we came from there
    
    // capture scope...
    completionHandler = [[completionHandler copy] autorelease];
    
    [_actionOperationQueue addOperationWithBlock:^{
        OFSDocumentStoreFileItem *failingFileItem = nil;
        NSError *error = nil;

        for (OFSDocumentStoreFileItem *fileItem in fileItems) {
            error = nil;
            if (![self _moveURL:fileItem.fileURL toCloud:shouldBeInCloud error:&error]) {
                failingFileItem = fileItem;
                break;
            }
        }
    
        if (completionHandler) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionHandler(failingFileItem, error);
            }];
        }
    }];
}

+ (BOOL)isZipUTI:(NSString *)uti;
{
    // Check both of the semi-documented system UTIs for zip (in case one goes away or something else weird happens).
    // Also check for a temporary hack UTI we had, in case the local LaunchServices database hasn't recovered.
    return UTTypeConformsTo((CFStringRef)uti, CFSTR("com.pkware.zip-archive")) ||
           UTTypeConformsTo((CFStringRef)uti, CFSTR("public.zip-archive")) ||
           UTTypeConformsTo((CFStringRef)uti, CFSTR("com.omnigroup.zip"));
}

- (void)cloneInboxItem:(NSURL *)inboxURL completionHandler:(void (^)(OFSDocumentStoreFileItem *newFileItem, NSError *errorOrNil))completionHandler;
{
    completionHandler = [[completionHandler copy] autorelease];
    
    void (^finishedBlock)(OFSDocumentStoreFileItem *newFileItem, NSError *errorOrNil) = ^(OFSDocumentStoreFileItem *newFileItem, NSError *errorOrNil) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            
            if (completionHandler) {
                completionHandler(newFileItem, errorOrNil);
            }
        }];
    };
    
    finishedBlock = [[finishedBlock copy] autorelease];
    
    [_actionOperationQueue addOperationWithBlock:^{
        if (![OFSDocumentStore isURLInInbox:inboxURL]) {
            finishedBlock(nil, nil);
            return;
        } 
        
        __block NSError *error = nil;
        NSString *uti = OFUTIForFileURLPreferringNative(inboxURL, &error);
        if (!uti) {
            finishedBlock(nil, error);
            return;
        }
        
        BOOL isZip = [[self class] isZipUTI:uti];
        OUUnzipArchive *archive = nil;
        if (isZip) {
            archive = [[[OUUnzipArchive alloc] initWithPath:[inboxURL path] error:&error] autorelease];
            if (!archive) {
                finishedBlock(nil, error);
                return;
            }
            
            // this validates that we have a zip with a single file or package
            uti = [self _fileTypeForDocumentInArchive:archive error:&error];
            if (!uti) {
                finishedBlock(nil, error);
                return;
            }
        }
        
        if (![_nonretained_delegate documentStore:self canViewFileTypeWithIdentifier:uti]) {
            // we're not going to delete the file in the inbox here, because another document store may want to lay claim to this inbox item. Give them a chance to. The calls to cleanupInboxItem: should be daisy-chained from OUISingleDocumentAppController or it's subclass.
            
            NSLog(@"Delegate says it cannot view file type \"%@\"", uti);

            NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
            OBASSERT(![NSString isEmptyString:appName]);

            NSError *utiShouldNotBeIncludedError = nil;
            NSString *title =  NSLocalizedStringFromTableInBundle(@"Unable to open file.", @"OmniFileStore", OMNI_BUNDLE, @"error title");
            NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ cannot open this type of file.", @"OmniFileStore", OMNI_BUNDLE, @"error description"), appName];
            OFSError(&utiShouldNotBeIncludedError, OFSCannotMoveItemFromInbox, title, description);
            
            finishedBlock(nil, utiShouldNotBeIncludedError);
            return;
        }

        NSURL *itemToMoveURL = nil;
        
        if (isZip) {
            OUUnzipEntry *entry = [[archive entries] objectAtIndex:0];
            NSString *fileName = [[[entry name] pathComponents] objectAtIndex:0];
            NSURL *unzippedFileURL = [archive URLByWritingTemporaryCopyOfTopLevelEntryNamed:fileName error:&error];
            if (!unzippedFileURL) {
                finishedBlock(nil, error);
                
                return;
            }
            // Zip file has been decompressed to unzippedFileURL
            itemToMoveURL = unzippedFileURL;
        }
        else {
            itemToMoveURL = inboxURL;
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self addDocumentWithScope:[self _defaultScope] inFolderNamed:nil fromURL:itemToMoveURL option:OFSDocumentStoreAddByRenaming completionHandler:finishedBlock];
        }];        
    }];
}

- (BOOL)deleteInbox:(NSError **)outError;
{
    // clean up by nuking the Inbox.
    __block BOOL success = NO;
    NSError *coordinatorError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:[[OFSDocumentStore userDocumentsDirectoryURL] URLByAppendingPathComponent:DocumentInteractionInbox isDirectory:YES]  options:NSFileCoordinatorWritingForDeleting error:&coordinatorError byAccessor:^(NSURL *newURL) {
        NSError *deleteError = nil;
        if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&deleteError]) {
            // Deletion of zip file failed.
            NSLog(@"Deletion of inbox file failed: %@", [deleteError toPropertyList]);
            return;
        }
        
        success = YES;
    }];
    [coordinator release];
    
    return success;
}

- (BOOL)_replaceURL:(NSURL *)fileURL withVersion:(NSFileVersion *)version replacing:(BOOL)replacing error:(NSError **)outError;
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSFileCoordinatorWritingOptions options = replacing ? NSFileCoordinatorWritingForReplacing : 0;
    
    __block BOOL success = NO;
    
    [coordinator coordinateWritingItemAtURL:fileURL options:options error:outError byAccessor:^(NSURL *newURL){
        // We don't pass NSFileVersionReplacingByMoving, leaving the version in place. It isn't clear if this is correct. We're going to mark it resolved if this all works, but it is unclear if that will clean it up.
        if (![version replaceItemAtURL:newURL options:0 error:outError]) {
            NSLog(@"Error replacing %@ with version %@: %@", fileURL, newURL, outError ? [*outError toPropertyList] : @"???");
            return;
        }
        
        success = YES;
    }];
    [coordinator release];

    return success;
}

- (void)resolveConflictForFileURL:(NSURL *)fileURL keepingFileVersions:(NSArray *)keepFileVersions completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    completionHandler = [[completionHandler copy] autorelease]; // capture scope
    
    void (^callCompletion)(NSError *e) = ^(NSError *e){
        if (completionHandler)
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{ completionHandler(e); }];
    };
    callCompletion = [[callCompletion copy] autorelease];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        NSFileVersion *originalVersion = [NSFileVersion currentVersionOfItemAtURL:fileURL];
        NSArray *allConflictVersions = [NSFileVersion unresolvedConflictVersionsOfItemAtURL:fileURL];
        
        NSUInteger keptFileVersionCount = [keepFileVersions count];
        NSFileVersion *firstKeptFileVersion = [keepFileVersions objectAtIndex:0];
        
        // Can't pointer-compare NSFileVersions since new instances are returned from each call of +currentVersionOfItemAtURL:
        if (![firstKeptFileVersion isEqual:originalVersion]) {
            // This version is going to replace the current version. replacing==YES means that the coordinated write will preserve the identity of the file, rather than looking like a delete of the original and a new file being created in its place.
            NSError *error = nil;
            if (![self _replaceURL:fileURL withVersion:firstKeptFileVersion replacing:YES error:&error]) {
                callCompletion(error);
                return;
            }
        }
        
        // Make new files for any other versions to be preserved
        if (keptFileVersionCount >= 2) {
            NSMutableSet *usedFileNames = [[self _copyCurrentlyUsedFileNames:nil] autorelease];
            
            NSString *originalFileName = [fileURL lastPathComponent];
            NSString *originalBaseName = nil;
            NSUInteger counter;
            [[originalFileName stringByDeletingPathExtension] splitName:&originalBaseName andCounter:&counter];
            NSString *originalPathExtension = [originalFileName pathExtension];
            
            NSURL *originalContainerURL = [fileURL URLByDeletingLastPathComponent];

            for (NSUInteger keptVersionIndex = 1; keptVersionIndex < keptFileVersionCount; keptVersionIndex++) {
                NSFileVersion *pickedVersion = [keepFileVersions objectAtIndex:keptVersionIndex];
                NSString *fileName = _availableName(usedFileNames, originalBaseName, originalPathExtension, &counter);

                NSURL *replacementURL = [originalContainerURL URLByAppendingPathComponent:fileName];
                
                NSError *error = nil;
                if (![self _replaceURL:replacementURL withVersion:pickedVersion replacing:NO error:&error]) {
                    callCompletion(error);
                    return;
                }
            }
        }
        
        // Only mark versions resolved if we had no errors.
        // The documentation makes no claims about whether this is considered an operation that needs file coordination...
        for (NSFileVersion *fileVersion in allConflictVersions) {
            OBASSERT(fileVersion != originalVersion);
            OBASSERT(fileVersion.conflict == YES);

            fileVersion.resolved = YES;
        }

        callCompletion(nil);
    }];
}

#endif

- (OFSDocumentStoreScope *)defaultUbiquitousScope;
{
    OBPRECONDITION([_ubiquitousScopes count] < 2); // No way to determine which is the default

    return [_ubiquitousScopes lastObject];
}

#pragma mark -
#pragma mark Private

// The top level is useful for settings and non-document type stuff, but NSMetadataQuery will only look in the Documents folder.
+ (NSURL *)_ubiquityContainerURL;
{
    return [[OFSDocumentStoreScope defaultUbiquitousScope] containerURL];
}

- (OFSDocumentStoreScope *)_defaultScope;
{
    OFSDocumentStoreScope *scope = nil;
    
    if ([OFSDocumentStore isUbiquityAccessEnabled] && 
        [_ubiquitousScopes count] > 0)
        scope = [self defaultUbiquitousScope];
    
    if (![scope documentsURL:NULL]) {
        scope = _localScope;
    }
   
    return scope;
}

- (NSArray *)_scanItemsDirectoryURLs;
{
    NSMutableArray *directoryURLs = [NSMutableArray array];
    
    // Scan our local ~/Documents if we have one.
    if (_localScope)
        [directoryURLs addObject:[_localScope documentsURL:NULL]];
    
    // Don't scan the ubiquity directory unless we have NSMetadataItems to match up with them.
    if ([OFSDocumentStore isUbiquityAccessEnabled] && _metadataInitialScanFinished) {
        // In addition to scanning our local Documents directory (on iPad, at least), we also scan our ubiquity container directly, if enabled.
        // Talking to Apple, the top-level entries in the container are intended to be present (and empty directory for a wrapper, for example). The metadata can lag behind the state of the filesystem, particularly for locally invoked operations. We don't want to create items based solely on the presense of a metadata item since then a delete of a file wouldn't produce a remove of the file item until after the metadata update.
        for (OFSDocumentStoreScope *_scope in _ubiquitousScopes) {
            NSURL *ubiquityDocumentsURL = [_scope documentsURL:NULL];
            if  (ubiquityDocumentsURL)
                [directoryURLs addObject:ubiquityDocumentsURL];
        }
    }
    
    return directoryURLs;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (BOOL)isURLInInbox:(NSURL *)url;
{
    // Check to see if the URL directly points to the Inbox.
    if (([[url lastPathComponent] caseInsensitiveCompare:DocumentInteractionInbox] == NSOrderedSame)) {
        return YES;
    }
    
    // URL does not directly point to Inbox, check if it points to a file directly in the Inbox.
    NSURL *pathURL = [url URLByDeletingLastPathComponent]; // Remove the filename.
    NSString *lastPathComponentString = [pathURL lastPathComponent];
    
    return ([lastPathComponentString caseInsensitiveCompare:DocumentInteractionInbox] == NSOrderedSame);
}

- (NSURL *)_moveURL:(NSURL *)sourceURL toCloud:(BOOL)shouldBeInCloud error:(NSError **)outError;
{
    OBPRECONDITION(sourceURL);
    
    NSURL *targetDocumentsURL;
    if (shouldBeInCloud) {
        OFSDocumentStoreScope *ubiquitousScope = [self defaultUbiquitousScope];
        if (!(targetDocumentsURL = [ubiquitousScope documentsURL:outError]))
            return NO;
    } else {
        // Check to make sure sourceURL is eligible to be moved out of iCloud.
        NSNumber *sourceIsDownloaded = nil;
        NSNumber *sourceHasUnresolvedConflicts = nil;
        NSError *error = nil;

        if (![sourceURL getResourceValue:&sourceIsDownloaded forKey:NSURLUbiquitousItemIsDownloadedKey error:&error]) {
             NSLog(@"Error checking if source URL %@ is downloaded: %@", [sourceURL absoluteString], [error toPropertyList]);
        }
        
        if ([sourceIsDownloaded boolValue] == NO) {
            NSLog(@"Source URL %@ is not fully downloaded.", sourceURL);
            
            NSString *title =  NSLocalizedStringFromTableInBundle(@"Cannot move item out of iCloud.", @"OmniFileStore", OMNI_BUNDLE, @"error title");
            NSString *description = NSLocalizedStringFromTableInBundle(@"This item is not fully downloaded and cannot be moved out of iCloud. Tap the document to begin the download.", @"OmniFileStore", OMNI_BUNDLE, @"not fully downloaded error description");
            
            OFSError(outError, OFSUbiquitousItemNotDownloaded, title, description);
            
            return nil;
        }
        
        if (![sourceURL getResourceValue:&sourceHasUnresolvedConflicts forKey:NSURLUbiquitousItemHasUnresolvedConflictsKey error:&error]) {
            NSLog(@"Error checking if source URL %@ is has unresolved conflicts: %@", [sourceURL absoluteString], [error toPropertyList]);
        }
        
        if ([sourceHasUnresolvedConflicts boolValue]) {
            NSLog(@"Source URL %@ has unresolved conflicts.", sourceURL);
            
            NSString *title =  NSLocalizedStringFromTableInBundle(@"Cannot move item out of iCloud.", @"OmniFileStore", OMNI_BUNDLE, @"error title");
            NSString *description = NSLocalizedStringFromTableInBundle(@"This item has unresolved conflicts and cannot be moved out of iCloud.", @"OmniFileStore", OMNI_BUNDLE, @"unresolved conflicts error description");
            
            OFSError(outError, OFSUbiquitousItemInConflict, title, description);
            
            return nil;
        }
        
        targetDocumentsURL = [_localScope documentsURL:outError];
    }
    
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

- (NSURL *)_urlForScope:(OFSDocumentStoreScope *)scope folderName:(NSString *)folderName fileName:(NSString *)fileName error:(NSError **)outError;
{
    OBPRECONDITION(fileName);
    
    NSURL *url = [scope documentsURL:outError];
    if (!url)
        return nil;
    
    if (folderName)
        url = [url URLByAppendingPathComponent:folderName];
    
    return [url URLByAppendingPathComponent:fileName];
}

// Track whether the user would like to have iCloud documents shown (assuming iCloud is even enabled).
- (void)_ubiquityAllowedPreferenceChanged:(NSNotification *)note;
{
    [self _stopMetadataQuery];
    [self _startMetadataQuery];
    
    [self _postUbiquityEnabledChangedIfNeeded];

    if (_metadataQuery) {
        // Scan will happen when the query finishes
    } else {
        [self scanItemsWithCompletionHandler:nil];
    }
}

- (void)_postUbiquityEnabledChangedIfNeeded;
{
    BOOL ubiquityEnabled = [[self class] isUbiquityAccessEnabled];
    if (_lastNotifiedUbiquityEnabled ^ ubiquityEnabled) {
        _lastNotifiedUbiquityEnabled = ubiquityEnabled;
        [[NSNotificationCenter defaultCenter] postNotificationName:OFSDocumentStoreUbiquityEnabledChangedNotification object:self];
    }
}

- (void)_startMetadataQuery;
{
    if (_metadataQuery)
        return;

#if !USE_METADATA_QUERY
    return;
#endif
    
    if ([[self class] isUbiquityAccessEnabled] == NO)
        return;
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if (!_netReachability) {
        _netReachability = [[OFNetReachability alloc] initWithDefaultRoute:YES/*ignore ad-hoc wi-fi*/];
    }
#endif
    
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
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [_netReachability release];
    _netReachability = nil;
#endif
}

- (void)_metadataQueryDidStartGatheringNotifiction:(NSNotification *)note;
{
    OBPRECONDITION([NSThread isMainThread]);

    DEBUG_METADATA(@"note %@", note);
    //    NSLog(@"results = %@", [self.metadataQuery results]);
}

- (void)_metadataQueryDidGatheringProgressNotifiction:(NSNotification *)note;
{
    OBPRECONDITION([NSThread isMainThread]);

    DEBUG_METADATA(@"note %@", note);
    DEBUG_METADATA(@"results = %@", [_metadataQuery results]);
}

// We only get this on the first metadata update
- (void)_metadataQueryDidFinishGatheringNotifiction:(NSNotification *)note;
{
    OBPRECONDITION([NSThread isMainThread]);

    DEBUG_METADATA(@"note %@", note);
    DEBUG_METADATA(@"results = %@", [_metadataQuery results]);
    
    _metadataInitialScanFinished = YES;
    _metadataUpdateVersionNumber++;
    
    [self scanItemsWithCompletionHandler:nil];
}

// ... after the first 'finish gathering', all incremental updates go through here
- (void)_metadataQueryDidUpdateNotifiction:(NSNotification *)note;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_METADATA(@"note %@", note);
    DEBUG_METADATA(@"results = %@", [_metadataQuery results]);
    
    _metadataUpdateVersionNumber++;
    
    NSArray *actions = [_afterMetadataUpdateActions autorelease];
    _afterMetadataUpdateActions = nil;

    [self _performActions:actions];

    // Without this, if you tap on a file that isn't downloaded, when the download finishes (or presumably progresses), the file item isn't updated. If this is too slow, maybe we can record notes about which file items need their metadata update applied and only do that here instead of a full scan.
    [self scanItemsWithCompletionHandler:nil];
}

- (void)_flushAfterInitialDocumentScanActions;
{
    if (!self.hasFinishedInitialMetdataQuery)
        return;
    
    if (_afterInitialDocumentScanActions) {
        NSArray *actions = [_afterInitialDocumentScanActions autorelease];
        _afterInitialDocumentScanActions = nil;
        [self _performActions:actions];
    }
    
    if (_afterMetadataUpdateActions) {
        NSArray *actions = [_afterMetadataUpdateActions autorelease];
        _afterMetadataUpdateActions = nil;
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

- (OFSDocumentStoreFileItem *)_newFileItemForURL:(NSURL *)fileURL date:(NSDate *)date;
{
    // This assumes that the choice of file item class is consistent for each URL (since we will reuse file item).  Could double-check in this loop that the existing file item has the right class if we ever want this to be dynamic.
    Class fileItemClass = [_nonretained_delegate documentStore:self fileItemClassForURL:fileURL];
    if (!fileItemClass) {
        // We have a UTI for this, but the delegate doesn't want it to show up in the listing (OmniGraffle templates, for example).
        return nil;
    }
    OBASSERT(OBClassIsSubclassOfClass(fileItemClass, [OFSDocumentStoreFileItem class]));
    
#ifdef OMNI_ASSERTIONS_ON
    for (id <NSFilePresenter> presenter in [NSFileCoordinator filePresenters]) {
        if ([presenter isKindOfClass:[OFSDocumentStoreFileItem class]]) {
            OFSDocumentStoreFileItem *otherFileItem  = (OFSDocumentStoreFileItem *)presenter;
            if (otherFileItem.beingDeleted)
                continue; // Replacing a file with a new one.
        }
        OBASSERT(OFNOTEQUAL(_fileItemCacheKeyForURL(presenter.presentedItemURL), _fileItemCacheKeyForURL(fileURL)));
    }
#endif
    
    OFSDocumentStoreFileItem *fileItem = [[fileItemClass alloc] initWithDocumentStore:self fileURL:fileURL date:date];

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Shouldn't make file items for files we can't view.
    OBASSERT([_nonretained_delegate documentStore:self canViewFileTypeWithIdentifier:fileItem.fileType]);
#endif

    DEBUG_STORE(@"  made new file item %@ for %@", fileItem, fileURL);

    return fileItem;
}

- (void)_possiblyRequestDownloadOfNewlyAddedUbiquitousFileItem:(OFSDocumentStoreFileItem *)fileItem metadataItem:(NSMetadataItem *)metadataItem;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // The first time we see an item for a URL (newly created or once at app launch), automatically start downloading it if it is "small" and we are on wi-fi. iWork seems to automatically download files in some cases where normal iCloud apps don't. Unclear what rules they uses.
    
    if (fileItem.isDownloaded || !_netReachability.reachable || _netReachability.usingCell)
        return;
        
    NSNumber *size = [metadataItem valueForAttribute:NSMetadataItemFSSizeKey]; // Experimentally, this returns the total size for file wrappers. Nice!
    OBASSERT(size);
    if (!size)
        return;
    
    NSUInteger maximumAutomaticDownloadSize = [[OFPreference preferenceForKey:@"OFSDocumentStoreMaximumAutomaticDownloadSize"] unsignedIntegerValue];
    
    if ([size unsignedLongLongValue] <= (unsigned long long)maximumAutomaticDownloadSize) {
        NSError *downloadError = nil;
        //NSLog(@"Reqesting download of %@ (size %@)", fileItem.fileURL, size);
        if (![fileItem requestDownload:&downloadError]) {
            NSLog(@"automatic download request for %@ failed with %@", fileItem.fileURL, [downloadError toPropertyList]);
        }
    }
#endif
}

- (NSString *)_singleTopLevelEntryNameInArchive:(OUUnzipArchive *)archive directory:(BOOL *)directory error:(NSError **)error;
{
    OBPRECONDITION(archive);
    
    NSString *topLevelEntryName = nil;
        
    if ([[archive entries] count] == 1) {
        // if there's only 1 entry, it should not be a directory
        *directory = NO;
        OUUnzipEntry *entry = [[archive entries] objectAtIndex:0];
        if (![[entry name] hasSuffix:@"/"]) {
            // This zip contains a single file.
            topLevelEntryName = [entry name];
        }
    }
    else if ([[archive entries] count] > 1) {
        // it's a multi-entry zip. All the entries should have the same prefix.
        *directory = YES;
        
        // Filter out unwanted entries (Ex. __MACOSX dir).
        NSArray *filteredEntries = [[archive entries] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            OUUnzipEntry *entry = (OUUnzipEntry *)evaluatedObject;
            NSString *name = [entry name];
            
            NSRange prefixRange = [name rangeOfString:@"__MACOSX" options:(NSAnchoredSearch | NSCaseInsensitiveSearch)];
            if (prefixRange.location != NSNotFound) {
                return NO;
            }

            return YES;
        }]];
        
        // sort entries by length so that the top level directory comes to the top
        NSArray *filteredAndSortedEntries = [filteredEntries sortedArrayUsingComparator:^(id entry1, id entry2) {
            return ([[entry1 name] caseInsensitiveCompare:[entry2 name]]);
        }];
        
        NSString *topLevelFileName = [[filteredAndSortedEntries objectAtIndex:0] name];
        BOOL invalidStructure = [filteredAndSortedEntries anyObjectSatisfiesPredicate:^BOOL(id object) {
            // invalid if any entry name does not start with topLevelFileName.
            OUUnzipEntry *entry = (OUUnzipEntry *)object;
            return ([[entry name] hasPrefix:topLevelFileName] == NO);
        }];
        
        // If the structure if valid, return topLevelFileName
        if (invalidStructure == NO) {
            topLevelEntryName = topLevelFileName;
        }
    }
    
    if (!topLevelEntryName) {
        // Something has gone wrong. Let's fill in Error.
        NSString *title =  NSLocalizedStringFromTableInBundle(@"Invalid Zip Archive", @"OmniFileStore", OMNI_BUNDLE, @"error title");
        NSString *description = NSLocalizedStringFromTableInBundle(@"The zip archive must contain a single document.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        
        OFSError(error, OFSInvalidZipArchive, title, description);
    }
    
    // By now topLevelEntryName will either have a name or be nil. If it's nil, the error will be filled in.
    return topLevelEntryName;
}

- (NSString *)_fileTypeForDocumentInArchive:(OUUnzipArchive *)archive error:(NSError **)error; // returns the UTI, or nil if there was an error
{
    OBPRECONDITION(archive);
    
    BOOL isDirectory = NO;
    NSString *topLevelEntryName = [self _singleTopLevelEntryNameInArchive:archive directory:&isDirectory error:error];
    if (!topLevelEntryName)
        return nil;
    
    
    return OFUTIForFileExtensionPreferringNative([topLevelEntryName pathExtension], [NSNumber numberWithBool:isDirectory]);
}

- (NSMutableSet *)_copyCurrentlyUsedFileNames:(OFSDocumentStoreScope *)scope ignoringFileURL:(NSURL *)fileURLToIgnore;
{
    // Collecting the names asynchronously from filesystem edits will yield out of date results. We still have race conditions with iCloud adding/removing files since coordinated reads of whole Documents directories does nothing to block writers.
    OBPRECONDITION([NSOperationQueue currentQueue] == _actionOperationQueue);

    NSMutableSet *usedFileNames = [[NSMutableSet alloc] init];
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // iPad apps always collect the same file names regardless of input scope; but, let's check to make sure things are setup correctly
    OBASSERT(_localScope);
    [self _addCurrentlyUsedFileNames:usedFileNames inScope:_localScope ignoringFileURL:fileURLToIgnore];
    if ([OFSDocumentStore isUbiquityAccessEnabled]) {
        OBASSERT([_ubiquitousScopes lastObject] == [self defaultUbiquitousScope]);
        [self _addCurrentlyUsedFileNames:usedFileNames inScope:[self defaultUbiquitousScope] ignoringFileURL:fileURLToIgnore];
    }
#else
    OBASSERT(_localScope == nil);
    OBASSERT([scope isUbiquitous]);
    [self _addCurrentlyUsedFileNames:usedFileNames inScope:scope ignoringFileURL:fileURLToIgnore];
#endif
    
    return usedFileNames;
}

- (NSMutableSet *)_copyCurrentlyUsedFileNames:(OFSDocumentStoreScope *)scope;
{
    return [self _copyCurrentlyUsedFileNames:scope ignoringFileURL:nil];
}

- (void)_addCurrentlyUsedFileNames:(NSMutableSet *)fileNames inScope:(OFSDocumentStoreScope *)scope ignoringFileURL:(NSURL *)fileURLToIgnore;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _actionOperationQueue);

    if (![scope documentsURL:NULL])
        return;

    NSError *error = nil;
    NSURL *documentsURL = [scope documentsURL:&error];
    if (!documentsURL) {
        if ([error causedByUserCancelling]) {
            OBASSERT([scope isUbiquitous]); // Should only happen when Documents & Data is turned off
        } else {
            NSLog(@"Error getting documents URL for scope %@: %@", [scope shortDescription], [error toPropertyList]);
        }
        return;
    }
    
    fileURLToIgnore = [fileURLToIgnore URLByStandardizingPath];
    
    _scanDirectoryURL(self, documentsURL, ^(NSFileManager *fileManager, NSURL *fileURL){
        if (fileURLToIgnore && [fileURLToIgnore isEqual:[fileURL URLByStandardizingPath]])
            return;
        [fileNames addObject:[fileURL lastPathComponent]];
    });
}
        
// We CANNOT check for file non-existence here. iCloud documents may be present on the server and we may only know about them via an NSMetadataQuery update that produced an OFSDocumentStoreFileItem. Also, iWork tries to avoid duplicate file names across folders and storage scopes. So, we take in an array of URLs and unique against that.
static NSString *_availableName(NSSet *usedFileNames, NSString *baseName, NSString *extension, NSUInteger *ioCounter)
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
            return [candidateName autorelease];
        }
        [candidateName release];
    }
}

- (NSString *)_availableFileNameAvoidingUsedFileNames:(NSSet *)usedFilenames withBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    OBPRECONDITION(_fileItems); // Make sure we've done a local scan. It might be out of date, so maybe we should scan here too.
    OBPRECONDITION(self.hasFinishedInitialMetdataQuery); // We can't unique against iCloud until whe know what is there
    
    return _availableName(usedFilenames, baseName, extension, ioCounter);
}

- (NSString *)_availableFileNameWithBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter scope:(OFSDocumentStoreScope *)scope;
{
    NSSet *usedFileNames = [self _copyCurrentlyUsedFileNames:scope];
    NSString *fileName = [self _availableFileNameAvoidingUsedFileNames:usedFileNames withBaseName:baseName extension:extension counter:ioCounter];
    [usedFileNames release];
    return fileName;
}

- (NSURL *)_availableURLInDirectoryAtURL:(NSURL *)directoryURL baseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter scope:(OFSDocumentStoreScope *)scope;
{
    NSString *availableFileName = [self _availableFileNameWithBaseName:baseName extension:extension counter:ioCounter scope:scope];
    return [directoryURL URLByAppendingPathComponent:availableFileName];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSURL *)_availableURLWithFileName:(NSString *)fileName;
{
    NSString *originalName = [fileName stringByDeletingPathExtension];
    NSString *extension = [fileName pathExtension];
    
    // If the file item name ends in a number, we are likely duplicating a duplicate.  Take that as our starting counter.  Of course, this means that if we duplicate "Revenue 2010", we'll get "Revenue 2011". But, w/o this we'll get "Revenue 2010 2", "Revenue 2010 2 2", etc.
    NSString *baseName = nil;
    NSUInteger counter;
    [originalName splitName:&baseName andCounter:&counter];
    
    return [self _availableURLInDirectoryAtURL:[[self class] userDocumentsDirectoryURL]
                                      baseName:baseName
                                     extension:extension
                                       counter:&counter
                                         scope:[self _defaultScope]];
}
#endif

- (NSURL *)_renameTargetURLForFileItem:(OFSDocumentStoreFileItem *)fileItem usedFilenames:(NSSet *)usedFilenames counter:(NSUInteger *)ioCounter;
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
        
        if (containingFolderName) {
            // Documents with the same name in different folders get the "(foldername)" appended.
            NSString *localFileName = [currentURL lastPathComponent];
            candidate = [localFileName stringByDeletingPathExtension];
            candidate = [candidate stringByAppendingFormat:@" (%@)", containingFolderName];
            candidate = [candidate stringByAppendingPathExtension:[localFileName pathExtension]];
        } else {
            // Just update the counter. This might be a local vs. iCloud conflict -- the local copy will get the "not in cloud" badge.
            candidate = [currentURL lastPathComponent];
        }
    }
    
    // Then unique the candidate versus whatever else we have.
    NSString *fileName = candidate;
    NSString *baseName = nil;
    NSUInteger counter;
    [[fileName stringByDeletingPathExtension] splitName:&baseName andCounter:&counter];
    
    fileName = [self _availableFileNameWithBaseName:baseName extension:[fileName pathExtension] counter:&counter scope:[self scopeForFileURL:currentURL]];
    
    return [[currentURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:fileName];
}

#if defined(OMNI_ASSERTIONS_ON) || !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
// calls to -[OFSDocumentStoreScope containerURL], which is called by -scopeForFileURL, can be expensive since it uses -[NSFileManager URLForUbiquityContainerIdentifier:] so the following two convenience methods 'cache' the containerURL
static OFSDocumentStoreScope *_scopeForFileURL(NSDictionary *scopeToContainerURL, NSURL *fileURL)
{
    __block OFSDocumentStoreScope *scope = nil;
    [scopeToContainerURL enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        OBASSERT([(NSObject *)key isKindOfClass:[OFSDocumentStoreScope class]]);
        OBASSERT([(NSObject *)obj isKindOfClass:[NSURL class]]);
        
        if ([OFSDocumentStoreScope isFile:fileURL inContainer:(NSURL *)obj]) {
            scope = (OFSDocumentStoreScope *)key;
            *stop = YES;
        }
    }];
    
    return scope;
}

static NSDictionary *_scopeToContainerURL(OFSDocumentStore *docStore)
{
    NSMutableDictionary *scopeToContainerURL = [NSMutableDictionary dictionary];
    
    if (docStore->_localScope) {
        NSError *error = nil;
        NSURL *documentsURL = [docStore->_localScope documentsURL:&error];
        if (!documentsURL) {
            NSLog(@"Error requesting documentsURL: %@", [error toPropertyList]);
            return nil;
        }
        
        OFSDocumentStoreScope *localScope = docStore->_localScope;
        
        [scopeToContainerURL setObject:documentsURL forKey:localScope];
    }
    
    for (OFSDocumentStoreScope *ubiquitousScope in docStore->_ubiquitousScopes) {
        NSURL *containerURL = [ubiquitousScope containerURL];
        if (containerURL)
            [scopeToContainerURL setObject:containerURL forKey:ubiquitousScope];
    }
    
    return scopeToContainerURL;
}
#endif

- (void)_checkFileItemsForUniqueFileNames;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // A previous set of rename operations is still enqueued.
    if (_isRenamingFileItemsToHaveUniqueFileNames)
        return;
    
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSDictionary *scopeToContainerURL = _scopeToContainerURL(self);
#endif
    
    NSMutableDictionary *nameToFileItems = [[NSMutableDictionary alloc] init];
    
    for (OFSDocumentStoreFileItem *fileItem in _fileItems) {
        NSMutableArray *items = [nameToFileItems objectForKey:fileItem.name];
        if (!items) {
            items = [NSMutableArray arrayWithObject:fileItem];
            [nameToFileItems setObject:items forKey:fileItem.name];
        } else
            [items addObject:fileItem];
    }
    
    NSMutableArray *pendingRenameNotificationOperations = nil;
    
    for (NSString *name in nameToFileItems) {
        NSMutableArray *fileItems = [nameToFileItems objectForKey:name];
        NSUInteger fileItemCount = [fileItems count];
        if (fileItemCount < 2)
            continue;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        NSOperation *renameOperation = [self _renameFileItemsToHaveUniqueFileNames:fileItems withScope:[self defaultUbiquitousScope]];
        if (!pendingRenameNotificationOperations)
            pendingRenameNotificationOperations = [NSMutableArray array];
        [pendingRenameNotificationOperations addObject:renameOperation];
#else
        NSMutableDictionary *fileItemsByScope = [[NSMutableDictionary alloc] init];
        
        for (OFSDocumentStoreFileItem *fileItem in fileItems) {
            OFSDocumentStoreScope *fileItemScope = _scopeForFileURL(scopeToContainerURL, fileItem.fileURL);
            if (!fileItemScope)
                fileItemScope = [self _defaultScope];
            OBASSERT([fileItemScope isUbiquitous]);
            NSMutableArray *items = [fileItemsByScope objectForKey:fileItemScope];
            if (!items) {
                items = [NSMutableArray arrayWithObject:fileItem];
                [fileItemsByScope setObject:items forKey:fileItemScope];
            } else
                [items addObject:fileItem];
        }
        
        for (OFSDocumentStoreScope *scope in fileItemsByScope) {
            NSMutableArray *fileItems = [fileItemsByScope objectForKey:scope];
            NSUInteger fileItemCount = [fileItems count];
            if (fileItemCount < 2)
                continue;
            
            NSOperation *renameOperation = [self _renameFileItemsToHaveUniqueFileNames:fileItems withScope:scope];
            if (!pendingRenameNotificationOperations)
                pendingRenameNotificationOperations = [NSMutableArray array];
            [pendingRenameNotificationOperations addObject:renameOperation];
        }
        
        [fileItemsByScope release];
#endif
    }
    
    [nameToFileItems release];
    
    // If we did end up staring a rename, queue up a block to turn off this flag (we'll avoid futher uniquing operations until this completes).
    if (_isRenamingFileItemsToHaveUniqueFileNames) {
        OBASSERT([pendingRenameNotificationOperations count] > 0);
        
        DEBUG_UNIQUE("Need to wait for operations %@", pendingRenameNotificationOperations);

        // Queue up an operation on the main thread to turn off the renaming flag, but only after all the presenters involved have heard about it.
        NSOperation *allRenamesFinished = [NSBlockOperation blockOperationWithBlock:^{
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                DEBUG_UNIQUE("Finished");
                OBASSERT(_isRenamingFileItemsToHaveUniqueFileNames == YES);
                _isRenamingFileItemsToHaveUniqueFileNames = NO; 
            }];
        }];
        
        for (NSOperation *dependency in pendingRenameNotificationOperations)
            [allRenamesFinished addDependency:dependency];

        [NotificationCompletionQueue addOperation:allRenamesFinished];
    }
}

/*
 Given a set of file items that were just scanned, make sure the file names are unique enough.
 There is a bit of a race condition here in that we are looking at the file names on the main thread.
 The accessors are atomic, but we might make renaming decisions that are bit out of date.
 We could restructure this so that it operates as part of the scan action, but the benefit is probably pretty low and the complexity is moderately high (since we need to apply the metadata results from the main thread).
 */
- (NSOperation *)_renameFileItemsToHaveUniqueFileNames:(NSMutableArray *)fileItems withScope:(OFSDocumentStoreScope *)scope;
{
    OBPRECONDITION([fileItems count] >= 2);
    
    // Note that we actually started a rename
    _isRenamingFileItemsToHaveUniqueFileNames = YES;
    
    // Make an empty operation that we'll return to signal our completion. We wait to add it to the queue until after we have established its dependencies.
    NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{}];

    [self performAsynchronousFileAccessUsingBlock:^{
        
        // Sort the items into a deterministic order (as best we can) so that two different devices will perform the same renames.
        // Also, let items in the cloud have higher precedence so that there is reduced chance of conflict.
        [fileItems sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            OFSDocumentStoreFileItem *fileItem1 = obj1;
            OFSDocumentStoreFileItem *fileItem2 = obj2;
            
            OFSDocumentStoreScope *scope1 = [self scopeForFileURL:fileItem1.fileURL];
            OFSDocumentStoreScope *scope2 = [self scopeForFileURL:fileItem2.fileURL];
            
            BOOL isUbiquitous1 = [scope1 isUbiquitous];
            BOOL isUbiquitous2 = [scope2 isUbiquitous];
            
            if (isUbiquitous1 != isUbiquitous2) {
                if (isUbiquitous1 == YES)
                    return NSOrderedAscending;
                if (isUbiquitous2 == YES)
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
        NSMutableSet *usedFilenames = [self _copyCurrentlyUsedFileNames:scope];
        DEBUG_UNIQUE("Avoiding file names %@", usedFilenames);
        
        NSUInteger counter = 0;
        NSUInteger fileItemCount = [fileItems count];
        for (NSUInteger fileItemIndex = 1; fileItemIndex < fileItemCount; fileItemIndex++) {
            OFSDocumentStoreFileItem *fileItem = [fileItems objectAtIndex:fileItemIndex];
            NSURL *sourceURL = fileItem.fileURL;
            NSURL *targetURL = [self _renameTargetURLForFileItem:fileItem usedFilenames:usedFilenames counter:&counter];
            DEBUG_UNIQUE("Moving %@ to %@", sourceURL, targetURL);
            
            // Mark this file name as used, though we won't have seen the file presenter notification for it yet.
            [usedFilenames addObject:[targetURL lastPathComponent]];
            
            // _coordinatedMoveItem expects us to have copied the completion block already.
            void (^notificationBlock)(NSURL *destinationURL, NSError *errorOrNil) = ^(NSURL *destinationURL, NSError *errorOrNil){
                DEBUG_UNIQUE("Finished moving %@ to %@", sourceURL, targetURL);
                if (!destinationURL)
                    NSLog(@"Error performing rename for uniqueness of %@ to %@: %@", sourceURL, targetURL, [errorOrNil toPropertyList]);
            };
            notificationBlock = [[notificationBlock copy] autorelease];
            
            NSOperation *presenterNotified = _coordinatedMoveItem(self, fileItem, sourceURL, targetURL, NotificationCompletionQueue, notificationBlock);
            [op addDependency:presenterNotified];
        }
        [usedFilenames release];
        
        // Now that we have the dependencies set up, we can add this to a queue so the original caller can tell when we are done. This doesn't really do an action, and we don't want any chance of dependency deadlock, so we have a concurrent queue we'll add it to.
        [NotificationCompletionQueue addOperation:op];
    }];
    
    return op;
}

// Called by file items when they move -- we just dispatch to our delegate (on iOS this lets the document picker move the previews along for local and incoming moves).
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentStore:fileWithURL:andDate:didMoveToURL:)])
        [_nonretained_delegate documentStore:self fileWithURL:oldURL andDate:date didMoveToURL:newURL];
}

// Called internally
- (void)_fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentStore:fileWithURL:andDate:didCopyToURL:andDate:)])
        [_nonretained_delegate documentStore:self fileWithURL:oldURL andDate:date didCopyToURL:newURL andDate:newDate];
}

// Called by file items when they gain/lose a version or a conflict version is marked resolved. Dispatch to the delegate to update previews.
- (void)_fileItem:(OFSDocumentStoreFileItem *)fileItem didGainVersion:(NSFileVersion *)fileVersion;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentStore:fileItem:didGainVersion:)])
        [_nonretained_delegate documentStore:self fileItem:fileItem didGainVersion:fileVersion];
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

#endif // OFS_DOCUMENT_STORE_SUPPORTED
