// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStore.h>

#import <OmniFileStore/OFSFeatures.h>

#if OFS_DOCUMENT_STORE_SUPPORTED

#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFileStore/OFSDocumentStoreDelegate.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFileStore/OFSDocumentStoreGroupItem.h>
#import <OmniUnzip/OUUnzipArchive.h>

#import "Errors.h"
#import "OFSShared_Prefix.h"
#import "OFSDocumentStoreItem-Internal.h"
#import "OFSDocumentStoreFileItem-Internal.h"

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

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
static NSString *_folderFilename(NSURL *fileURL)
{
    NSURL *containerURL = [fileURL URLByDeletingLastPathComponent];
    if (_isFolder(containerURL))
        return [containerURL lastPathComponent];
    return nil;
}
#endif

@interface OFSDocumentStore ()

+ (NSURL *)_ubiquityContainerURL;
+ (NSURL *)_ubiquityDocumentsURL:(NSError **)outError;
- (NSArray *)_scanItemsDirectoryURLs;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (OFSDocumentStoreScope)_defaultScope;
- (NSURL *)_containerURLForScope:(OFSDocumentStoreScope)scope error:(NSError **)outError;
- (NSURL *)_urlForScope:(OFSDocumentStoreScope)scope folderName:(NSString *)folderName fileName:(NSString *)fileName error:(NSError **)outError;
- (NSURL *)_moveURL:(NSURL *)sourceURL toCloud:(BOOL)shouldBeInCloud error:(NSError **)outError;
#endif

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
- (NSMutableSet *)_copyCurrentlyUsedFileNames;
- (BOOL)_addCurrentlyUsedFileNames:(NSMutableSet *)fileNames inDirectoryURL:(NSURL *)directoryURL usingCoordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;
- (NSURL *)_renameTargetURLForFileItem:(OFSDocumentStoreFileItem *)fileItem usedFilenames:(NSSet *)usedFilenames counter:(NSUInteger *)ioCounter;
- (void)_renameFileItemsToHaveUniqueFileNames;

@end

@implementation OFSDocumentStore
{
    // NOTE: There is no setter for this; we currently make some calls to the delegate from a background queue and just use the ivar.
    id <OFSDocumentStoreDelegate> _nonretained_delegate;
    NSURL *_directoryURL;
    
    NSMetadataQuery *_metadataQuery;
    BOOL _metadataInitialScanFinished;
    NSMutableArray *_afterInitialDocumentScanActions;

    BOOL _isScanningItems;
    NSMutableArray *_deferredScanCompletionHandlers;
    
    BOOL _isRenamingFileItemsToHaveUniqueFileNames;
    
    NSMutableSet *_fileItems;
    NSDictionary *_groupItemByName;
    
    NSMutableSet *_topLevelItems;
    
    NSOperationQueue *_actionOperationQueue;
}

static OFPreference *OFSDocumentStoreDisableUbiquityPreference = nil; // Even if ubiquity is enabled, don't ask the user -- just pretend we don't see it.
static OFPreference *OFSDocumentStoreUserWantsUbiquityPreference = nil; // If ubiquity is on, the user still might want to not use it, but have the option to turn it on later.

+ (void)initialize;
{
    OBINITIALIZE;

    OFSDocumentStoreDisableUbiquityPreference = [[OFPreference preferenceForKey:@"OFSDocumentStoreDisableUbiquity"] retain];
    OFSDocumentStoreUserWantsUbiquityPreference = [[OFPreference preferenceForKey:@"OFSDocumentStoreUserWantsUbiquity"] retain];
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

+ (void)didPromptForUbiquityAccessWithResult:(BOOL)allowUbiquityAccess;
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
    [self scanItemsWithCompletionHandler:^{
        for (OFSDocumentStoreFileItem *fileItem in _fileItems)
            [fileItem _resumeFilePresenter];
        
        if (completionHandler)
            completionHandler();
    }];
}

