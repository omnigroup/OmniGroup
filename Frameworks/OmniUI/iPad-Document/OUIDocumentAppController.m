// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentAppController.h>

@import UIKit;
@import MobileCoreServices;
@import CoreSpotlight;
@import OmniAppKit;
@import OmniBase;
@import OmniDAV;
@import OmniDocumentStore;
@import OmniFileExchange;
@import OmniFoundation;
@import OmniUI;

#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentPreviewGenerator.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>
#import <OmniUIDocument/OUIDocumentSceneDelegate.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>
#import <OmniUIDocument/OUIErrors.h>
#import <OmniUIDocument/OUIToolbarTitleButton.h>
#import <OmniUIDocument/OmniUIDocument-Swift.h>
//#import <CrashReporter/CrashReporter.h>

#import "OUINewDocumentCreationRequest.h"
#import "OUIDocument-Internal.h"
#import "OUIDocumentAppController-Internal.h"
#import "OUIDocumentInbox.h"
#import "OUIDocumentParameters.h"
#import "OUIDocumentPicker-Internal.h"
#import "OUIDocumentPickerViewController-Internal.h"
#import "OUIDocumentPickerItemView-Internal.h"
#import "OUILaunchViewController.h"
#import "OUIRestoreSampleDocumentListController.h"

RCS_ID("$Id$");

static NSString * const OpenBookmarkAction = @"openBookmark";

static NSString * const ODSShortcutTypeNewDocument = @"com.omnigroup.framework.OmniUIDocument.shortcut-items.new-document";

static NSString * const ODSOpenRecentDocumentShortcutFileKey = @"ODSFileItemURLStringKey";

OFDeclareDebugLogLevel(OUIApplicationLaunchDebug);
#define DEBUG_LAUNCH(level, format, ...) do { \
    if (OUIApplicationLaunchDebug >= (level)) \
        NSLog(@"APP: " format, ## __VA_ARGS__); \
    } while (0)

static OFDeclareDebugLogLevel(OUIBackgroundFetchDebug);
#define DEBUG_FETCH(level, format, ...) do { \
    if (OUIBackgroundFetchDebug >= (level)) \
        NSLog(@"FETCH: " format, ## __VA_ARGS__); \
    } while (0)

static OFDeclareTimeInterval(OUIBackgroundFetchTimeout, 15, 5, 600);

@interface OUIDocumentAppController (/*Private*/) <OUIDocumentPreviewGeneratorDelegate, OUIDocumentPickerDelegate, OUIWebViewControllerDelegate, OUIDocumentCreationRequestDelegate, ODSStoreDelegate>

@property(nonatomic,copy) NSArray *launchAction;

@property (nonatomic, strong) NSArray *leftItems;
@property (nonatomic, strong) NSArray *rightItems;

@property (nonatomic, weak) OUIWebViewController *webViewController;
@property (nonatomic,readonly) UIBarButtonItem *editButtonItem;
@property (nonatomic) BOOL readyToShowNews;

@property (nonatomic, strong) NSMutableArray<ODSFileItem *> *awaitedFileItemDownloads;

@property (nonatomic, strong) NSUserActivity *userActivityForCurrentlyOpenDocument;

@end

static unsigned SyncAgentAccountsSnapshotContext;

@implementation OUIDocumentAppController
{
    BOOL _didFinishLaunching;
    BOOL _isOpeningURL;

    OFXAgent *_syncAgent;
    BOOL _syncAgentForegrounded; // Keep track of whether we have told the sync agent to run. We might get backgrounded while starting up (when handling a crash alert, for example).
    
    ODSStore *_documentStore;
    ODSLocalDirectoryScope *_localScope;
    OUIDocumentPreviewGenerator *_previewGenerator;
    BOOL _previewGeneratorForegrounded;
    
    OFBackgroundActivity *_backgroundFlushActivity;

    OUIDocumentExporter *_exporter;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
#if 0 && defined(DEBUG) && OUI_GESTURE_RECOGNIZER_DEBUG
    [UIGestureRecognizer enableStateChangeLogging];
#endif
    
#if 0 && defined(DEBUG)
    sleep(3); // see the default image
#endif

    [OUIInspectorAppearance setCurrentTheme:OUIThemedAppearanceThemeLight];

    switch ([[UIDevice currentDevice] userInterfaceIdiom]) {
        case UIUserInterfaceIdiomPhone:
            [ODSLocalDirectoryScope setLocalDocumentsDisplayName:NSLocalizedStringFromTableInBundle(@"On My iPhone", @"OmniUIDocument", OMNI_BUNDLE, @"Local Documents device-specific display name (should match the name of the On My iPhone location in the Files app on an iPhone)")];
            break;
        case UIUserInterfaceIdiomPad:
            ODSLocalDirectoryScope.localDocumentsDisplayName = NSLocalizedStringFromTableInBundle(@"On My iPad", @"OmniUIDocument", OMNI_BUNDLE, @"Local Documents device-specific display name (should match the name of the On My iPad location in the Files app on an iPad)");
            break;
        default:
            break;
    }
}

+ (BOOL)shouldOfferToReportError:(NSError *)error;
{
    if (![super shouldOfferToReportError:error])
        return NO;

    if ([error hasUnderlyingErrorDomain:ODSErrorDomain code:ODSFilenameAlreadyInUse])
        return NO; // We need to let the user know to pick a different filename, but reporting this error to us won't help anyone
    
    if ([error hasUnderlyingErrorDomain:OUIDocumentErrorDomain code:OUIDocumentErrorCannotMoveItemFromInbox])
        return NO; // Ignore the error as per <bug:///160026> (iOS-OmniGraffle Bug: Error encountered: Unable to open file (public.zip-archive))

    return YES;
}

- (UIWindow *)makeMainWindow
{
    OBRejectUnusedImplementation(self, _cmd);
}

// Called at app startup if the main xib didn't have a window outlet hooked up.
- (UIWindow *)makeMainWindowForScene:(UIWindowScene *)scene
{
    NSString *windowClassName = [[OFPreference preferenceForKey:@"OUIMainWindowClass"] stringValue];
    Class windowClass = ![NSString isEmptyString:windowClassName] ? NSClassFromString(windowClassName) : [UIWindow class];
    OBASSERT(OBClassIsSubclassOfClass(windowClass, [UIWindow class]));
    
    UIWindow *window = [[windowClass alloc] initWithWindowScene:scene];
    window.backgroundColor = [UIColor whiteColor];
    return window;
}

- (BOOL)shouldOpenOnlineHelpOnFirstLaunch;
{
    // Apps may wish to override this behavior in a subclass
    
    // Screenshot automation should pass a launch arg to request special behavior—in this case, not showing the help on very first launch, to keep it more consistent with subsequent launches and give us one less thing to special case.
     if ([[NSUserDefaults standardUserDefaults] boolForKey:@"TAKING_SCREENSHOTS"]) {
         return NO;
     } else {
         return YES;
     }
}

#pragma mark -
#pragma mark Sample documents

- (NSInteger)builtInResourceVersion;
{
    return 1;
}

- (NSString *)sampleDocumentsDirectoryTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Restore Sample Documents", @"OmniUIDocument", OMNI_BUNDLE, @"Restore Sample Documents Title");
}

- (NSURL *)sampleDocumentsDirectoryURL;
{
    return [[NSBundle mainBundle] URLForResource:@"Samples" withExtension:@""];
}

- (NSPredicate *)sampleDocumentsFilterPredicate;
{
    // For subclasses to overide.
    return nil;
}

- (void)copySampleDocumentsToUserDocumentsWithCompletionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
{
    OBPRECONDITION(_localScope);
    
    NSURL *samplesDirectoryURL = [self sampleDocumentsDirectoryURL];
    if (!samplesDirectoryURL) {
        if (completionHandler)
            completionHandler(@{});
        return;
    }
        
    [self copySampleDocumentsFromDirectoryURL:samplesDirectoryURL toScope:_localScope stringTableName:[self stringTableNameForSampleDocuments] completionHandler:completionHandler];
}