#endif

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
    //files from graffletopia (and maybe elsewhere) can be named "Foo.gstencil.zip". Both extensions need stripped. the second call will do nothing if there's no extension.
    return [self fileItemNamed:[[[fileURL lastPathComponent] stringByDeletingPathExtension] stringByDeletingPathExtension]] != nil;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSURL *)availableURLWithFileName:(NSString *)fileName;
{
    NSString *originalName = [fileName stringByDeletingPathExtension];
    NSString *extension = [fileName pathExtension];
    
    // If the file item name ends in a number, we are likely duplicating a duplicate.  Take that as our starting counter.  Of course, this means that if we duplicate "Revenue 2010", we'll get "Revenue 2011". But, w/o this we'll get "Revenue 2010 2", "Revenue 2010 2 2", etc.
    NSString *baseName = nil;
    NSUInteger counter;
    [originalName splitName:&baseName andCounter:&counter];
    
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

- initWithDirectoryURL:(NSURL *)directoryURL delegate:(id <OFSDocumentStoreDelegate>)delegate scanCompletionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION(delegate);
    
    if (!(self = [super init]))
        return nil;

    _directoryURL = [directoryURL copy];
    _nonretained_delegate = delegate;
    
    _actionOperationQueue = [[NSOperationQueue alloc] init];
    [_actionOperationQueue setName:@"OFSDocumentStore file actions"];
    [_actionOperationQueue setMaxConcurrentOperationCount:1];
    
#if 0 && defined(DEBUG)
    if (_directoryURL)
        [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:_directoryURL];
#endif

    [OFPreference addObserver:self selector:@selector(_ubiquityAllowedPreferenceChanged:) forPreference:OFSDocumentStoreUserWantsUbiquityPreference];
    
    [self _startMetadataQuery];
    
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

static BOOL _performAdd(NSURL *fromURL, NSURL *toURL, OFSDocumentStoreScope scope, BOOL isReplacing, NSError **outError)
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
    
    if (scope == OFSDocumentStoreScopeUbiquitous) {
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
- (NSOperation *)addDocumentWithScope:(OFSDocumentStoreScope)scope inFolderNamed:(NSString *)folderName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]); // We'll invoke the completion handler on the main thread

    if (!completionHandler)
        completionHandler = ^(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error){
            NSLog(@"Error adding document from %@: %@", fromURL, [error toPropertyList]);
        };
    
    completionHandler = [[completionHandler copy] autorelease]; // preserve scope
    
    if (scope == OFSDocumentStoreScopeUnknown)
        scope = [[self class] _defaultScope];
        
    NSURL *toURL = nil;
    BOOL isReplacing = NO;
    
    if (option == OFSDocumentStoreAddNormally) {
        // Use the given file name.
        NSError *error = nil;
        toURL = [self _urlForScope:scope folderName:folderName fileName:[fromURL lastPathComponent] error:&error];
        if (!toURL) {
            completionHandler(nil, error);
            return nil;
        }
    }
    else if (option == OFSDocumentStoreAddByRenaming) {
        // Generate a new file name.
        NSString *fileName = [fromURL lastPathComponent];
        NSString *baseName = nil;
        NSUInteger counter;
        [[fileName stringByDeletingPathExtension] splitName:&baseName andCounter:&counter];

        fileName = [self availableFileNameWithBaseName:baseName extension:[fileName pathExtension] counter:&counter];

        NSError *error = nil;
        toURL = [self _urlForScope:scope folderName:folderName fileName:fileName error:&error];
        if (!toURL) {
            completionHandler(nil, error);
            return nil;
        }
    }
    else if (option == OFSDocumentStoreAddByReplacing) {
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
        OBASSERT_NOT_REACHED("OFSDocumentStoreAddOpiton not given or invalid.");
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
                    OFSDocumentStoreFileItem *duplicateItem = [self fileItemWithURL:toURL];
                    OBASSERT(duplicateItem);
                    completionHandler(duplicateItem, nil);
                }];
            } else
                completionHandler(nil, error);
        }];
    }];
    
    // We must have a different queue for the actions than we have for notifications, lest we deadlock vs. our OFSDocumentStoreFileItems.
    [_actionOperationQueue addOperation:operation];
    
    return operation;
}

- (NSOperation *)addDocumentFromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
{
    OFSDocumentStoreScope scope = OFSDocumentStoreScopeUnknown;
    if ([_nonretained_delegate respondsToSelector:@selector(documentStore:scopeForNewDocumentAtURL:)])
        scope = [_nonretained_delegate documentStore:self scopeForNewDocumentAtURL:fromURL];
    
    if (scope == OFSDocumentStoreScopeUnknown)
        scope = [self scopeForFileURL:fromURL];
        
    if (scope == OFSDocumentStoreScopeUnknown) {
        // Might be coming from UIDocumentInteractionController or our app wrapper if we are restoring a template.
        scope = [[self class] _defaultScope];
    }
    
    return [self addDocumentWithScope:scope inFolderNamed:_folderFilename(fromURL) fromURL:fromURL option:option completionHandler:completionHandler];
}
#endif

static NSURL *_coordinatedMoveItem(OFSDocumentStoreFileItem *fileItem, NSURL *destinationDirectoryURL, NSString *destinationFileName, NSError **outError)
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

    // The file item will be notified of the move by the calls to -itemAtURL:didMoveToURL:.
    NSFileCoordinator *coordinator = [[[NSFileCoordinator alloc] initWithFilePresenter:nil] autorelease];
    
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
         
         // This fires -presentedItemDidMoveToURL:. If we don't call this, NSFileCoordinator will silently cleanup after us, but it will do so sometime later. We want to be able to stick blocks on the presenter queue to let us know when these operations have been acknowledged by the presenters, so the silent delayed cleanup is actively unhelpful.
         // The documentation says we must call this w/in the block, but it doesn't specify whether we pass the original URLs or the temporary ones passed to the block... Radar 10319838: NSFileCoordinator -itemAtURL:didMoveToURL: documentation unclear
         [coordinator itemAtURL:newURL1 didMoveToURL:newURL2];
         [coordinator itemAtURL:sourceURL didMoveToURL:destinationURL];
         
         // Recommended calling convention for this API (since it returns void) is to set a __block variable to success...
         success = YES;
     }];
    
    if (success) {
        OBASSERT(innerError == nil);
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

- (void)renameFileItem:(OFSDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionQueue:(NSOperationQueue *)completionQueue handler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
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
    // scanItemsWithCompletionHandler: now ignores the 'Inbox' so we should never get into this situation.
    OBASSERT(![OFSDocumentStore isURLInInbox:containingDirectoryURL]);
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
            // We want to delay firing the completion handler until the file presenter has seen the effects of this change.
            [[fileItem presentedItemOperationQueue] addOperationWithBlock:^{
                [completionQueue addOperationWithBlock:^{
                    if (destinationURL)
                        completionHandler(destinationURL, nil);
                    else 
                        completionHandler(nil, error);
                }];
            }];
        }
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
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)moveItems:(NSSet *)fileItems toFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
{
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
        OFSDocumentStoreGroupItem *group = [_groupItemByName objectForKey:folderName];
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
        NSURL *containerURL = [[self class] _ubiquityDocumentsURL:&error];
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
    // NSFileManager will return /private/var URLs even when passed a standardized (/var) URL. Our cache keys should always be in one space.
    url = [url URLByStandardizingPath];
    
    // NSMetadataItem passes URLs w/o the trailing slash when the really are directories. Use strings for keys instead of URLs and trim the trailing slash if it is there.
    return [[url absoluteString] stringByRemovingSuffix:@"/"];
}