- (void)copySampleDocumentsFromDirectoryURL:(NSURL *)sampleDocumentsDirectoryURL toScope:(ODSScope *)scope stringTableName:(NSString *)stringTableName completionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
{
    // This should be called as part of an after-scan action so we can properly unique names.
    OBPRECONDITION(scope);
    OBPRECONDITION(scope);
    OBPRECONDITION(scope.hasFinishedInitialScan);
    
    completionHandler = [completionHandler copy];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    __autoreleasing NSError *directoryContentsError = nil;
    NSArray *sampleURLs = [fileManager contentsOfDirectoryAtURL:sampleDocumentsDirectoryURL includingPropertiesForKeys:nil options:0 error:&directoryContentsError];
    if (!sampleURLs) {
        NSLog(@"Unable to find sample documents at %@: %@", sampleDocumentsDirectoryURL, [directoryContentsError toPropertyList]);
        if (completionHandler)
            completionHandler(nil);
        return;
    }
    
    NSDate *lastInstallDate = [[NSDate alloc] initWithXMLString:[[NSUserDefaults standardUserDefaults] stringForKey:@"SampleDocumentsHaveBeenCopiedToUserDocumentsDate"]];

    NSOperationQueue *callingQueue = [NSOperationQueue currentQueue];
    NSMutableDictionary *nameToURL = [NSMutableDictionary dictionary];
    
    for (NSURL *sampleURL in sampleURLs) {
        NSString *sampleName = [[sampleURL lastPathComponent] stringByDeletingPathExtension];
        
        NSString *localizedTitle = [[NSBundle mainBundle] localizedStringForKey:sampleName value:sampleName table:stringTableName];
        if ([NSString isEmptyString:localizedTitle]) {
            OBASSERT_NOT_REACHED("No localization available for sample document name");
            localizedTitle = sampleName;
        }
        NSURL *existingFileURL = [scope.documentsURL URLByAppendingPathComponent:scope.rootFolder.relativePath isDirectory:YES];
        existingFileURL = [existingFileURL URLByAppendingPathComponent:localizedTitle];
        existingFileURL = [existingFileURL URLByAppendingPathExtension:[sampleURL pathExtension]];

        void (^addAction)(void) = ^{
            [scope addDocumentInFolder:scope.rootFolder baseName:localizedTitle fromURL:sampleURL option:ODSStoreAddByCopyingSourceToAvailableDestinationURL completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error){
                if (!duplicateFileItem) {
                    NSLog(@"Failed to copy sample document %@: %@", sampleURL, [error toPropertyList]);
                    return;
                }
                [callingQueue addOperationWithBlock:^{
                    BOOL skipBackupAttributeSuccess = [[NSFileManager defaultManager] addExcludedFromBackupAttributeToItemAtURL:duplicateFileItem.fileURL error:NULL];
#ifdef OMNI_ASSERTIONS_ON
                    OBPOSTCONDITION(skipBackupAttributeSuccess);
#else
                    (void)skipBackupAttributeSuccess;
#endif
                    OBASSERT([nameToURL objectForKey:sampleName] == nil);
                    [nameToURL setObject:duplicateFileItem.fileURL forKey:sampleName];
                }];
            }];
        };

        if ([fileManager fileExistsAtPath:[existingFileURL path]]) {
            NSDictionary *oldResourceAttributes = [fileManager attributesOfItemAtPath:[existingFileURL path] error:NULL];
            NSDate *oldResourceDate = [oldResourceAttributes fileModificationDate];
            ODSFileItem *existingFileItem = [scope fileItemWithURL:existingFileURL];
            // We are going to treat all sample documents which were previously copied over by our pre-universal apps as customized.  The logic here differs from what we do on the Mac.  On the Mac we use if (lastInstallDate != nil && ...
            if (!lastInstallDate || [oldResourceDate isAfterDate:lastInstallDate]) {
                NSString *customizedTitle = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"CustomizedSampleDocumentName", @"OmniUIDocument", OMNI_BUNDLE, @"%@ Customized", @"moved aside custom sample document name"), localizedTitle];
                __block ODSScope *blockScope = scope;
                [scope addDocumentInFolder:scope.rootFolder baseName:customizedTitle fromURL:existingFileURL option:ODSStoreAddByCopyingSourceToAvailableDestinationURL completionHandler:^(ODSFileItem *duplicateFileItem, NSError *error){
                    [blockScope deleteItems:[NSSet setWithObject:existingFileItem] completionHandler:^(NSSet *deletedFileItems, NSArray *errorsOrNil) {
                        addAction();
                    }];
                }];
            } else {
                [scope deleteItems:[NSSet setWithObject:existingFileItem] completionHandler:^(NSSet *deletedFileItems, NSArray *errorsOrNil) {
                    addAction();
                }];
            }
        } else {
            addAction();
        }

    }
    
    // Wait for all the copies to finish
    [scope afterAsynchronousFileAccessFinishes:^{
        // Wait for the updates of the nameToURL dictionary
        [callingQueue addOperationWithBlock:^{
            if (completionHandler)
                completionHandler(nameToURL);
        }];
    }];
}

- (NSString *)stringTableNameForSampleDocuments;
{
    return @"SampleNames";
}

- (NSString *)localizedNameForSampleDocumentNamed:(NSString *)documentName;
{
    return [[NSBundle mainBundle] localizedStringForKey:documentName value:documentName table:[self stringTableNameForSampleDocuments]];
}

- (NSURL *)URLForSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;
{
    NSString *extension = OFPreferredPathExtensionForUTI(fileType);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *fileName = [name stringByAppendingPathExtension:extension];
    
    return [[self sampleDocumentsDirectoryURL] URLByAppendingPathComponent:fileName];
}

#pragma mark - Background fetch

// OmniPresence-enabled applications should implement -application:performFetchWithCompletionHandler: to call this. We cannot name this method -application:performFetchWithCompletionHandler: since UIKit will throw an exception if you declare 'fetch' in your UIBackgroundModes.
- (void)performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler_;
{
    OBPRECONDITION([[UIApplication sharedApplication] isProtectedDataAvailable], "Otherwise we'll need to delay this sync attempt, wait for data protection to become available, timeout if it doesn't soon enough, etc.");
    
    DEBUG_FETCH(1, @"Fetch requested by system");
    if (_syncAgent == nil) {
        OBASSERT_NOT_REACHED("Should always create the sync agent, or the app should not have requested background fetching?"); // Or maybe there are multiple subsystems that might need to fetch -- we need some coordination of when to call the completion handler in that case.
        if (completionHandler_)
            completionHandler_(UIBackgroundFetchResultNoData);
        return;
    }
    
    // We need to reply to the completion handler we were given promptly.
    // We'll clear this once we've called it so that other calls can be avoided.
    __block typeof(completionHandler_) handler = [completionHandler_ copy];

    // Reply to the completion handler as soon as possible if a transfer starts rather than waiting for the whole sync to finish
    // '__block' here is so that the -removeObserver: in the block will not capture the initial 'nil' value.
    __block id transferObserver = [[NSNotificationCenter defaultCenter] addObserverForName:OFXAccountTransfersNeededNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note){
        if (handler) {
            DEBUG_FETCH(1, @"Found new data -- %@", [note userInfo][OFXAccountTransfersNeededDescriptionKey]);
            handler(UIBackgroundFetchResultNewData);
            handler = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:transferObserver];
    }];

    // If we don't hear anything back from the sync for a significant time, report that there is no data (though we let the sync keep running until it times out or we get put back to sleep/killed).
    OFAfterDelayPerformBlock(OUIBackgroundFetchTimeout, ^{
        if (handler) {
            DEBUG_FETCH(1, @"Timed out");
            handler(UIBackgroundFetchResultNoData);
            handler = nil;
        }
     });
    
    [_syncAgent sync:^{
        // This is ugly for our purposes here, but the -sync: completion handler can return before any transfers have started. Making the completion handler be after all this work is even uglier. In particular, automatic download of small docuemnts is controlled by OFXDocumentStoreScope. Wait for a bit longer for stuff to filter through the systems.
        // Note also, that OFXAgentActivity will keep us alive while transfers are happening.
        
        if (!handler)
            return; // Status already reported
        
        DEBUG_FETCH(1, @"Sync request completed -- waiting for a bit to determine status");
        OFAfterDelayPerformBlock(5.0, ^{
            // If we have two accounts and one is offline, we'll let the 'new data' win on the other account (if there is new data).
            if (handler) {
                BOOL foundError = NO;
                for (OFXServerAccount *account in _syncAgent.accountRegistry.validCloudSyncAccounts) {
                    if (account.lastError) {
                        DEBUG_FETCH(1, @"Fetch for account %@ encountered error %@", [account shortDescription], [account.lastError toPropertyList]);
                        foundError = YES;
                    }
                }
                
                if (foundError) {
                    DEBUG_FETCH(1, @"Sync resulted in error");
                    handler(UIBackgroundFetchResultFailed);
                } else {
                    DEBUG_FETCH(1, @"Sync finished without any changes");
                    handler(UIBackgroundFetchResultNoData);
                }
                handler = nil;
            }
        });
    }];
}

#pragma mark - OUIAppController subclass

/*
 In order to adopt Siri Shortcuts, your app's OUIAppController subclass must override the three methods below.
 Your override for supportsSiriShortcuts should simply return YES.
 For the other two methods, you should return a reverse-domain name string that ends with the activity's name. For example, OmniGraffle returns these:
 
        "com.OmniGroup.OmniGraffle.OpenDocumentURLActivity"
        "com.OmniGroup.OmniGraffle.CreateDocumentFromTemplateActivity"
 
 Then, it must add this key with analogous values at the top level of your app's Info.plist:
 
        <key>NSUserActivityTypes</key>
        <array>
            <string>com.OmniGroup.OmniGraffle.OpenDocumentURLActivity</string>
            <string>com.OmniGroup.OmniGraffle.CreateDocumentFromTemplateActivity</string>
        </array>
 
 Then, you get the Open Document and Create Document From Template Shortcuts for free!
 */

+ (BOOL)supportsSiriShortcuts
{
    return NO;
}

+ (NSString *)openDocumentUserActivityType;
{
    OBRequestConcreteImplementation(self, _cmd);
}
+ (NSString *)createDocumentFromTemplateUserActivityType;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSArray *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position;
{
    NSMutableArray *options = [NSMutableArray arrayWithArray:[super additionalAppMenuOptionsAtPosition:position]];
    
    switch (position) {
        case OUIAppMenuOptionPositionBeforeReleaseNotes:
            break;

        case OUIAppMenuOptionPositionAfterReleaseNotes:
        {
            NSString *sampleDocumentsDirectoryTitle = [[OUIDocumentAppController controller] sampleDocumentsDirectoryTitle];
            if (sampleDocumentsDirectoryTitle == nil) {
                break;
            }
            UIImage *image = [[UIImage imageNamed:@"OUIMenuItemRestoreSampleDocuments" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [options addObject:[OUIMenuOption optionWithTarget:self selector:@selector(restoreSampleDocuments:) title:sampleDocumentsDirectoryTitle image:image]];
            break;
        }

        case OUIAppMenuOptionPositionAtEnd:
            break;

        default:
            OBASSERT_NOT_REACHED("Unknown possition");
            break;
    }

    return options;
}

#pragma mark - API

- (NSArray *)_expandedTypesFromPrimaryTypes:(NSArray *)primaryTypes;
{
    NSMutableArray *expandedTypes = [NSMutableArray array];
    [expandedTypes addObjectsFromArray:primaryTypes];
    for (NSString *primaryType in primaryTypes) {
        NSArray *fileExtensions = CFBridgingRelease(UTTypeCopyAllTagsWithClass((__bridge CFStringRef)primaryType, kUTTagClassFilenameExtension));
        for (NSString *fileExtension in fileExtensions) {
            NSString *expandedType = (NSString *)CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileExtension, NULL));
            if (expandedType != nil && ![expandedTypes containsObject:expandedType]) {
                [expandedTypes addObject:expandedType];
            }
        }
    }
    return expandedTypes;
}

- (NSArray <NSString *> *)editableFileTypes;
{
    return OADocumentFileTypes.main.writableTypeIdentifiers;
}

- (NSArray <NSString *> *)viewableFileTypes;
{
    return OADocumentFileTypes.main.readableTypeIdentifiers;
}

static NSSet *ViewableFileTypes()
{
    static dispatch_once_t onceToken;
    static NSSet *viewableFileTypes = nil;

    dispatch_once(&onceToken, ^{
        // Make a set all our declared UTIs, for fast contains-checking in canViewFileTypeWithIdentifier.
        viewableFileTypes = [NSSet setWithArray:OADocumentFileTypes.main.readableTypeIdentifiers];
    });

    return viewableFileTypes;
}

- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;
{
    OBPRECONDITION(!uti || [uti isEqualToString:[uti lowercaseString]]); // our cache uses lowercase keys.
    
    if (uti == nil)
        return NO;

    NSSet *viewableFileTypes = ViewableFileTypes();
    if ([viewableFileTypes containsObject:uti]) {
        return YES; // Performance fix: avoid calling OFTypeConformsTo, which calls UTTypeConformsTo, which is slow, when possible.
    }

    for (NSString *candidateUTI in viewableFileTypes) {
        if (OFTypeConformsTo(uti, candidateUTI))
            return YES;
    }
    return NO;
}

- (void)restoreSampleDocuments:(id)sender;
{
    OBFinishPortingWithNote("<bug:///176698> (Frameworks-iOS Unassigned: OBFinishPorting: -restoreSampleDocuments: in OUIDocumentAppController)");
#if 0
    OUIDocumentAppController *documentAppController = [OUIDocumentAppController controller];
    NSURL *sampleDocumentsURL = [documentAppController sampleDocumentsDirectoryURL];
    NSString *restoreSamplesViewControllerTitle = [documentAppController sampleDocumentsDirectoryTitle];
    NSPredicate *sampleDocumentsFilter = [documentAppController sampleDocumentsFilterPredicate];
    
    OUIRestoreSampleDocumentListController *restoreSampleDocumentsViewController = [[OUIRestoreSampleDocumentListController alloc] initWithSampleDocumentsURL:sampleDocumentsURL];
    restoreSampleDocumentsViewController.navigationItem.title = restoreSamplesViewControllerTitle;
    restoreSampleDocumentsViewController.fileFilterPredicate = sampleDocumentsFilter;
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:restoreSampleDocumentsViewController];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    [_documentPicker presentViewController:navigationController animated:YES completion:nil];
#endif
}

- (void)updatePreviewsFor:(id <NSFastEnumeration>)fileItems;
{
    [OUIDocumentPreview populateCacheForFileItems:fileItems completionHandler:^{
        [_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:fileItems];
    }];
}

#pragma mark - ODSStoreDelegate

- (NSString *)documentStoreBaseNameForNewFiles:(ODSStore *)store;
{
    return NSLocalizedStringFromTableInBundle(@"My Document", @"OmniUIDocument", OMNI_BUNDLE, @"Base name for newly created documents. This will have an number appended to it to make it unique.");
}

- (NSString *)documentStoreBaseNameForNewTemplateFiles:(ODSStore *)store;
{
    return NSLocalizedStringFromTableInBundle(@"My Template", @"OmniUIDocument", OMNI_BUNDLE, @"Base name for newly created templates. This will have an number appended to it to make it unique.");
}

- (NSString *)documentStore:(ODSStore *)store baseNameForFileImportedFromURL:(NSURL *)importedURL;
{
    return [importedURL.lastPathComponent stringByDeletingPathExtension];
}

- (NSArray *)documentCreationRequestEditableDocumentTypes:(OUINewDocumentCreationRequest *)request;
{
    return [self editableFileTypes];
}

- (void)presentSyncError:(NSError *)syncError forAccount:(OFXServerAccount *)account inViewController:(UIViewController *)viewController retryBlock:(void (^)(void))retryBlock;
{
    OBPRECONDITION(viewController);
    
    NSError *serverCertificateError = syncError.serverCertificateError;
    if (serverCertificateError != nil) {
        OUICertificateTrustAlert *certAlert = [[OUICertificateTrustAlert alloc] initForError:serverCertificateError];
        certAlert.shouldOfferTrustAlwaysOption = YES;
        certAlert.storeResult = YES;
        if (retryBlock) {
            certAlert.trustBlock = ^(OFCertificateTrustDuration trustDuration) {
                retryBlock();
            };
        }
        [certAlert findViewController:^{
            return viewController;
        }];
        [[[OUIAppController sharedController] backgroundPromptQueue] addOperation:certAlert];
        return;
    }
    
    NSError *displayError = OBFirstUnchainedError(syncError);

    NSError *httpError = [syncError underlyingErrorWithDomain:ODAVHTTPErrorDomain];
    while (httpError != nil && [httpError.userInfo objectForKey:NSUnderlyingErrorKey])
        httpError = [httpError.userInfo objectForKey:NSUnderlyingErrorKey];

    if (httpError != nil && [[httpError domain] isEqualToString:ODAVHTTPErrorDomain] && [[httpError.userInfo objectForKey:ODAVHTTPErrorDataContentTypeKey] isEqualToString:@"text/html"]) {
        OUIWebViewController *webController = [[OUIWebViewController alloc] init];
        webController.delegate = self;
        
        // webController.title = [displayError localizedDescription];
        (void)[webController view]; // Load the view so we get its navigation set up
        webController.navigationItem.leftBarButtonItem = nil; // We don't want a disabled "Back" button on our error page
        [webController loadData:[httpError.userInfo objectForKey:ODAVHTTPErrorDataKey] ofType:[httpError.userInfo objectForKey:ODAVHTTPErrorDataContentTypeKey]];
        UINavigationController *webNavigationController = [[UINavigationController alloc] initWithRootViewController:webController];
        webNavigationController.navigationBar.barStyle = UIBarStyleBlack;

        webNavigationController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
        [viewController presentViewController:webNavigationController animated:YES completion:retryBlock];
        self.webViewController = webController;
        return;
    }

    NSMutableArray *messages = [NSMutableArray array];

    NSString *reason = [displayError localizedFailureReason];
    if (![NSString isEmptyString:reason])
        [messages addObject:reason];

    NSString *suggestion = [displayError localizedRecoverySuggestion];
    if (![NSString isEmptyString:suggestion])
        [messages addObject:suggestion];

    NSString *message = [messages componentsJoinedByString:@"\n"];

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[displayError localizedDescription] message:message preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to ignore the error.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {}];
    [alertController addAction:okAction];

    if (account != nil) {
        UIAlertAction *editAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Edit Credentials", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to change the username and password.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {

            void (^editCredentials)(void) = ^{
                OBFinishPortingWithNote("<bug:///176699> (Frameworks-iOS Unassigned: OBFinishPorting: Handle editing OmniPresence credentials when presenting a sync error)");
#if 0
                [self.documentPicker editSettingsForAccount:account];
#endif
            };
            editCredentials = [editCredentials copy];
            OUIDocument *document = viewController.sceneDocument;
            if (document != nil) {
                [viewController.sceneDelegate closeDocumentWithCompletionHandler:^{
                    OBFinishPortingWithNote("<bug:///176699> (Frameworks-iOS Unassigned: OBFinishPorting: Handle editing OmniPresence credentials when presenting a sync error)");
#if 0
                    // Dismissing without animation and then immediately pushing into the top navigation controller causes the screen to be left blank. To prevent this, we dismiss with animation and use the completion handler to run the code that causes the push in the navigation controller.
                    // The document view controller isn't dismissed by -closeDocumentWithCompletionHandler:, which is arguably weird.
                    [self.documentPicker dismissViewControllerAnimated:YES completion:^{
                        editCredentials();
                    }];
#endif
                }];
            } else
                editCredentials();
        }];
        [alertController addAction:editAction];
    }

    if (retryBlock != NULL) {
        UIAlertAction *retryAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Retry Sync", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to retry syncing.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
            retryBlock();
        }];
        [alertController addAction:retryAction];
    }

    if ([MFMailComposeViewController canSendMail] && ODAVShouldOfferToReportError(syncError)) {
        UIAlertAction *reportAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Report Error", @"OmniUIDocument", OMNI_BUNDLE, @"When displaying a sync error, this is the option to report the error.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {
            NSString *body = [NSString stringWithFormat:@"\n%@\n\n%@\n", [[OUIAppController controller] fullReleaseString], [syncError toPropertyList]];
            [[OUIAppController controller] sendFeedbackWithSubject:@"Sync failure" body:body inScene:viewController.view.window.windowScene];
        }];
        [alertController addAction:reportAction];
    }
    [viewController presentViewController:alertController animated:YES completion:^{}];
}