static OFSDocumentStoreFileItem *_addFileItemWithURL(OFSDocumentStore *self, NSMutableDictionary *urlToExistingFileItem, NSMutableDictionary *urlToUpdatedFileItem, NSMutableDictionary *fileItemToUpdatedModificationDate, NSURL *fileURL, NSDate *date)
{
    OBPRECONDITION(urlToUpdatedFileItem);
    OBPRECONDITION(fileURL);

    NSString *fileItemCacheKey = _fileItemCacheKeyForURL(fileURL);
    OFSDocumentStoreFileItem *fileItem = [urlToExistingFileItem objectForKey:fileItemCacheKey];

    // The caller should have verified that the URL has a valid file type for us, but we'll double-check.
    OBFinishPortingLater("Why are we redundantly checking the UTI of this file?");
    NSError *error;
    NSString *uti = OFUTIForFileURLPreferringNative(fileURL, &error);
    if (!uti) {
        OBASSERT_NOT_REACHED("Could not determine UTI for file URL");
        NSLog(@"Could not determine UTI for URL %@: %@", fileURL, [error toPropertyList]);
    }
    
    if (![self->_nonretained_delegate documentStore:self shouldIncludeFileItemWithFileType:uti]) {
        OBASSERT_NOT_REACHED("The caller should have verified that the URL has a valid file type for us");
        return nil;
    }
    
    OBFinishPortingLater("Since the result of this is controlled by the filter UI in the document picker, we should have different API to pass in an immutable mapping of UTI->Class or otherwise ensure this is thread-safe.");
    Class itemClass = [self->_nonretained_delegate documentStore:self fileItemClassForURL:fileURL];
    OBASSERT_NOTNULL(itemClass); // don't return YES from -shouldInclude if you don't intend to give us an item class
    
    if (fileItem) { 
        DEBUG_STORE(@"Existing file item: %@", [fileItem shortDescription]);
        OBASSERT([fileItem isKindOfClass:itemClass]); // not sure this will ever happen, but if the delegate changes its mind about what item class this item should be, we need to add code to handle that scenario.
        //NSLog(@"  reused file item %@ for %@", fileItem, fileURL);
        [urlToUpdatedFileItem setObject:fileItem forKey:fileItemCacheKey];
        
        // Record the updated modification date to apply once we get back to the main thread (for KVO).
        [fileItemToUpdatedModificationDate setObject:date forKey:fileItem];
    } else {
        fileItem = [self _newFileItemForURL:fileURL date:date];
        DEBUG_STORE(@"New file item %@ at %@ with scope %d", [fileItem shortDescription], fileItem.fileURL, fileItem.scope);
        OBASSERT(fileItem);
        
        [urlToUpdatedFileItem setObject:fileItem forKey:fileItemCacheKey];
        [fileItem release];
    }
    
    return fileItem;
}