- (void)warnAboutDiscardingUnsyncedEditsInAccount:(OFXServerAccount *)account fromViewController:(UIViewController *)parentViewController withCancelAction:(void (^)(void))cancelAction discardAction:(void (^)(void))discardAction;
{
    if (cancelAction == NULL)
        cancelAction = ^{};

    if (account.usageMode != OFXServerAccountUsageModeCloudSync) {
        discardAction(); // This account doesn't sync, so there's nothing to warn about
        return;
    }

    assert(_syncAgent != nil); // Or we won't ever count anything!
    [_syncAgent countFileItemsWithLocalChangesForAccount:account completionHandler:^(NSError *errorOrNil, NSUInteger count) {
        if (count == 0) {
            discardAction(); // No unsynced changes
        } else {
            NSString *message;
            if (count == 1)
                message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The \"%@\" account has an edited document which has not yet been synced up to the cloud. Do you wish to discard those edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: message format"), account.displayName, count];
            else if (count == NSNotFound)
                message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The \"%@\" account may have edited documents which have not yet been synced up to the cloud. Do you wish to discard any local edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: message format"), account.displayName, count];
            else
                message = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The \"%@\" account has %ld edited documents which have not yet been synced up to the cloud. Do you wish to discard those edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: message format"), account.displayName, count];

            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Discard unsynced edits?", @"OmniUIDocument", OMNI_BUNDLE, @"Lose unsynced changes warning: title") message:message preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *cancelAlertAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: cancel button label") style:UIAlertActionStyleCancel handler:^(UIAlertAction * __nonnull action) {
                cancelAction();
            }];
            [alertController addAction:cancelAlertAction];

            UIAlertAction *discardAlertAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Discard Edits", @"OmniUIDocument", OMNI_BUNDLE, @"Discard unsynced edits dialog: discard button label")  style:UIAlertActionStyleDestructive handler:^(UIAlertAction * __nonnull action) {
                discardAction();
            }];
            [alertController addAction:discardAlertAction];

            [parentViewController presentViewController:alertController animated:YES completion:^{}];
        }
    }];
}

- (NSSet *)internalTemplateFileItems;
{
    return [NSSet set];
}

#pragma mark - Subclass responsibility

- (NSString *)newDocumentShortcutIconImageName;
{
    return @"3DTouchShortcutNewDocument";
}

- (UIImage *)documentPickerBackgroundImage;
{
    return nil;
}

- (UIColor *)emptyOverlayViewTextColor;
{
    UIWindow *window = [[self class] windowForScene:nil options:OUIWindowForSceneOptionsAllowCascadingLookup];
    return window.tintColor;
}

- (Class)documentExporterClass
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (Class)documentClassForURL:(NSURL *)url;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (BOOL)allowsMultiFileSharing
{
    // Default to not allowing this. Some of our apps can do this, others can't.
    
    // Historical comment for context:
    // Exporting more than one thing is really fine, except when sending OmniPlan files via Mail. But we don't have a good way to restrict just that. bug:///147627
    return NO;
}

- (UIColor *)launchActivityIndicatorColor
{
    UIWindow *window = [[self class] windowForScene:nil options:OUIWindowForSceneOptionsAllowCascadingLookup];
    return window.tintColor;
}

#pragma mark -
#pragma mark UIApplicationDelegate

- (void)_delayedFinishLaunchingAllowCopyingSampleDocuments:(BOOL)allowCopyingSampleDocuments
                                    openingDocumentWithURL:(NSURL *)launchDocumentURL
                                       orShowingOnlineHelp:(BOOL)showHelp
                                         completionHandler:(void (^)(void))completionHandler;
{
    DEBUG_LAUNCH(1, @"Delayed finish launching allowCopyingSamples:%d openURL:%@ orShowingHelp:%@", allowCopyingSampleDocuments, launchDocumentURL, showHelp ? @"YES" : @"NO");
    
    BOOL startedOpeningDocument = NO;
    ODSFileItem *launchFileItem = nil;
    
    if (launchDocumentURL) {
        launchFileItem = [_documentStore fileItemWithURL:launchDocumentURL];
        DEBUG_LAUNCH(1, @"  launchFileItem: %@", [launchFileItem shortDescription]);
    }
    
    completionHandler = [completionHandler copy];

    NSInteger builtInResourceVersion = [self builtInResourceVersion];
    if (allowCopyingSampleDocuments && launchDocumentURL == nil && [[NSUserDefaults standardUserDefaults] integerForKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"] < builtInResourceVersion) {
        // Copy in a welcome document if one exists and we haven't done so for first launch yet.
        [self copySampleDocumentsToUserDocumentsWithCompletionHandler:^(NSDictionary *nameToURL) {
            [[NSUserDefaults standardUserDefaults] setInteger:builtInResourceVersion forKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"];
            [[NSUserDefaults standardUserDefaults] setObject:[[NSDate date] xmlString] forKey:@"SampleDocumentsHaveBeenCopiedToUserDocumentsDate"];
        }];
        return;
    }

    if (launchFileItem != nil) {
        DEBUG_LAUNCH(1, @"Opening document %@", [launchFileItem shortDescription]);
        // We used to actually open the document here, but that fights with application:openURL:options:
//        [self openDocument:launchFileItem];
        startedOpeningDocument = YES;
    } else if (launchDocumentURL.isFileURL && !OFISEQUAL(launchDocumentURL.pathExtension, @"omnipresence-config")) {
        // application:openURL: will take care of opening the document...
        startedOpeningDocument = YES;
    } else {
        // Restore our selected or open document if we didn't get a command from on high.
        NSArray *launchAction = [self.launchAction copy];

        if (launchDocumentURL) {
            // We had a launch URL, but didn't find the file. This might be an OmniPresence config file -- don't open the document if any
            launchAction = nil;
        }
        
        DEBUG_LAUNCH(1, @"  launchAction: %@", launchAction);
        if ([launchAction isKindOfClass:[NSArray class]] && [launchAction count] == 2) {
            // Clear the launch action in case we crash while opening this file; we'll restore it if the file opens successfully.
            self.launchAction = nil;

            if (_isOpeningURL) {
                // We may have been cold launched with a requst from Spotlight or a shortcut. That path sets _isOpeningURL (which is kind of hacky) which we would have done here based on `startedOpeningDocument`.
                startedOpeningDocument = YES;
            } else {
                NSURL *launchURL = [self _urlForLaunchAction:launchAction];
                if (launchURL) {
                    OBFinishPortingLater("Open previously opened file?");
#if 0
                    [_documentBrowser revealDocumentAtURL:launchURL importIfNeeded:NO completion:^(NSURL * _Nullable revealedDocumentURL, NSError * _Nullable error) {
                        NSString *action = [launchAction objectAtIndex:0];
                        if ([action isEqualToString:OpenBookmarkAction]) {
                            DEBUG_LAUNCH(1, @"Opening file item %@", [launchFileItem shortDescription]);
                            [self _openDocument:launchFileItem isOpeningFromPeek:NO willPresentHandler:nil completionHandler:nil];
                            startedOpeningDocument = YES;
                        } else
                            fileItemToSelect = launchFileItem;
                    }];
#endif
                }
            }
        }
        if(allowCopyingSampleDocuments && ![[NSUserDefaults standardUserDefaults] boolForKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"]) {
            // The user is opening an inbox document. Copy the sample docs and pretend like we're already opening it
            [self copySampleDocumentsToUserDocumentsWithCompletionHandler:^(NSDictionary *nameToURL) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SampleDocumentsHaveBeenCopiedToUserDocuments"];
            }];
            if ([launchDocumentURL isFileURL] && OFISEQUAL([[launchDocumentURL path] pathExtension], @"omnipresence-config")) {
                startedOpeningDocument = NO; // If the 'launchDocumentURL' actually points to a config file, we're not going to open a document.
            }
            else {
                startedOpeningDocument = YES;
            }
        }
    }
    
    // Iff we didn't open a document, go to the document picker. We don't want to start loading of previews if the user is going directly to a document (particularly the welcome document).
    if (!startedOpeningDocument) {
        if (showHelp && self.hasOnlineHelp && [self shouldOpenOnlineHelpOnFirstLaunch]) {
            dispatch_after(0, dispatch_get_main_queue(), ^{
                [self showOnlineHelp:nil];
            });
        } else if (self.newsURLStringToShowWhenReady){
            self.readyToShowNews = YES;
            // [self showNewsURLString:self.newsURLStringToShowWhenReady evenIfShownAlready:NO];
        }
    } else {
        // Now that we are on screen, if we are waiting for a document to open, we'll just fade it in when it is loaded.
        _isOpeningURL = YES; // prevent preview generation while we are getting around to it
    }
    
    self.readyToShowNews = YES;
    if (completionHandler)
        completionHandler();
}

- (NSUInteger)_toolbarIndexForControl:(UIControl *)toolbarControl inToolbar:(UIToolbar *)toolbar;
{
    NSArray *toolbarItems = [toolbar items];
    for (id toolbarTarget in [toolbarControl allTargets]) {
        if ([toolbarTarget isKindOfClass:[UIBarButtonItem class]]) {
            return [toolbarItems indexOfObjectIdenticalTo:toolbarTarget];
        }
    }
    return [toolbarItems indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop) {
        UIBarButtonItem *toolbarItem = obj;
        return (BOOL)(toolbarItem.customView == toolbarControl);
    }];
}

#ifdef DEBUG_kc
#define DEBUG_TOOLBAR_AVAILABLE_WIDTH 1
#else
#define DEBUG_TOOLBAR_AVAILABLE_WIDTH 0
#endif

- (CGFloat)_availableWidthForResizingToolbarItems:(NSArray *)resizingToolbarItems inToolbar:(UIToolbar *)toolbar;
{
    NSUInteger firstIndexOfResizingItems = NSNotFound;
    NSUInteger lastIndexOfResizingItems = NSNotFound;
    NSUInteger currentIndex = 0;
    for (UIBarButtonItem *toolbarItem in [toolbar items]) {
        if ([resizingToolbarItems containsObjectIdenticalTo:toolbarItem]) {
            lastIndexOfResizingItems = currentIndex;
            if (firstIndexOfResizingItems == NSNotFound)
                firstIndexOfResizingItems = currentIndex;
        }
        currentIndex++;
    }

    CGFloat toolbarWidth = toolbar.frame.size.width;

    if (firstIndexOfResizingItems == NSNotFound)
        return toolbarWidth;

    CGFloat bogusWidth = ceil(1.2f * toolbarWidth / 500.0) * 500.0f;
    for (UIBarButtonItem *resizingItem in resizingToolbarItems) {
        OBASSERT(resizingItem.width == 0.0f); // Otherwise we should be keeping track of what the old width was so we can put it back
        resizingItem.width = bogusWidth;
    }
    [toolbar setNeedsLayout];
    [toolbar layoutIfNeeded];

    CGFloat leftWidth = 0.0f;
    CGFloat rightWidth = 0.0f;
    CGFloat floatingItemsLeftEdge = 0.0f;
    CGFloat floatingItemsRightEdge = 0.0f;
    CGFloat resizingItemsLeftEdge = 0.0f;
    CGFloat resizingItemsRightEdge = 0.0f;

    for (UIView *toolbarView in [toolbar subviews]) {
        if ([toolbarView isKindOfClass:[UIControl class]]) {
            UIControl *toolbarControl = (UIControl *)toolbarView;
            NSUInteger toolbarIndex = [self _toolbarIndexForControl:toolbarControl inToolbar:toolbar];
            if (toolbarIndex == NSNotFound) {
#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
                NSLog(@"DEBUG: Cannot find toolbar item for %@", toolbarControl);
#endif
            } else if (toolbarIndex < firstIndexOfResizingItems) {
                // This item is to the left of our resizing items
                CGRect toolbarControlFrame = toolbarControl.frame;
                CGFloat rightEdgeOfLeftItem = CGRectGetMaxX(toolbarControlFrame);
                if (rightEdgeOfLeftItem <= 0.0) {
                    // This item floats to the left of the resizing content
                    CGFloat leftEdge = CGRectGetMinX(toolbarControlFrame);
                    if (leftEdge < floatingItemsLeftEdge)
                        floatingItemsLeftEdge = leftEdge;
                } else {
                    if (rightEdgeOfLeftItem > leftWidth)
                        leftWidth = rightEdgeOfLeftItem;
#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
                    NSLog(@"DEBUG: toolbarIndex = %lu, rightEdgeOfLeftItem = %1.1f, leftWidth = %1.1f", toolbarIndex, rightEdgeOfLeftItem, leftWidth);
#endif
                }
            } else if (toolbarIndex > lastIndexOfResizingItems) {
                // This item is to the right of our resizing items
                CGRect toolbarControlFrame = toolbarControl.frame;
                CGFloat leftEdgeOfRightItem = CGRectGetMinX(toolbarControlFrame);
                if (leftEdgeOfRightItem >= toolbarWidth) {
                    // This item floats to the right of the resizing content
                    CGFloat rightEdge = CGRectGetMaxX(toolbarControlFrame);
                    if (rightEdge > floatingItemsRightEdge)
                        floatingItemsRightEdge = rightEdge;
                } else {
                    if (toolbarWidth - leftEdgeOfRightItem > rightWidth)
                        rightWidth = toolbarWidth - leftEdgeOfRightItem;
#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
                    NSLog(@"DEBUG: toolbarIndex = %lu, rightEdgeOfLeftItem = %1.1f, rightWidth = %1.1f", toolbarIndex, leftEdgeOfRightItem, rightWidth);
#endif
                }
            } else {
                CGRect toolbarControlFrame = toolbarControl.frame;
                CGFloat leftEdge = CGRectGetMinX(toolbarControlFrame);
                CGFloat rightEdge = CGRectGetMaxX(toolbarControlFrame);
                if (leftEdge < resizingItemsLeftEdge)
                    resizingItemsLeftEdge = leftEdge;
                if (rightEdge > resizingItemsRightEdge)
                    resizingItemsRightEdge = rightEdge;
#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
                NSLog(@"DEBUG: toolbarIndex = %lu, resizing control=%@", toolbarIndex, toolbarControl);
#endif
            }
        }
    }

    CGFloat floatingItemsWidth = 0.0f;

    if (floatingItemsLeftEdge < resizingItemsLeftEdge)
        floatingItemsWidth += resizingItemsLeftEdge - floatingItemsLeftEdge;

    if (floatingItemsRightEdge > resizingItemsRightEdge)
        floatingItemsWidth += floatingItemsRightEdge - resizingItemsRightEdge;

    CGFloat availableWidth = toolbarWidth - floatingItemsWidth - leftWidth - rightWidth - 8.0f - 8.0f; /* Leave a margin on both sides */

#if DEBUG_TOOLBAR_AVAILABLE_WIDTH
    NSLog(@"DEBUG: availableWidth = %1.1f (toolbarWidth = %1.1f, floatingItemsWidth = %1.1f, leftWidth = %1.1f, rightWidth = %1.1f)", availableWidth, toolbarWidth, floatingItemsWidth, leftWidth, rightWidth);
#endif

    for (UIBarButtonItem *resizingItem in resizingToolbarItems) {
        resizingItem.width = 0.0f; // Put back the old widths
    }

    return availableWidth;
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void(^)(NSArray<id<UIUserActivityRestoring>> * __nullable restorableObjects))restorationHandler;
{
    OBFinishPortingLater("Figure out which scene to hand off to and, well, hand off to it.");
    return NO;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    // UIKit throws an exception if UIBackgroundModes contains 'fetch' but the application delegate doesn't implement -application:performFetchWithCompletionHandler:. We want to be more flexible to allow apps to use our document picker w/o having to support background fetch.
    OBASSERT_IF([[[NSBundle mainBundle] infoDictionary][@"UIBackgroundModes"] containsObject:@"fetch"],
                [self respondsToSelector:@selector(application:performFetchWithCompletionHandler:)]);
    
    NSURL *launchOptionsURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    if (!launchOptionsURL)
        launchOptionsURL = self.searchResultsURL;
    
    // If we are getting launched into the background, try to stay alive until our document picker is ready to view (otherwise the snapshot in the app launcher will be bogus).
    OFBackgroundActivity *activity = nil;
    if ([application applicationState] == UIApplicationStateBackground)
        activity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniUI.OUIDocumentAppController.launching"];
    
    void (^launchAction)(void) = ^(void) {
        DEBUG_LAUNCH(1, @"Did launch with options %@", launchOptions);
        
        _documentStore = [[ODSStore alloc] initWithDelegate:self];

        // Pump the runloop once so that the -viewDidAppear: messages get sent before we muck with the view containment again. Otherwise, we never get -viewDidAppear: on the root view controller, and thus the OUILaunchViewController, causing assertions.
        //OUIDisplayNeededViews();
        
        DEBUG_LAUNCH(1, @"Creating document store");
        
        // Start out w/o syncing so that our initial setup will just find local documents. This is crufty, but it avoids hangs in syncing when we aren't able to reach the server.
        _syncAgent = [[OFXAgent alloc] init];
        _syncAgent.syncSchedule = (application.applicationState == UIApplicationStateBackground) ? OFXSyncScheduleManual : OFXSyncScheduleNone; // Allow the manual sync from -application:performFetchWithCompletionHandler: that we might be about to do. We just want to avoid automatic syncing.
        [_syncAgent applicationLaunched];
        _syncAgentForegrounded = _syncAgent.foregrounded; // Might be launched into the background
        
        _agentActivity = [[OFXAgentActivity alloc] initWithAgent:_syncAgent];
        
        // Wait for scopes to get their document URL set up.
        [_syncAgent afterAsynchronousOperationsFinish:^{
            DEBUG_LAUNCH(1, @"Sync agent finished first pass");
            
            _localScope = [[ODSLocalDirectoryScope alloc] initWithDirectoryURL:[self _localDirectoryURL] scopeType:ODSLocalDirectoryScopeNormal documentStore:_documentStore];
            [_documentStore addScope:_localScope];

            [_syncAgent addObserver:self forKeyPath:OFValidateKeyPath(_syncAgent, accountsSnapshot) options:0 context:&SyncAgentAccountsSnapshotContext];
            [self _updateBackgroundFetchInterval];
            
            NSURL *templateDirectoryURL = [self _templatesDirectoryURL];
            if (templateDirectoryURL) {
                ODSScope *templateScope = [[ODSLocalDirectoryScope alloc] initWithDirectoryURL:templateDirectoryURL scopeType:ODSLocalDirectoryScopeTemplate documentStore:_documentStore];
                [_documentStore addScope:templateScope];
            }

            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemContentsChangedNotification:) name:ODSFileItemContentsChangedNotification object:_documentStore];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_fileItemFinishedDownloadingNotification:) name:ODSFileItemFinishedDownloadingNotification object:_documentStore];
            
            __weak OUIDocumentAppController *weakSelf = self;

            // We have to wait for the document store to get results from its scopes
            [_documentStore addAfterInitialDocumentScanAction:^{
                DEBUG_LAUNCH(1, @"Initial scan finished");
                
                OUIDocumentAppController *strongSelf = weakSelf;
                OBASSERT(strongSelf);
                if (!strongSelf)
                    return;
                
                [strongSelf _updateCoreSpotlightIndex];
                
                [strongSelf _delayedFinishLaunchingAllowCopyingSampleDocuments:YES
                                                        openingDocumentWithURL:launchOptionsURL
                                                           orShowingOnlineHelp:NO // Don't always try to open the welcome document; just if we copy samples
                                                             completionHandler:^{
                                                                 
                    // Don't start generating previews until we have decided whether to open a document at launch time (which will prevent preview generation until it is closed).
                    strongSelf->_previewGenerator = [[OUIDocumentPreviewGenerator alloc] init];
                    strongSelf->_previewGenerator.delegate = strongSelf;
                    strongSelf->_previewGeneratorForegrounded = YES;


                    // Cache population should have already started, but we should wait for it before queuing up previews.
                    [OUIDocumentPreview afterAsynchronousPreviewOperation:^{
                        [strongSelf->_previewGenerator enqueuePreviewUpdateForFileItemsMissingPreviews:[strongSelf _mergedFileItems]];
                    }];

                    [activity finished];
                                                                 
                    // If we have an expired temporary license, we likely want to notify the user. Do this after the activity finishes so that any UI we bring up does not appear in the snapshot
                    [strongSelf checkTemporaryLicensingStateWithCompletionHandler:nil];
                }];
            }];

        
            // Go ahead and start syncing now.
            _syncAgent.syncSchedule = OFXSyncScheduleAutomatic;
        }];
        
        _didFinishLaunching = YES;

        // Possibly want to allow finer control over this, but it does the right thing for now.
        // OUIDocumentPreview.previewTemplateImageTintColor = window.tintColor;

        // Start real preview generation any time we are missing one.
        [[NSNotificationCenter defaultCenter] addObserverForName:OUIDocumentPickerItemViewPreviewsDidLoadNotification object:nil queue:nil usingBlock:^(NSNotification *note){
            OUIDocumentPickerItemView *itemView = [note object];
            for (OUIDocumentPreview *preview in itemView.loadedPreviews) {
                // Only do the update if we have a placeholder (no preview on disk). If we have a "empty" preview (meaning there was an error), don't redo the error-provoking work.
                if (preview.type == OUIDocumentPreviewTypePlaceholder) {
                    ODSFileItem *fileItem = [_documentStore fileItemWithURL:preview.fileURL];
                    OBASSERT(fileItem);
                    if (fileItem)
                        [_previewGenerator fileItemNeedsPreviewUpdate:fileItem];
                }
            }
        }];
    };

    // Might be invoked immediately or might be postponed (if we are handling a crash report).
    [self addLaunchAction:launchAction];

    return YES;
}