// Called as part of a 'prepare' block. See the header doc for -[NSFileCoordinator prepare...] for discussion of why we pass NSFileCoordinatorReadingWithoutChanges for individual directories.
static void _scanDirectoryURL(OFSDocumentStore *self, NSFileCoordinator *coordinator, NSURL *directoryURL, void (^itemBlock)(NSFileManager *fileManager, NSURL *fileURL))
{
    OBASSERT(![NSThread isMainThread]);
    
    __block BOOL readingSuccess = NO;
    NSError *readingError = nil;
    [coordinator coordinateReadingItemAtURL:directoryURL options:NSFileCoordinatorReadingWithoutChanges
                                      error:&readingError
                                 byAccessor:
     ^(NSURL *readURL){
         // We are reading directories that shouldn't be replaced wholesale by any other writers. BUT we'll sure want to know if they ever are. If so, we'll need to do URL surgery to make OFSDocumentStoreFileItems that have the URLs the should have, not relative URLs to readURL.
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
                 NSError *error;
                 NSString *uti = OFUTIForFileURLPreferringNative(fileURL, &error);
                 if (!uti) {
                     OBASSERT_NOT_REACHED("Could not determine UTI for file URL");
                     NSLog(@"Could not determine UTI for URL %@: %@", fileURL, [error toPropertyList]);
                     continue;
                 }
                 
                 // Recurse into non-document directories in ~/Documents. Not checking for OFSDocumentStoreFolderPathExtension here since I don't recall if documents sent to us from other apps via UIDocumentInteractionController end up inside ~/Documents or elsewhere (and it isn't working for me right now).
                 if (![self->_nonretained_delegate documentStore:self shouldIncludeFileItemWithFileType:uti]) {
                     if (!UTTypeConformsTo((CFStringRef)uti, kUTTypePackage)) {
                         // The delegate might not want a file item for this URL, but if it's a directory might want ones for its descendants
                         NSNumber *isDirectory = nil;
                         NSError *resourceError = nil;
                         
                         if (![fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&resourceError])
                             NSLog(@"Unable to determine if %@ is a directory: %@", fileURL, [resourceError toPropertyList]);
                         
                         else {
                             // We never want to acknowledge files in the inbox directly. Instead they'll be dealt with when they're handed to us via document interaction and moved.
                             if ([isDirectory boolValue] 
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
                                 && ![OFSDocumentStore isURLInInbox:fileURL]
#endif
                                 )
                                 [scanDirectoryURLs addObject:fileURL];
                         }
                     }
                     
                     // Don't create an item for this URL
                     continue;
                 }
                 
                 itemBlock(fileManager, fileURL);
             }
         }
     }];
    
    if (!readingSuccess) {
        NSLog(@"Error scanning %@: %@", directoryURL, [readingError toPropertyList]);
        // We don't pass this up currently... should we make all the completion handlers deal with it? Add a main-thread delegate callback to present the error?
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
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    
    __block BOOL prepareSuccess = NO;
    NSError *prepareError = nil;
    [coordinator prepareForReadingItemsAtURLs:directoryURLs options:0
                           writingItemsAtURLs:nil options:0
                                        error:&prepareError
                                   byAccessor:
     ^(void (^prepareCompletionHandler)(void)){
         prepareSuccess = YES;
         
         for (NSURL *directoryURL in directoryURLs) {
             DEBUG_STORE(@"Scanning %@", directoryURL);
#if 0 && defined(DEBUG)
             [[NSFileManager defaultManager] logPropertiesOfTreeAtURL:directoryURL];
#endif
             _scanDirectoryURL(self, coordinator, directoryURL, itemBlock);
         }
         
         if (prepareCompletionHandler)
             prepareCompletionHandler();
     }];
    
    [coordinator release];
    
    if (!prepareSuccess) {
        NSLog(@"Error preparing to scan %@: %@", directoryURLs, [prepareError toPropertyList]);
        // We don't pass this up currently... should we make all the completion handlers deal with it? Add a main-thread delegate callback to present the error?
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

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    // Need to know what class of file items to make.
    OBPRECONDITION(_nonretained_delegate);
    
    // Capture state
    completionHandler = [[completionHandler copy] autorelease];
    
    if (_isScanningItems) {
        // There is an in-flight scan already. We want to get its state back before we start another scanning operaion.
        if (!_deferredScanCompletionHandlers)
            _deferredScanCompletionHandlers = [[NSMutableArray alloc] init];
        if (!completionHandler)
            completionHandler = ^{}; // want to make sure a scan actually happens
        [_deferredScanCompletionHandlers addObject:completionHandler];
        return;
    }
    
    _isScanningItems = YES;
    
    // Scan the existing documents directory, reusing file items when possible. We'll do the scan on a background coordinated read. The background queue should NOT mutate existing file items, since we don't want KVO firing on the background thread.
    NSMutableDictionary *urlToUpdatedFileItem = [[NSMutableDictionary alloc] init];
    
    NSArray *directoryURLs = [self _scanItemsDirectoryURLs];
    
    // _fileItems is updated on the main thread, so we need to read it here too. This is racey.
    NSArray *existingFileItems = [[_fileItems copy] autorelease];
    
    [self performAsynchronousFileAccessUsingBlock:^{
        
        // Filled in by _scanDirectoryURLs inside the coordinated read
        NSMutableDictionary *urlToExistingFileItem = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *fileItemToUpdatedModificationDate = [[NSMutableDictionary alloc] init];
        
        // Build an index to help in reusing file items. We do this inside the action to make sure any pending local changes are done, but file presenter messages haven't been sent yet, so this could still be racey. Perhaps we should wait for all the queued file presenter notifications on all the file item's presenter queues.
        for (OFSDocumentStoreFileItem *fileItem in existingFileItems) {
            OBASSERT([urlToExistingFileItem objectForKey:_fileItemCacheKeyForURL(fileItem.presentedItemURL)] == nil);
            [urlToExistingFileItem setObject:fileItem forKey:_fileItemCacheKeyForURL(fileItem.presentedItemURL)];
        }
        DEBUG_STORE(@"urlToExistingFileItem = %@", urlToExistingFileItem);
        
        
        void (^itemBlock)(NSFileManager *fileManager, NSURL *fileURL) = ^(NSFileManager *fileManager, NSURL *fileURL){
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
            _addFileItemWithURL(self, urlToExistingFileItem, urlToUpdatedFileItem, fileItemToUpdatedModificationDate, fileURL, modificationDate);
        };
        
        void (^scanFinished)(void) = ^{
            OBASSERT([NSThread isMainThread]);
            
            {
                // Apply metadata to the scanned items. The results of NSMetadataQuery can lag behind the filesystem operations, particularly if they are invoked locally.
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
                            OBASSERT([self scopeForFileURL:fileURL] == OFSDocumentStoreScopeUbiquitous);
                            
                            DEBUG_METADATA(@"item %@ %@", item, [fileURL absoluteString]);
                            DEBUG_METADATA(@"  %@", [item valuesForAttributes:[NSArray arrayWithObjects:NSMetadataUbiquitousItemHasUnresolvedConflictsKey, NSMetadataUbiquitousItemIsDownloadedKey, NSMetadataUbiquitousItemIsDownloadingKey, NSMetadataUbiquitousItemIsUploadedKey, NSMetadataUbiquitousItemIsUploadingKey, NSMetadataUbiquitousItemPercentDownloadedKey, NSMetadataUbiquitousItemPercentUploadedKey, NSMetadataItemFSContentChangeDateKey, NSMetadataItemFSSizeKey, nil]]);
                            
                            // May be nil if we are in the process of a delete.
                            OFSDocumentStoreFileItem *fileItem = [urlToUpdatedFileItem objectForKey:_fileItemCacheKeyForURL(fileURL)];
                            [fileItem _updateWithMetadataItem:item];
                            
                            // We get the modification date from the NSMetadataItem. Don't update it below.
                            [fileItemToUpdatedModificationDate removeObjectForKey:fileItem];
                        }
                    } @finally {
                        [_metadataQuery enableUpdates];
                    }
                }
                
                // Apply any modification date updates for local documents (possibly edited by iTunes file sharing).
                for (OFSDocumentStoreFileItem *fileItem in fileItemToUpdatedModificationDate) {
                    fileItem.date = [fileItemToUpdatedModificationDate objectForKey:fileItem];
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
                    OFSDocumentStoreFileItem *fileItem = [urlToExistingFileItem objectForKey:cacheKey];
                    if ([urlToUpdatedFileItem objectForKey:cacheKey] == nil) {
                        DEBUG_STORE(@"File item %@ has disappeared, invalidating %@", cacheKey, [fileItem shortDescription]);
                        [fileItem _invalidate];
                    }
                }
            }
            
            NSSet *updatedFileItems = [NSSet setWithArray:[urlToUpdatedFileItem allValues]];
            BOOL fileItemsChanged = OFNOTEQUAL(_fileItems, updatedFileItems);
            if (fileItemsChanged) {
                [self willChangeValueForKey:OFSDocumentStoreFileItemsBinding];
                [_fileItems release];
                _fileItems = [[NSMutableSet alloc] initWithSet:updatedFileItems];
                [self didChangeValueForKey:OFSDocumentStoreFileItemsBinding];
                
            }
            
            [urlToExistingFileItem release];;
            [urlToUpdatedFileItem release];
            
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
                DEBUG_STORE(@"Scanned top level items %@", _topLevelItems);
                
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
            [self _renameFileItemsToHaveUniqueFileNames];
            
            // We are done scanning -- see if any other scan requests have piled up while we were running and start one if so.
            // We do need to rescan (rather than just calling all the queued completion handlers) since the caller might have queued more filesystem changing operations between the two scan requests.
            _isScanningItems = NO;
            if ([_deferredScanCompletionHandlers count] > 0) {
                void (^nextCompletionHandler)(void) = [[[_deferredScanCompletionHandlers objectAtIndex:0] retain] autorelease];
                [_deferredScanCompletionHandlers removeObjectAtIndex:0];
                [self scanItemsWithCompletionHandler:nextCompletionHandler];
            }
        };
        
        
        _scanDirectoryURLs(self, directoryURLs, itemBlock, scanFinished);
    }];
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// Moves all the existing local documents to iCloud, preserving their folder structure.
- (void)moveLocalDocumentsToCloudWithCompletionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION([[self class] _ubiquityContainerURL]);
    
    completionHandler = [[completionHandler copy] autorelease];
    
    NSURL *localDirectoryURL = [[_directoryURL copy] autorelease];
    NSURL *ubiquityDocumentsURL = [[self class] _ubiquityDocumentsURL:NULL];
    NSArray *allDirectoryURLs = [NSArray arrayWithObjects:localDirectoryURL, ubiquityDocumentsURL, nil];
    OBASSERT([allDirectoryURLs count] == 2);
    
    [self performAsynchronousFileAccessUsingBlock:^{
        DEBUG_STORE(@"Moving local documents (%@) to iCloud (%@)", localDirectoryURL, ubiquityDocumentsURL);
        
        NSMutableDictionary *movedURLs = [NSMutableDictionary dictionary]; // sourceURL -> destURL
        NSMutableDictionary *errorURLs = [NSMutableDictionary dictionary]; // sourceURL -> error
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        NSError *error = nil;
        __block BOOL prepareSucceeded = NO;
        
        [coordinator prepareForReadingItemsAtURLs:allDirectoryURLs options:0
                               writingItemsAtURLs:allDirectoryURLs options:0
                                            error:&error
                                       byAccessor:
         ^(void (^prepareCompletionHandler)(void)){
             prepareSucceeded = YES;
             
             // Gather the names to avoid (only from the destination).
             NSError *nameScanError = nil;
             NSMutableSet *usedFileNames = [NSMutableSet set];
             if (![self _addCurrentlyUsedFileNames:usedFileNames inDirectoryURL:ubiquityDocumentsURL usingCoordinator:coordinator error:&nameScanError]) {
                 // We didn't move any URLs.
                 _scanDirectoryURL(self, coordinator, localDirectoryURL, ^(NSFileManager *fileManager, NSURL *sourceURL){
                     [errorURLs setObject:error forKey:sourceURL];
                 });
                 return;
             }
             DEBUG_STORE(@"  usedFileNames = %@", usedFileNames);
             
             // Process all the local documents, moving them into the ubiquity container.
             _scanDirectoryURL(self, coordinator, localDirectoryURL, ^(NSFileManager *fileManager, NSURL *sourceURL){
                 NSString *sourceFileName = [sourceURL lastPathComponent];
                 NSUInteger counter = 0;
                 NSString *destinationName = _availableName(usedFileNames, [sourceFileName stringByDeletingPathExtension], [sourceFileName pathExtension], &counter);
                 
                 NSString *folderName = [[sourceURL URLByDeletingLastPathComponent] lastPathComponent];
                 if (OFNOTEQUAL([folderName pathExtension], OFSDocumentStoreFolderPathExtension))
                     folderName = nil;
                 
                 NSURL *destinationURL = ubiquityDocumentsURL;
                 if (folderName)
                     destinationURL = [destinationURL URLByAppendingPathComponent:folderName];
                 destinationURL = [destinationURL URLByAppendingPathComponent:destinationName];
                 
                 __block BOOL moveSuccess = NO;
                 __block NSError *moveError = nil;
                 [coordinator coordinateWritingItemAtURL:sourceURL options:NSFileCoordinatorWritingForMoving
                                        writingItemAtURL:destinationURL options:NSFileCoordinatorWritingForReplacing error:&moveError byAccessor:
                  ^(NSURL *newURL1, NSURL *newURL2){
                      moveSuccess = [fileManager moveItemAtURL:newURL1 toURL:newURL2 error:&moveError];
                  }];
                 
                 if (!moveSuccess) {
                     [errorURLs setObject:moveError forKey:sourceURL];
                     DEBUG_STORE(@"  error moving %@: %@", sourceURL, [moveError toPropertyList]);
                 } else {
                     [movedURLs setObject:destinationURL forKey:sourceURL];
                     DEBUG_STORE(@"  moved %@ to %@", sourceURL, destinationURL);
                     
                     // Now we need to avoid this file name.
                     [usedFileNames addObject:[destinationURL lastPathComponent]];
                 }
             });
             
             if (prepareCompletionHandler)
                 prepareCompletionHandler();
         }];
        
        if (completionHandler) {
            if (prepareSucceeded) {
                // We got inside the coordinator and should have filled out source/dest or source/error pairs for each source URL.
            } else {
                // We didn't move any URLs.
                _scanDirectoryURL(self, coordinator, localDirectoryURL, ^(NSFileManager *fileManager, NSURL *sourceURL){
                    [errorURLs setObject:error forKey:sourceURL];
                });
            }
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionHandler(movedURLs, errorURLs);
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
- (OFSDocumentStoreScope)scopeForFileURL:(NSURL *)fileURL;
{
    if (_urlContainedByURL(fileURL, _directoryURL))
        return OFSDocumentStoreScopeLocal;
    
    // OBFinishPorting: Is there a possible race condition between an item scan calling back to us and being foregrounded/backgrounded changing our container URL between something valid and nil?
    if (_urlContainedByURL(fileURL, [[self class] _ubiquityDocumentsURL:NULL]))
        return OFSDocumentStoreScopeUbiquitous;
        
    return OFSDocumentStoreScopeUnknown;
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
    
    NSURL *fileURL = [self availableURLInDirectoryAtURL:directoryURL baseName:name extension:(NSString *)extension counter:&counter];
    CFRelease(extension);
    
    [[NSUserDefaults standardUserDefaults] setInteger:counter forKey:UntitledDocumentCreationCounterKey];
    return fileURL;
}

static void _addItemAndNotifyHandler(OFSDocumentStore *self, void (^handler)(OFSDocumentStoreFileItem *createdFileItem, NSError *error), NSURL *createdURL, NSError *error)
{
    // We will modify our file items here, so this still needs to be on the background
    OBPRECONDITION([NSOperationQueue currentQueue] == self->_actionOperationQueue);
    
    // We just successfully wrote a new document; there is no need to do a full scan (though one may fire anyway if the metadata query launches due to this being in iCloud). Still, we want to get back to the UI as soon as possible by calling the completion handler w/o waiting for the scan.
    OFSDocumentStoreFileItem *createdFileItem = nil;
    if (createdURL) {
        NSDate *date = nil;
        if (![createdURL getResourceValue:&date forKey:NSURLContentModificationDateKey error:NULL]) {
            OBASSERT_NOT_REACHED("We just created it...");
        }
        
        // The delegate is in charge of making sure that the file will sort to the top if the UI is sorting files by date. If it just copies a template, then it may need to call -[NSFileManager touchItemAtURL:error:]
        OBASSERT(date);
        OBASSERT([date timeIntervalSinceNow] < 0.5);
        
        createdFileItem = [self _newFileItemForURL:createdURL date:date];
        if (!createdFileItem) {
            OBASSERT_NOT_REACHED("Some error in the delegate where we created a file of a type we don't display?");
        } else {
            // Assuming for now that we don't create items inside groups.
            OBASSERT(OFNOTEQUAL([[createdURL URLByDeletingLastPathComponent] pathExtension], OFSDocumentStoreFolderPathExtension));
            
            NSSet *added = [[NSSet alloc] initWithObjects:&createdFileItem count:1];
            
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
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            handler(createdFileItem, error);
        }];
}

- (void)createNewDocument:(void (^)(OFSDocumentStoreFileItem *createdFileItem, NSError *error))handler;
{
    // Put this in the _actionOperationQueue so we seralize with any previous in-flight scans that may update our set of file items (which could change the generated name for a new document).
    
    handler = [[handler copy] autorelease];

    [_actionOperationQueue addOperationWithBlock:^{
        NSString *documentType = [self documentTypeForNewFiles];
        NSURL *newDocumentURL = [self urlForNewDocumentOfType:documentType];
        
        // We create documents in the ~/Documents directory at first and then if iCloud is on (and the delegate allows it), we move them into iCloud.
        OBASSERT([self scopeForFileURL:newDocumentURL] == OFSDocumentStoreScopeLocal);
        
        [_nonretained_delegate createNewDocumentAtURL:newDocumentURL completionHandler:^(NSURL *createdURL, NSError *error){
            if (!createdURL) {
                _addItemAndNotifyHandler(self, handler, nil, error);
                return;
            }
            
            // Check if we should move the new document into iCloud, and do so.
            OFSDocumentStoreScope scope = OFSDocumentStoreScopeUnknown;
            if ([_nonretained_delegate respondsToSelector:@selector(documentStore:scopeForNewDocumentAtURL:)])
                scope = [_nonretained_delegate documentStore:self scopeForNewDocumentAtURL:newDocumentURL];
            if (scope == OFSDocumentStoreScopeUnknown)
                scope = [[self class] _defaultScope];
            
            if (scope == OFSDocumentStoreScopeUbiquitous) {
                NSError *containerError = nil;
                
                NSURL *containerURL = [self _containerURLForScope:scope error:&containerError];
                if (!containerURL) {
                    _addItemAndNotifyHandler(self, handler, nil, containerError);
                    return;
                }
                
                [_actionOperationQueue addOperationWithBlock:^{
                    NSError *cloudError = nil;
                    NSURL *destinationURL = [self _moveURL:createdURL toCloud:YES error:&cloudError];
                    if (!destinationURL) {
                        _addItemAndNotifyHandler(self, handler, nil, cloudError); // Though we may now have a local document...
                    } else {
                        _addItemAndNotifyHandler(self, handler, destinationURL, nil);
                    }
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
        
        BOOL isZip = UTTypeConformsTo((CFStringRef)uti, (CFStringRef)@"com.omnigroup.zip");
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
        
        if (![_nonretained_delegate documentStore:self shouldIncludeFileItemWithFileType:uti]) {
            // we're not going to delete the file in the inbox here, because another document store may want to lay claim to this inbox item. Give them a chance to. The calls to cleanupInboxItem: should be daisy-chained from OUISingleDocumentAppController or it's subclass.
            
            NSError *utiShouldNotBeIncludedError = nil;
            NSString *title =  NSLocalizedStringFromTableInBundle(@"An error has occurred", @"OmniFileStore", OMNI_BUNDLE, @"error title");
            NSString *description = NSLocalizedStringFromTableInBundle(@"Delegate claims not to support the file type.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
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
            [self addDocumentFromURL:itemToMoveURL option:OFSDocumentStoreAddByRenaming completionHandler:^(OFSDocumentStoreFileItem *addedDocumentFileItem, NSError *error) {
                NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                [coordinator coordinateWritingItemAtURL:inboxURL options:NSFileCoordinatorWritingForDeleting error:&error byAccessor:^(NSURL *newURL) {
                    NSError *deleteError = nil;
                    if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:&deleteError]) {
                        // Deletion of zip file failed.
                        NSLog(@"Deletion of zip file failed: %@", [deleteError toPropertyList]);
                    }
                }];
                [coordinator release];

                finishedBlock(addedDocumentFileItem, error);
            }];
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
#endif

#pragma mark -
#pragma mark Private

// The top level is useful for settings and non-document type stuff, but NSMetadataQuery will only look in the Documents folder.
+ (NSURL *)_ubiquityContainerURL;
{
    // Hidden preference to totally disable iCloud support until Apple fixes some edge case bugs.
    if ([OFSDocumentStoreDisableUbiquityPreference boolValue])
        return nil;
    
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
    
    // We don't cache this since if the app is backgrounded and then brought back to the foreground, iCloud may have been turned off/on while we were in the background.
    return [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:fullContainerID];
}

+ (NSURL *)_ubiquityDocumentsURL:(NSError **)outError;
{
    if (![self isUbiquityAccessEnabled]) {
        // iCloud may be off globally, or this app may not have defined the infoDictionary keys (isn't using iCloud at all), or the user may have opted out of iCloud for this app.
        OBUserCancelledError(outError);
        return nil;
    }
        
    // Later the Documents directory will be automatically created, but we need to do it ourselves now.
    NSURL *containerURL = [self _ubiquityContainerURL];
    if (!containerURL) {
        OBASSERT_NOT_REACHED("+isUbiquityAccessEnabled should have returned NO.");
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

- (NSArray *)_scanItemsDirectoryURLs;
{
    NSMutableArray *directoryURLs = [NSMutableArray array];
    
    // Scan our local ~/Documents if we have one.
    if (_directoryURL)
        [directoryURLs addObject:_directoryURL];
    
    // In addition to scanning our local Documents directory (on iPad, at least), we also scan our ubiquity container directly, if enabled.
    // Talking to Apple, the top-level entries in the container are intended to be present (and empty directory for a wrapper, for example). The metadata can lag behind the state of the filesystem, particularly for locally invoked operations. We don't want to create items based solely on the presense of a metadata item since then a delete of a file wouldn't produce a remove of the file item until after the metadata update.
    NSURL *ubiquityDocumentsURL = [[self class] _ubiquityDocumentsURL:NULL];
    if  (ubiquityDocumentsURL)
        [directoryURLs addObject:ubiquityDocumentsURL];
    
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

+ (OFSDocumentStoreScope)_defaultScope;
{
    if ([self isUbiquityAccessEnabled])
        return OFSDocumentStoreScopeUbiquitous;
    return OFSDocumentStoreScopeLocal;
}

- (NSURL *)_containerURLForScope:(OFSDocumentStoreScope)scope error:(NSError **)outError;
{
    switch (scope) {
        case OFSDocumentStoreScopeUbiquitous:
            return [[self class] _ubiquityDocumentsURL:outError];
        default:
            OBASSERT_NOT_REACHED("Bad scope -- using local documents");
            // fall through
        case OFSDocumentStoreScopeLocal:
            OBASSERT(_directoryURL);
            if (_directoryURL)
                return _directoryURL;
            return [[self class] userDocumentsDirectoryURL];
    }
}

- (NSURL *)_urlForScope:(OFSDocumentStoreScope)scope folderName:(NSString *)folderName fileName:(NSString *)fileName error:(NSError **)outError;
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

// Track whether the user would like to have iCloud documents shown (assuming iCloud is even enabled).
- (void)_ubiquityAllowedPreferenceChanged:(NSNotification *)note;
{
    [self _stopMetadataQuery];
    [self _startMetadataQuery];
    [self scanItemsWithCompletionHandler:nil];
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
        OBASSERT(OFNOTEQUAL(_fileItemCacheKeyForURL(presenter.presentedItemURL), _fileItemCacheKeyForURL(fileURL)));
    }
#endif
    
    OFSDocumentStoreFileItem *fileItem = [[fileItemClass alloc] initWithDocumentStore:self fileURL:fileURL date:date];

    DEBUG_STORE(@"  made new file item %@ for %@", fileItem, fileURL);

    return fileItem;
}

- (NSString *)_singleTopLevelEntryNameInArchive:(OUUnzipArchive *)archive directory:(BOOL *)directory error:(NSError **)error;
{
    OBASSERT(archive);
    
    NSString *topLevelEntryName = nil;
        
    if ([[archive entries] count] == 1) {
        // if there's only 1 entry, it should not be a directory
        *directory = NO;
        OUUnzipEntry *entry = [[archive entries] objectAtIndex:0];
        if (![[entry name] lastCharacter] == '/') {
            // This zip contains a single file.
            topLevelEntryName = [entry name];
        }
    }
    else if ([[archive entries] count] > 1) {
        // it's a multi-entry zip. All the entries should have the same prefix.
        *directory = YES;
        NSArray *entries = [archive entries];
        // sort entries by length so that the top level directory comes to the top
        entries = [entries sortedArrayUsingComparator:^(id entry1, id entry2) {
            return ([[entry1 name] caseInsensitiveCompare:[entry2 name]]);
        }];
        
        NSString *topLevelFileName = [[entries objectAtIndex:0] name];
        BOOL invalidStructure = [entries anyObjectSatisfiesPredicate:^BOOL(id object) {
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
    
    
    return OFUTIForFileExtensionPreferringNative([topLevelEntryName pathExtension], isDirectory);
}

// TODO: Phase this out in favor of looking at the file names in a coordinated read inside whatever operation needs it?
- (NSMutableSet *)_copyCurrentlyUsedFileNames;
{
    NSMutableSet *usedFileNames = [[NSMutableSet alloc] init];
    for (NSURL *url in [_fileItems valueForKey:OFSDocumentStoreFileItemFilePresenterURLBinding])
        [usedFileNames addObject:[url lastPathComponent]];
    return usedFileNames;
}

// Must be called inside a NSFileCoordinator 'prepare' block.
- (BOOL)_addCurrentlyUsedFileNames:(NSMutableSet *)fileNames inDirectoryURL:(NSURL *)directoryURL usingCoordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _actionOperationQueue);
    
    // NSFileCoordinatorReadingWithoutChanges since the calling 'prepare' should already have used options that would have forced saving
    __block BOOL success = NO;
    [coordinator coordinateReadingItemAtURL:directoryURL options:NSFileCoordinatorReadingWithoutChanges error:outError byAccessor:^(NSURL *newURL){
        _scanDirectoryURL(self, coordinator, newURL, ^(NSFileManager *fileManager, NSURL *fileURL){
            [fileNames addObject:[fileURL lastPathComponent]];
        });
        success = YES;
    }];
    
    return success;
}

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
        
        // Try a bunch of heuristics about the best renaming operations.
        
        if (fileItem.scope == OFSDocumentStoreScopeLocal) {
            // Move local documents out of the way of iCloud documents
            NSString *localFileName = [currentURL lastPathComponent];
            NSString *localSuffix = NSLocalizedStringFromTableInBundle(@"local", @"OmniFileStore", OMNI_BUNDLE, @"Suffix to automatically apply to document having the same name as others, when the document is local");
            
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
    [[fileName stringByDeletingPathExtension] splitName:&baseName andCounter:&counter];
    
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

        // Note that we actually started a rename
        _isRenamingFileItemsToHaveUniqueFileNames = YES;

        // Sort the items into a deterministic order (as best we can) so that two different devices will perform the same renames.
        // Also, let items in the cloud have higher precedence so that there is reduced chance of conflict.
        [fileItems sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            OFSDocumentStoreFileItem *fileItem1 = obj1;
            OFSDocumentStoreFileItem *fileItem2 = obj2;
            
            OFSDocumentStoreScope scope1 = fileItem1.scope;
            OFSDocumentStoreScope scope2 = fileItem2.scope;
            
            if (scope1 != scope2) {
                if (scope1 == OFSDocumentStoreScopeUbiquitous)
                    return NSOrderedAscending;
                if (scope2 == OFSDocumentStoreScopeUbiquitous)
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
            OFSDocumentStoreFileItem *fileItem = [fileItems objectAtIndex:fileItemIndex];
            
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
            
            
            if (!pendingRenameNotificationOperations)
                pendingRenameNotificationOperations = [NSMutableArray array];

            // Add an empty block on the file item's presenter queue so we can know when it has heard about the rename.
            NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{}];
            [[fileItem presentedItemOperationQueue] addOperation:op];
            [pendingRenameNotificationOperations addObject:op];
        }
        
        [usedFilenames release];
    }
    
    [nameToFileItems release];
    
    // If we did end up staring a rename, queue up a block to turn off this flag (we'll avoid futher uniquing operations until this completes).
    if (_isRenamingFileItemsToHaveUniqueFileNames) {
        OBASSERT([pendingRenameNotificationOperations count] > 0);
        
        [_actionOperationQueue addOperationWithBlock:^{
            // Queue up an operation on the main thread to turn off the renaming flag, but only after all the presenters involved have heard about it.
            NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{
                DEBUG_UNIQUE("Finished");
                OBASSERT(_isRenamingFileItemsToHaveUniqueFileNames == YES);
                _isRenamingFileItemsToHaveUniqueFileNames = NO; 
            }];
            
            for (NSOperation *dependency in pendingRenameNotificationOperations)
                [op addDependency:dependency];
            
            [[NSOperationQueue mainQueue] addOperation:op];
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

#endif // OFS_DOCUMENT_STORE_SUPPORTED