- (NSArray *)_launchActionForOpeningURL:(NSURL *)fileURL;
{
    NSError *bookmarkError = nil;
    NSData *bookmarkData = [fileURL bookmarkDataWithOptions:0 /* docs say to use NSURLBookmarkCreationWithSecurityScope, but SDK says not available on iOS */ includingResourceValuesForKeys:nil relativeToURL:nil error:&bookmarkError];
    if (bookmarkData != nil) {
        return @[OpenBookmarkAction, bookmarkData];
    } else {
#ifdef DEBUG
        NSLog(@"Unable to create bookmark for %@: %@", fileURL, [bookmarkError toPropertyList]);
#endif
        return nil;
    }
}

- (NSURL *)_urlForLaunchAction:(NSArray *)launchAction;
{
    if (launchAction.count != 2)
        return nil;

    id launchParameter = launchAction[1];
    if ([launchParameter isKindOfClass:[NSData class]]) {
        NSData *bookmarkData = launchParameter;
        BOOL isStale = NO;
        return [NSURL URLByResolvingBookmarkData:bookmarkData options:0 relativeToURL:nil bookmarkDataIsStale:&isStale error:NULL];
    } else {
        NSString *launchParameterString = OB_CHECKED_CAST(NSString, launchParameter);
        return [NSURL URLWithString:launchParameterString];
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISystemIsSnapshottingNotification object:nil];
    [self destroyCurrentSnapshotTimer];
    DEBUG_LAUNCH(1, @"Will enter foreground");

    if (_syncAgent && _syncAgentForegrounded == NO) {
        _syncAgentForegrounded = YES;
        [_syncAgent applicationWillEnterForeground];
    }
    
    if (_documentStore && _previewGeneratorForegrounded == NO) {
        OBASSERT(_previewGenerator);
        _previewGeneratorForegrounded = YES;
        // Make sure we find the existing previews before we check if there are documents that need previews updated
        [self initializePreviewCache];
    }
}

- (NSSet *)_mergedFileItems;
{
    NSSet *mergedFileItems = _documentStore.mergedFileItems;
    return [mergedFileItems setByAddingObjectsFromSet:self.internalTemplateFileItems];
}

- (void)initializePreviewCache;
{
    [self updatePreviewsFor:[self _mergedFileItems]];
}

- (void)applicationDidEnterBackground:(UIApplication *)application;
{
    DEBUG_LAUNCH(1, @"Did enter background");
    
    [self _updateShortcutItems];

    // Radar 14075101: UIApplicationDidEnterBackgroundNotification sent twice if app with background activity is killed from Springboard
    if (_syncAgent && _syncAgentForegrounded) {
        _syncAgentForegrounded = NO;
        [_syncAgent applicationDidEnterBackground];
    }
    
    if (_documentStore && _previewGeneratorForegrounded) {
        _previewGeneratorForegrounded = NO;
        
        NSSet *mergedFileItems = [self _mergedFileItems];
        
        [[self class] _cleanUpDocumentStateNotUsedByFileItems:mergedFileItems];
        
        [_previewGenerator applicationDidEnterBackground];
        
        // Clean up unused previews
        [OUIDocumentPreview deletePreviewsNotUsedByFileItems:mergedFileItems];
    }
    
    
    //Register to observe the ViewDidLayoutSubviewsNotification, which we post in the -didLayoutSubviews method of the DocumentPickerViewController.
    //-didLayoutSubviews gets called during Apple's snapshots. Each time it is called while we are backgrounded, we assume they are taking another snapshot,
    //so we reset the countdown to clearing the cache (since the cache is used in generating the views they are snapshotting).
    _backgroundFlushActivity = [OFBackgroundActivity backgroundActivityWithIdentifier: @"com.omnigroup.OmniUI.OUIDocumentAppController.delayedCacheClearing"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willWaitForSnapshots) name:OUISystemIsSnapshottingNotification object: nil];
    
    //Need to actually kick off the timer, since the system may not take the snapshots that end up causing the notification to post, and we do want to clear the cache eventually.
    [self willWaitForSnapshots];
    
    [super applicationDidEnterBackground:application];
}

- (void)applicationWillTerminate:(UIApplication *)application;
{
    DEBUG_LAUNCH(1, @"Will terminate");

    // Radar 14075101: UIApplicationDidEnterBackgroundNotification sent twice if app with background activity is killed from Springboard (though in this case, we get 'did background' and then 'will terminate' and OFXAgent doesn't handle this since both transition it to its 'stopped' state).
    if (_syncAgent && _syncAgentForegrounded) {
        _syncAgentForegrounded = NO;
        [_syncAgent applicationWillTerminateWithCompletionHandler:nil];
    }
    
    [super applicationWillTerminate:application];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;
{
    DEBUG_LAUNCH(1, @"Memory warning");

    [super applicationDidReceiveMemoryWarning:application];
    
    [OUIDocumentPreview discardHiddenPreviews];
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options;
{
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil sessionRole:connectingSceneSession.role];
    configuration.sceneClass = [UIWindowScene class];
    configuration.delegateClass = [OUIDocumentSceneDelegate class];
    configuration.storyboard = nil;
    return configuration;
}

#pragma mark - UIApplicationShortcutItem Handling

- (void)_updateShortcutItems
{
    // Update quicklaunch actions
    NSMutableArray <UIApplicationShortcutItem *> *shortcutItems = [[NSMutableArray <UIApplicationShortcutItem *> alloc] init];

    if (self.canCreateNewDocument) {
        // dynamically create the "new document" option
        UIApplicationShortcutIcon *newDocShortcutIcon = [UIApplicationShortcutIcon iconWithTemplateImageName:[self newDocumentShortcutIconImageName]];
        NSString *newDocumentLocalizedTitle = NSLocalizedStringWithDefaultValue(@"New Document", @"OmniUIDocument", OMNI_BUNDLE, @"New Document", @"New Template button title");
        UIApplicationShortcutItem *newDocItem = [[UIApplicationShortcutItem alloc] initWithType:ODSShortcutTypeNewDocument localizedTitle:newDocumentLocalizedTitle localizedSubtitle:nil icon:newDocShortcutIcon userInfo:nil];
        [shortcutItems addObject:newDocItem];
    }
    
    [UIApplication sharedApplication].shortcutItems = shortcutItems;
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler;
{
    if ([shortcutItem.type hasSuffix:@".shortcut-items.open-recent"]) {
        // Open Recent
        NSString *urlString = [shortcutItem.userInfo stringForKey:ODSOpenRecentDocumentShortcutFileKey];
        if (![NSString isEmptyString:urlString]) {
            NSURL *url = [NSURL URLWithString:urlString];
            if (url) {
                [self _openDocumentWithURLAfterScan:url completion:^{
                    if (completionHandler) {
                        completionHandler(YES);
                    }
                }];
            } else {
                if (completionHandler) {
                    completionHandler(NO);
                }
            }
        } else {
            if (completionHandler) {
                completionHandler(NO);
            }
        }
    }
    else if ([shortcutItem.type hasSuffix:@".shortcut-items.new-document"]) {
        // __weak OUIDocumentAppController *weakSelf = self;  // weak self is only to keep compiler happy
        [self addLaunchAction:^{
            OBFinishPortingWithNote("<bug:///176705> (Frameworks-iOS Unassigned: OBFinishPorting: Handle new document shortcut item in OUIDocumentAppController)");
#if 0
            OUIDocumentAppController *strongSelf = weakSelf;
            [strongSelf.documentPicker.documentStore addAfterInitialDocumentScanAction:^{
                [strongSelf _closeAllDocumentsBeforePerformingBlock:^{
                    // New Document
                    OUIDocumentPicker *documentPicker = [strongSelf documentPicker];
                    [documentPicker navigateToScope:[[strongSelf documentPicker] localDocumentsScope] animated:NO];
                    [documentPicker.selectedScopeViewController newDocumentWithTemplateFileItem:nil documentType:ODSDocumentTypeNormal completion:^{
                        if (completionHandler) {
                            completionHandler(YES);
                        }
                    }];
                }];
            }];
#endif
        }];
    }
}

#pragma mark - ODSStoreDelegate

- (void)documentStore:(ODSStore *)store fileItem:(ODSFileItem *)fileItem willMoveToURL:(NSURL *)newURL;
{
    NSString *uniqueID = [[self class] spotlightIDForFileURL:fileItem.fileURL];
    if (uniqueID) {
        NSMutableDictionary *dict = [[self class] _spotlightToFileURL];
        [dict setObject:[[self class] _savedPathForFileURL:newURL] forKey:uniqueID];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"SpotlightToFileURLPathMapping"];
        
        if (![[fileItem.fileURL.path lastPathComponent] isEqualToString:[newURL.path lastPathComponent]]) {
            // title has changed, regenerate spotlight info
            [_previewGenerator fileItemNeedsPreviewUpdate:fileItem];
        }
    }
}

- (void)documentStore:(ODSStore *)store willRemoveFileItemAtURL:(NSURL *)destinationURL;
{
    NSString *uniqueID = [[self class] spotlightIDForFileURL:destinationURL];
    if (uniqueID) {
        [[CSSearchableIndex defaultSearchableIndex] deleteSearchableItemsWithIdentifiers:@[uniqueID] completionHandler: ^(NSError * __nullable error) {
            if (error)
                NSLog(@"Error deleting searchable item %@: %@", uniqueID, error);
        }];
        
        NSMutableDictionary *dict = [[self class] _spotlightToFileURL];
        [dict removeObjectForKey:uniqueID];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"SpotlightToFileURLPathMapping"];
    }
    
    NSString *identifierForURL = [self _persistentIdentifierForOpenDocumentActivityAtURL:destinationURL inStore:store];
    [NSUserActivity deleteSavedUserActivitiesWithPersistentIdentifiers:@[identifierForURL] completionHandler:^{}];
}

- (NSString *)_persistentIdentifierForOpenDocumentActivityAtURL:(NSURL *)url inStore:(ODSStore *)store
{
    if (url == nil) {
        // OmniPlan passes nil as the URL because it doesn't allow the user to specify a template when making a new document.
        return @"NewDocumentFromDefaultTemplate";
    }

    NSString *scopeString;
    for (ODSScope *scope in store.scopes) {
        if ([scope isFileInContainer:url]) {
            scopeString = scope.displayName;
        }
    }
    if (scopeString == nil) {
        scopeString = @"inAppBundle";
    }
    OBASSERT_NOTNULL(scopeString);
    NSString *identifier = url.lastPathComponent;
    if (scopeString == nil || identifier == nil) {
        return nil;
    }
    return [@[scopeString, identifier] componentsJoinedByString:@"."];
}

static NSMutableDictionary *spotlightToFileURL;

+ (NSMutableDictionary *)_spotlightToFileURL;
{
    if (!spotlightToFileURL) {
        NSDictionary *dictionary = [[NSUserDefaults standardUserDefaults] objectForKey:@"SpotlightToFileURLPathMapping"];
        if (dictionary)
            spotlightToFileURL = [dictionary mutableCopy];
        else
            spotlightToFileURL = [[NSMutableDictionary alloc] init];
    }
    return spotlightToFileURL;
}


+ (void)registerSpotlightID:(NSString *)uniqueID forDocumentFileURL:(NSURL *)fileURL;
{
    NSMutableDictionary *dict = [self _spotlightToFileURL];
    NSString *savedPath = [self _savedPathForFileURL:fileURL];
    if (savedPath) {
        [dict setObject:savedPath forKey:uniqueID];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"SpotlightToFileURLPathMapping"];
    }
}

+ (NSString *)spotlightIDForFileURL:(NSURL *)fileURL;
{
    NSString *path = [self _savedPathForFileURL:fileURL];
    NSArray *keys = [[self _spotlightToFileURL] allKeysForObject:path];
    return [keys lastObject];
}

+ (NSURL *)fileURLForSpotlightID:(NSString *)uniqueID;
{
    return [self _fileURLForSavedPath:[[self _spotlightToFileURL] objectForKey:uniqueID]];
}

+ (NSString *)_savedPathForFileURL:(NSURL *)fileURL;
{
    NSString *path = fileURL.path;
    NSString *home = NSHomeDirectory();
    if ([path hasPrefix:home]) // doing this replacement because container id (i.e. part of NSHomeDirectory()) changes on each software update
        path = [@"HOME-" stringByAppendingString:[path stringByRemovingPrefix:home]];
    return path;
}

+ (NSURL *)_fileURLForSavedPath:(NSString *)path;
{
    if (!path)
        return nil;
    
    if ([path hasPrefix:@"HOME-"])
        path = [NSHomeDirectory() stringByAppendingPathComponent:[path stringByRemovingPrefix:@"HOME-"]];
    return [NSURL fileURLWithPath:path];
}

- (void)_updateCoreSpotlightIndex;
{
    NSMutableDictionary *dict = [[self class] _spotlightToFileURL];
    
    // make mapping
    NSMutableDictionary *fileURLToSpotlight = [NSMutableDictionary dictionary];
    for (NSString *uniqueID in dict)
        [fileURLToSpotlight setObject:uniqueID forKey:[dict objectForKey:uniqueID]];

    // remove ids for files which still exist
    for (ODSFileItem *item in _documentStore.mergedFileItems) {
        [fileURLToSpotlight removeObjectForKey:[[self class] _savedPathForFileURL:item.fileURL]];
    }
    
    // whatever is left in mapping are missing indexed files
    NSMutableArray *missingIDs = [NSMutableArray array];
    for (NSString *savedPath in fileURLToSpotlight) {
        NSString *uniqueID = [fileURLToSpotlight objectForKey:savedPath];
        [missingIDs addObject:uniqueID];
        [dict removeObjectForKey:uniqueID];
    }
    if (missingIDs.count) {
        [[CSSearchableIndex defaultSearchableIndex] deleteSearchableItemsWithIdentifiers:missingIDs completionHandler: ^(NSError * __nullable error) {
            if (error)
                NSLog(@"Error deleting searchable items: %@", error);
        }];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:@"SpotlightToFileURLPathMapping"];
    }
}

#pragma mark - OUIDocumentPreviewGeneratorDelegate delegate

- (BOOL)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator isFileItemCurrentlyOpen:(ODSFileItem *)fileItem;
{
    OBFinishPortingLater("How much of OUIDocumentPreviewGenerator should we keep?");
    OBPRECONDITION(fileItem);
    return NO; // OFISEQUAL(_document.fileURL, fileItem.fileURL);
}

- (BOOL)previewGeneratorHasOpenDocument:(OUIDocumentPreviewGenerator *)previewGenerator;
{
    OBFinishPortingLater("How much of OUIDocumentPreviewGenerator should we keep?");
    OBPRECONDITION(_didFinishLaunching); // Don't start generating previews before the app decides whether to open a launch document
    return YES; // _isOpeningURL || _document != nil;
}

- (void)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator performDelayedOpenOfFileItem:(ODSFileItem *)fileItem;
{
    OBFinishPortingLater("How much of OUIDocumentPreviewGenerator should we keep?");
    [self documentPicker:nil openTappedFileItem:fileItem];
}

- (BOOL)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator shouldGeneratePreviewForURL:(NSURL *)fileURL;
{
    OBFinishPortingLater("How much of OUIDocumentPreviewGenerator should we keep?");
    return YES;
}

- (Class)previewGenerator:(OUIDocumentPreviewGenerator *)previewGenerator documentClassForFileURL:(NSURL *)fileURL;
{
    OBFinishPortingLater("How much of OUIDocumentPreviewGenerator should we keep?");
    return [self documentClassForURL:fileURL];
}

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &SyncAgentAccountsSnapshotContext) {
        if (object == _syncAgent && [keyPath isEqual:OFValidateKeyPath(_syncAgent, accountsSnapshot)]) {
            [self _updateBackgroundFetchInterval];
        } else
            OBASSERT_NOT_REACHED("Unknown KVO keyPath");
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Document state

static NSString * const OUIDocumentViewStates = @"OUIDocumentViewStates";

+ (NSDictionary *)documentStateForFileEdit:(OFFileEdit *)fileEdit;
{
    OBPRECONDITION(fileEdit);

    NSString *identifier = fileEdit.uniqueEditIdentifier;
    NSDictionary *documentViewStates = [[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates];
    return [documentViewStates objectForKey:identifier];
}

+ (void)setDocumentState:(NSDictionary *)documentState forFileEdit:(OFFileEdit *)fileEdit;
{
    OBPRECONDITION(fileEdit);
    if (!fileEdit) {
        return;
    }

    // This gets called twice on save; once to remove the old edit's view state pointer and once to store the new view state under the new edit.
    // We could leave the old edit's document state in place, but it is easy for us to clean it up here rather than waiting for the app to be backgrounded.
    NSString *identifier = fileEdit.uniqueEditIdentifier;
    NSMutableDictionary *allDocsViewState = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates]];
    if (documentState)
        [allDocsViewState setObject:documentState forKey:identifier];
    else
        [allDocsViewState removeObjectForKey:identifier];
    [[NSUserDefaults standardUserDefaults] setObject:allDocsViewState forKey:OUIDocumentViewStates];
}

+ (void)copyDocumentStateFromFileEdit:(OFFileEdit *)fromFileEdit toFileEdit:(OFFileEdit *)toFileEdit;
{
    [self setDocumentState:[self documentStateForFileEdit:fromFileEdit] forFileEdit:toFileEdit];
}

+ (void)_cleanUpDocumentStateNotUsedByFileItems:(NSSet *)fileItems;
{
    // Clean up any document's view state that no longer applies
    
    NSDictionary *oldViewStates = [[NSUserDefaults standardUserDefaults] dictionaryForKey:OUIDocumentViewStates];
    NSMutableDictionary *newViewStates = [NSMutableDictionary dictionary];
    
    for (ODSFileItem *fileItem in fileItems) {
        NSString *identifier = fileItem.fileEdit.uniqueEditIdentifier;
        if (!identifier)
            continue;
        NSDictionary *viewState = oldViewStates[identifier];
        if (viewState)
            newViewStates[identifier] = viewState;
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:newViewStates forKey:OUIDocumentViewStates];
}

#pragma mark - Private

static NSString * const OUINextLaunchActionDefaultsKey = @"OUINextLaunchAction";

- (NSArray *)launchAction;
{
    NSArray *action = [[NSUserDefaults standardUserDefaults] objectForKey:OUINextLaunchActionDefaultsKey];
    DEBUG_LAUNCH(1, @"Launch action is %@", action);
    return action;
}

- (void)setLaunchAction:(NSArray *)launchAction;
{
    DEBUG_LAUNCH(1, @"Setting launch action %@", launchAction);
    [[NSUserDefaults standardUserDefaults] setObject:launchAction forKey:OUINextLaunchActionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)_updateBackgroundFetchInterval;
{
    OBPRECONDITION(_syncAgent);
    
    NSTimeInterval backgroundFetchInterval;
    OFXServerAccountsSnapshot *accountsSnapshot = _syncAgent.accountsSnapshot;

    if ([accountsSnapshot.runningAccounts count] > 0) {
        DEBUG_FETCH(1, @"Setting minimum fetch interval to \"minimum\".");
        backgroundFetchInterval = UIApplicationBackgroundFetchIntervalMinimum;
    } else {
        DEBUG_FETCH(1, @"Setting minimum fetch interval to \"never\".");
        backgroundFetchInterval = UIApplicationBackgroundFetchIntervalNever;
    }

    [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:backgroundFetchInterval];
}

static void _updatePreviewForFileItem(OUIDocumentAppController *self, NSNotification *note)
{
    OBPRECONDITION([note object] == self->_documentStore);

    ODSFileItem *fileItem = [[note userInfo] objectForKey:ODSFileItemInfoKey];
    OBASSERT([fileItem isKindOfClass:[ODSFileItem class]]);

    [self->_previewGenerator fileItemNeedsPreviewUpdate:fileItem];
}

- (void)_fileItemContentsChangedNotification:(NSNotification *)note;
{
    _updatePreviewForFileItem(self, note);
}

- (void)_fileItemFinishedDownloadingNotification:(NSNotification *)note;
{
    OBFinishPorting;
#if 0
    if (self.awaitedFileItemDownloads != nil && self.awaitedFileItemDownloads.count > 0) {
        ODSFileItem *finishedFileItem = note.userInfo[ODSFileItemInfoKey];
        ODSFileItem *awaitedFileItem = self.awaitedFileItemDownloads[0];
        if ([finishedFileItem fileURL] == [awaitedFileItem fileURL]) {
            self.awaitedFileItemDownloads = nil;
            [self openDocument:awaitedFileItem];
            // we only put it in this queue if we got security access, so we should always stop accessing.
            [awaitedFileItem.fileURL stopAccessingSecurityScopedResource];
        }
    }
    _updatePreviewForFileItem(self, note);
#endif
}

- (void)_openDocumentWithURLAfterScan:(NSURL *)fileURL completion:(void(^)(void))completion;
{
    OBFinishPorting;
#if 0
    // We should be called early on, before any previously open document has been opened.
    OBPRECONDITION(_isOpeningURL == NO);
    OBPRECONDITION(_document == nil);

    // Note that we are in the middle of handling a request to open a URL. This will disable opening of any previously open document in the rest of the launch sequence.
    _isOpeningURL = YES;

    void (^afterScanAction)(void) = ^(void){
        ODSFileItem *launchFileItem = [_documentStore fileItemWithURL:fileURL];
        if (launchFileItem != nil && (!_document || _document.fileItem != launchFileItem)) {
            if (_document) {
                [self closeDocumentWithCompletionHandler:^{
                    [self _setDocument:nil];    // in -closeDocumentWithCompletionHandler:, this block will get called before _setDocument:nil gets called. That messes with -openDocument: so setting the document to nil first
                    [self openDocument:launchFileItem];
                    if (completion) {
                        completion();
                    }
                }];
            } else {
                [self openDocument:launchFileItem];
                if (completion) {
                    completion();
                }
            }
        } else {
            if (completion) {
                completion();
            }
        }
    };
    void (^launchAction)(void) = ^(void){
        [_documentStore addAfterInitialDocumentScanAction:afterScanAction];
    };
    [self addLaunchAction:launchAction];
#endif
}

- (NSURL *)_localDirectoryURL
{
    return [ODSLocalDirectoryScope userDocumentsDirectoryURL];
}

- (NSURL *)_templatesDirectoryURL
{
    return [ODSLocalDirectoryScope templateDirectoryURL];
}

#pragma mark -Snapshots

- (void)didFinishWaitingForSnapshots;
{
    [OUIDocumentPreview flushPreviewImageCache];
    [_backgroundFlushActivity finished];
}

@end
