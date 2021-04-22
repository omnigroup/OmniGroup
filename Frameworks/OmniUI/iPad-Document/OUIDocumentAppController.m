// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentAppController.h>

@import CoreSpotlight;
@import MobileCoreServices;
@import OmniAppKit;
@import OmniBase;
@import OmniDAV;
@import OmniDocumentStore;
@import OmniFileExchange;
@import OmniFoundation;
@import OmniUI;
@import UIKit;

#import <OmniUIDocument/OUIDocument.h>
#import <OmniUIDocument/OUIDocumentSceneDelegate.h>
#import <OmniUIDocument/OUIDocumentViewController.h>
#import <OmniUIDocument/OUIErrors.h>
#import <OmniUIDocument/OUIToolbarTitleButton.h>
#import <OmniUIDocument/OmniUIDocument-Swift.h>

#import "OUIDocumentInbox.h"
#import "OUIDocumentParameters.h"
#import "OUIDocumentSyncActivityObserver.h"
#import "OUINewDocumentCreationRequest.h"
#import "OUIRestoreSampleDocumentListController.h"

static NSString * const OpenBookmarkAction = @"openBookmark";

NSString * const OUIShortcutTypeNewDocument = @"com.omnigroup.framework.OmniUIDocument.shortcut-items.new-document";

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

@interface OUIDocumentAppController () <OUIWebViewControllerDelegate, OUIDocumentCreationRequestDelegate>

@property (nonatomic, weak) OUIWebViewController *webViewController;

@property (nonatomic, strong) UIImage *agentStatusImage;

@property (atomic, strong, readwrite) NSURL *iCloudDocumentsURL;

@end

static unsigned SyncAgentAccountsSnapshotContext;

@implementation OUIDocumentAppController
{
    OFXAgent *_syncAgent;
    BOOL _syncAgentForegrounded; // Keep track of whether we have told the sync agent to run. We might get backgrounded while starting up (when handling a crash alert, for example).
    OUIDocumentSyncActivityObserver *_syncActivityObserver;
    
    OFBackgroundActivity *_backgroundFlushActivity;

    NSString *_agentStatusImageName;
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
            OUIDocumentAppController.localDocumentsDisplayName = NSLocalizedStringFromTableInBundle(@"On My iPhone", @"OmniUIDocument", OMNI_BUNDLE, @"Local Documents device-specific display name (should match the name of the On My iPhone location in the Files app on an iPhone)");
            break;
        case UIUserInterfaceIdiomPad:
            OUIDocumentAppController.localDocumentsDisplayName = NSLocalizedStringFromTableInBundle(@"On My iPad", @"OmniUIDocument", OMNI_BUNDLE, @"Local Documents device-specific display name (should match the name of the On My iPad location in the Files app on an iPad)");
            break;
        default:
            OBASSERT_NOT_REACHED("Add a proper localized device name");
            OUIDocumentAppController.localDocumentsDisplayName = NSLocalizedStringFromTableInBundle(@"Local Documents", @"OmniUIDocument", OMNI_BUNDLE, @"Local Documents display name");
            break;
    }
}

static NSString *_customLocalDocumentsDisplayName;

+ (void)setLocalDocumentsDisplayName:(NSString *)localDocumentsDisplayName;
{
    _customLocalDocumentsDisplayName = [localDocumentsDisplayName copy];
}

+ (NSString *)localDocumentsDisplayName;
{
    return _customLocalDocumentsDisplayName != nil ? _customLocalDocumentsDisplayName : NSLocalizedStringFromTableInBundle(@"Local Documents", @"OmniUIDocument", OMNI_BUNDLE, @"Local Documents display name");
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

- (instancetype)init;
{
    self = [super init];
    if (self == nil)
        return nil;

    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperationWithBlock:^{
        NSURL *containerURL = [NSFileManager.defaultManager URLForUbiquityContainerIdentifier:nil];
        NSURL *documentsURL = [containerURL.URLByStandardizingPath URLByAppendingPathComponent:@"Documents"];
        self.iCloudDocumentsURL = documentsURL;
    }];

    return self;
}

// Called at app startup if the main xib didn't have a window outlet hooked up.
- (UIWindow *)makeMainWindowForScene:(UIWindowScene *)scene
{
    NSString *windowClassName = [[OFPreference preferenceForKey:@"OUIMainWindowClass"] stringValue];
    Class windowClass = ![NSString isEmptyString:windowClassName] ? NSClassFromString(windowClassName) : [UIWindow class];
    OBASSERT(OBClassIsSubclassOfClass(windowClass, [UIWindow class]));
    
    UIWindow *window = [[windowClass alloc] initWithWindowScene:scene];
    window.backgroundColor = [UIColor systemBackgroundColor];
    return window;
}

- (nullable __kindof OUIDocument *)mostRecentlyActiveDocument;
{
    UIScene *documentScene = [self mostRecentlyActiveSceneSatisfyingCondition:^BOOL(UIScene *scene) {
        id <UISceneDelegate> sceneDelegate = scene.delegate;
        return [sceneDelegate isKindOfClass:[OUIDocumentSceneDelegate class]] &&  ((OUIDocumentSceneDelegate *)sceneDelegate).document != nil;
    }];
    OUIDocumentSceneDelegate *sceneDelegate = OB_CHECKED_CAST_OR_NIL(OUIDocumentSceneDelegate, documentScene.delegate);
    return sceneDelegate.document;
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

- (void)copySampleDocumentsToUserDocumentsWithCompletionHandler:(void (^)(NSDictionary <NSString *, NSURL *> *nameToURL))completionHandler;
{
    NSURL *samplesDirectoryURL = [self sampleDocumentsDirectoryURL];
    if (!samplesDirectoryURL) {
        if (completionHandler)
            completionHandler(@{});
        return;
    }
        
    [self copySampleDocumentsFromDirectoryURL:samplesDirectoryURL toTargetURL:self.localDocumentsURL stringTableName:[self stringTableNameForSampleDocuments] completionHandler:completionHandler];
}

- (void)copySampleDocumentsFromDirectoryURL:(NSURL *)sampleDocumentsDirectoryURL toTargetURL:(NSURL *)targetURL stringTableName:(NSString *)stringTableName completionHandler:(void (^)(NSDictionary <NSString *, NSURL *> *nameToURL))completionHandler;
{
    completionHandler = [completionHandler copy];
    
    UIScene *documentScene = [self mostRecentlyActiveSceneSatisfyingCondition:^(UIScene *scene) {
        return [scene.delegate isKindOfClass:[OUIDocumentSceneDelegate class]];
    }];
    OUIDocumentSceneDelegate *sceneDelegate = OB_CHECKED_CAST_OR_NIL(OUIDocumentSceneDelegate, documentScene.delegate);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    __autoreleasing NSError *directoryContentsError = nil;
    NSArray *sampleURLs = [fileManager contentsOfDirectoryAtURL:sampleDocumentsDirectoryURL includingPropertiesForKeys:nil options:0 error:&directoryContentsError];
    if (sampleURLs == nil) {
        NSLog(@"Unable to find sample documents at %@: %@", sampleDocumentsDirectoryURL, [directoryContentsError toPropertyList]);
        if (completionHandler != nil)
            completionHandler(nil);
        return;
    }
    
    OFPreference *datePreference = [OFPreference preferenceForKey:@"SampleDocumentsHaveBeenCopiedToUserDocumentsDate" defaultValue:@""];
    NSString *lastInstallDateString = datePreference.stringValue;
    NSDate *lastInstallDate = [NSString isEmptyString:datePreference.stringValue] ? nil : [[NSDate alloc] initWithXMLString:lastInstallDateString];

    NSMutableDictionary <NSString *, NSURL *> *nameToURL = [NSMutableDictionary dictionary];
    for (NSURL *sampleURL in sampleURLs) {
        NSString *sampleName = [[sampleURL lastPathComponent] stringByDeletingPathExtension];
        
        NSString *localizedTitle = [[NSBundle mainBundle] localizedStringForKey:sampleName value:sampleName table:stringTableName];
        if ([NSString isEmptyString:localizedTitle]) {
            OBASSERT_NOT_REACHED("No localization available for sample document name");
            localizedTitle = sampleName;
        }
        NSString *extension = sampleURL.pathExtension;
        NSString *localizedFilenameWithExtension = [localizedTitle stringByAppendingPathExtension:extension];
        NSURL *targetFileURL = [targetURL URLByAppendingPathComponent:localizedFilenameWithExtension];

        void (^copyFile)(void) = ^{
            NSError *copyError = nil;
            if (![fileManager copyItemAtURL:sampleURL toURL:targetFileURL error:&copyError]) {
                NSLog(@"Failed to copy sample document %@: %@", sampleURL, copyError.toPropertyList);
                return;
            }

            // We used to set the "skip backup" attribute on these files, but doesn't that mean that a customer who edited one of these files wouldn't get their edited copy backed up?
            OBASSERT([nameToURL objectForKey:sampleName] == nil);
            [nameToURL setObject:targetFileURL forKey:sampleName];
        };

        if ([fileManager fileExistsAtPath:[targetFileURL path]]) {
            NSDictionary *oldResourceAttributes = [fileManager attributesOfItemAtPath:targetFileURL.path error:NULL];
            NSDate *oldResourceDate = [oldResourceAttributes fileModificationDate];

            // We are going to treat all sample documents which were previously copied over by our pre-universal apps as customized.  The logic here differs from what we do on the Mac.  On the Mac we use if (lastInstallDate != nil && ...
            if (lastInstallDate == nil || [oldResourceDate isAfterDate:lastInstallDate]) {
                NSString *customizedTitle = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"CustomizedSampleDocumentName", @"OmniUIDocument", OMNI_BUNDLE, @"%@ Customized", @"moved aside custom sample document name"), localizedTitle];
                if (sceneDelegate == nil) {
                    NSLog(@"Sample document named \"%@\" already exists, and no scene delegate is available to help pick an available file name", localizedFilenameWithExtension);
                    continue; // Guess we won't be updating this sample document
                }

                NSURL *customizedURL = [sceneDelegate urlForNewDocumentInFolderAtURL:targetURL baseName:customizedTitle extension:extension];

                NSError *moveError = nil;
                if (![fileManager moveItemAtURL:targetFileURL toURL:customizedURL error:&moveError]) {
                    NSLog(@"Failed to move customized sample document from \"%@\" to \"%@\": %@", localizedFilenameWithExtension, customizedURL.lastPathComponent, moveError.toPropertyList);
                    continue;
                }

                copyFile();
            } else {
                [fileManager removeItemAtURL:targetFileURL error:nil]; // We only care if the copy succeeds, not the delete
                copyFile();
            }
        } else {
            copyFile();
        }
    }

    if (completionHandler != nil)
        completionHandler(nameToURL);
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

- (NSURL *)localDocumentsURL;
{
    static NSURL *documentsURL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *locationError;
        documentsURL = [[[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&locationError] copy];
        if (documentsURL == nil) {
            NSLog(@"Unable to find the local documents folder: %@", locationError.toPropertyList);
        }
        assert(documentsURL != nil);
    });
    return documentsURL;
}

- (NSArray <NSString *> *)editableFileTypes;
{
    return OADocumentFileTypes.main.writableTypeIdentifiers;
}

- (NSArray <NSString *> *)viewableFileTypes;
{
    return OADocumentFileTypes.main.readableTypeIdentifiers;
}

- (NSArray <NSString *> *)templateFileTypes;
{
    return nil;
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

- (void)restoreSampleDocuments:(OUIMenuInvocation *)sender;
{
    UIWindow *window = sender.presentingViewController.view.window;
    [self _restoreSampleDocumentsInWindow:window];
}

- (void)_restoreSampleDocumentsInWindow:(UIWindow *)window;
{
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
    
    [window.rootViewController presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark Sync support

- (OUIMenuOption *)configureOmniPresenceMenuOption;
{
    OUIMenuOption *option = [[OUIMenuOption alloc] initWithTitle:[OUIServerAccountsViewController localizedDisplayNameForBrowsing:NO] image:self.configureOmniPresenceMenuImage action:^(OUIMenuInvocation *invocation) {
        UIView *view = invocation.presentingViewController.view;
        OUIDocumentSceneDelegate *sceneDelegate = [OUIDocumentSceneDelegate documentSceneDelegateForView:view];
        [sceneDelegate configureSyncAccounts];
    }];
    return option;
}

- (void)presentSyncError:(nullable NSError *)syncError inViewController:(UIViewController *)viewController retryBlock:(void (^ _Nullable)(void))retryBlock;
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

#pragma mark - Subclass responsibility

- (NSString *)newDocumentShortcutIconImageName;
{
    return @"3DTouchShortcutNewDocument";
}

- (UIColor *)emptyOverlayViewTextColor;
{
    UIWindow *window = [[self class] windowForScene:nil options:OUIWindowForSceneOptionsAllowFallbackLookup];
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

#pragma mark -
#pragma mark UIApplicationDelegate

- (void)_delayedFinishLaunchingAllowCopyingSampleDocuments:(BOOL)allowCopyingSampleDocuments completionHandler:(void (^)(void))completionHandler;
{
    DEBUG_LAUNCH(1, @"Delayed finish launching allowCopyingSamples:%@", allowCopyingSampleDocuments ? @"YES" : @"NO");
    
    completionHandler = [completionHandler copy];

    NSInteger builtInResourceVersion = [self builtInResourceVersion];
    OFPreference *versionPreference = [OFPreference preferenceForKey:@"SampleDocumentsHaveBeenCopiedToUserDocumentsVersion" defaultValue:@(0)];
    OFPreference *datePreference = [OFPreference preferenceForKey:@"SampleDocumentsHaveBeenCopiedToUserDocumentsDate" defaultValue:@""];
    if (allowCopyingSampleDocuments && versionPreference.integerValue < builtInResourceVersion) {
        // Copy in a welcome document if one exists and we haven't done so for first launch yet.
        [self copySampleDocumentsToUserDocumentsWithCompletionHandler:^(NSDictionary <NSString *, NSURL *> *nameToURL) {
            versionPreference.integerValue = builtInResourceVersion;
            datePreference.stringValue = [[NSDate date] xmlString];
            if (completionHandler != NULL)
                completionHandler();
        }];
    } else {
        if (completionHandler != NULL)
            completionHandler();
    }
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void(^)(NSArray<id<UIUserActivityRestoring>> * __nullable restorableObjects))restorationHandler;
{
    OBFinishPortingLater("<bug:///178487> (Frameworks-iOS Unassigned: Restore handoff support)");
    return NO;
}

- (void)_recoverLegacyTrashIfNeeded;
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *legacyTrashURL = [[OUIDocumentAppController legacyTrashDirectoryURL] absoluteURL];
    NSArray *trashedFiles = [fileManager contentsOfDirectoryAtURL:legacyTrashURL includingPropertiesForKeys:@[] options:0 error:nil];
    if (trashedFiles == nil || trashedFiles.count == 0)
        return; // We've already cleaned up our legacy trash, so there's nothing to do

    NSURL *localDocuments = self.localDocumentsURL;

    NSString *dateString = [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterNoStyle];
    NSString *recoveredTrashName = [NSString stringWithFormat:@"Trash (from %@)", dateString];
    NSURL *recoveredTrashURL = [localDocuments URLByAppendingPathComponent:recoveredTrashName isDirectory:YES];
    NSError *moveError = nil;
    NSInteger tryIndex = 1;

    while (![fileManager moveItemAtURL:legacyTrashURL toURL:recoveredTrashURL error:&moveError]) {
        if (![moveError hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError]) {
            // Not sure what error we could have gotten, but let's log it and move on
            NSLog(@"Unable to recover the legacy trash by moving %@ to %@: %@", legacyTrashURL.absoluteString, recoveredTrashURL.absoluteString, moveError.toPropertyList);
            return;
        }

        // Huh, there's already a folder named "Trash (from [today's date])"? Well, perhaps this person installed an old version of the app, got some new trash, then updated to the latest version again. Let's keep searching for a unique name for their new trash.
        tryIndex++;
        recoveredTrashName = [NSString stringWithFormat:@"Trash %@ (from %@)", @(tryIndex), dateString];
        recoveredTrashURL = [localDocuments URLByAppendingPathComponent:recoveredTrashName isDirectory:YES];
        moveError = nil;
    }

    NSLog(@"Recovered the legacy trash by moving %@ to %@", legacyTrashURL.absoluteString, recoveredTrashURL.absoluteString);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    (void)self.localDocumentsURL; // Make sure we have a local documents folder (in case the system hasn't already done this on our behalf)

    // UIKit throws an exception if UIBackgroundModes contains 'fetch' but the application delegate doesn't implement -application:performFetchWithCompletionHandler:. We want to be more flexible to allow apps to use our document picker w/o having to support background fetch.
    OBASSERT_IF([[[NSBundle mainBundle] infoDictionary][@"UIBackgroundModes"] containsObject:@"fetch"],
                [self respondsToSelector:@selector(application:performFetchWithCompletionHandler:)]);
    
    // If we are getting launched into the background, try to stay alive until our document picker is ready to view (otherwise the snapshot in the app launcher will be bogus).
    OFBackgroundActivity *activity = nil;
    if ([application applicationState] == UIApplicationStateBackground)
        activity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniUI.OUIDocumentAppController.launching"];
    
    void (^launchAction)(void) = ^(void) {
        DEBUG_LAUNCH(1, @"Did launch with options %@", launchOptions);
        
        [self _recoverLegacyTrashIfNeeded];

        // Start out w/o syncing so that our initial setup will just find local documents. This is crufty, but it avoids hangs in syncing when we aren't able to reach the server.
        _syncAgent = [[OFXAgent alloc] init];
        _syncAgent.syncSchedule = (application.applicationState == UIApplicationStateBackground) ? OFXSyncScheduleManual : OFXSyncScheduleNone; // Allow the manual sync from -application:performFetchWithCompletionHandler: that we might be about to do. We just want to avoid automatic syncing.
        [_syncAgent applicationLaunched];
        _syncAgentForegrounded = _syncAgent.foregrounded; // Might be launched into the background
        
        _agentActivity = [[OFXAgentActivity alloc] initWithAgent:_syncAgent];
        _syncActivityObserver = [[OUIDocumentSyncActivityObserver alloc] initWithAgentActivity:_agentActivity];

        __weak OUIDocumentAppController *weakSelf = self;
        _syncActivityObserver.accountChanged = ^(OFXServerAccount *account){
            [weakSelf _accountChanged:account];
        };
        _syncActivityObserver.accountsUpdated = ^(NSArray <OFXServerAccount *> *updatedAccounts, NSArray <OFXServerAccount *> *addedAccounts, NSArray <OFXServerAccount *> *removedAccounts) {
            OUIDocumentAppController *strongSelf = weakSelf; // Really, this instance exists for the life of the app anyway, but...
            if ([strongSelf _updateAgentStatusImage]) {
                [strongSelf _updateDocumentBrowserToolbarItems];
            }
        };

        [self _updateAgentStatusImage];

        // Wait for scopes to get their document URL set up.
        [_syncAgent afterAsynchronousOperationsFinish:^{
            DEBUG_LAUNCH(1, @"Sync agent finished first pass");
            
            [_syncAgent addObserver:self forKeyPath:OFValidateKeyPath(_syncAgent, accountsSnapshot) options:0 context:&SyncAgentAccountsSnapshotContext];
            [self _updateBackgroundFetchInterval];
            
            OUIDocumentAppController *strongSelf = weakSelf;
            OBASSERT(strongSelf);
            if (!strongSelf)
                return;

            [strongSelf _updateCoreSpotlightIndex];

            [strongSelf _delayedFinishLaunchingAllowCopyingSampleDocuments:YES completionHandler:^{
                [activity finished];
            }];

            // Go ahead and start syncing now.
            _syncAgent.syncSchedule = OFXSyncScheduleAutomatic;
        }];
    };

    // Might be invoked immediately or might be postponed (if we are handling a crash report).
    [self addLaunchAction:launchAction];

    return YES;
}

- (void)applicationWillEnterForeground;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUISystemIsSnapshottingNotification object:nil];
    [self destroyCurrentSnapshotTimer];
    DEBUG_LAUNCH(1, @"Will enter foreground");

    if (_syncAgent && _syncAgentForegrounded == NO) {
        _syncAgentForegrounded = YES;
        [_syncAgent applicationWillEnterForeground];
    }
    
    [super applicationWillEnterForeground];
}

- (void)applicationDidEnterBackground;
{
    DEBUG_LAUNCH(1, @"Did enter background");
    
    [self _updateShortcutItems];

    // Radar 14075101: UIApplicationDidEnterBackgroundNotification sent twice if app with background activity is killed from Springboard
    if (_syncAgent && _syncAgentForegrounded) {
        _syncAgentForegrounded = NO;
        [_syncAgent applicationDidEnterBackground];
    }

    //Register to observe the ViewDidLayoutSubviewsNotification, which we post in the -didLayoutSubviews method of the DocumentPickerViewController.
    //-didLayoutSubviews gets called during Apple's snapshots. Each time it is called while we are backgrounded, we assume they are taking another snapshot,
    //so we reset the countdown to clearing the cache (since the cache is used in generating the views they are snapshotting).
    _backgroundFlushActivity = [OFBackgroundActivity backgroundActivityWithIdentifier: @"com.omnigroup.OmniUI.OUIDocumentAppController.delayedCacheClearing"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willWaitForSnapshots) name:OUISystemIsSnapshottingNotification object: nil];
    
    //Need to actually kick off the timer, since the system may not take the snapshots that end up causing the notification to post, and we do want to clear the cache eventually.
    [self willWaitForSnapshots];
    
    [super applicationDidEnterBackground];
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
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options;
{
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil sessionRole:connectingSceneSession.role];
    configuration.sceneClass = [UIWindowScene class];
    configuration.delegateClass = OFISEQUAL(connectingSceneSession.role, UIWindowSceneSessionRoleExternalDisplay) ? nil : self.defaultSceneDelegateClass;
    configuration.storyboard = nil;
    return configuration;
}

#pragma mark -

- (Class)defaultSceneDelegateClass;
{
    return [OUIDocumentSceneDelegate class];
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
        UIApplicationShortcutItem *newDocItem = [[UIApplicationShortcutItem alloc] initWithType:OUIShortcutTypeNewDocument localizedTitle:newDocumentLocalizedTitle localizedSubtitle:nil icon:newDocShortcutIcon userInfo:nil];
        [shortcutItems addObject:newDocItem];
    }
    
    [UIApplication sharedApplication].shortcutItems = shortcutItems;
}

#pragma mark - ODSStoreDelegate

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
    OBFinishPortingLater("<bug:///177538> (Frameworks-iOS Unassigned: OBFinishPorting: Use Spotlight index extensions rather than having our app controllers maintain Spotlight indexes)");
#if 0
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
#endif
}

// This is for the trash scope for the OmniDocumentStore-based document picker. Note that Files.app on iOS 11 will create a .Trash directory inside the ~/Documents container for an app and move files there (which every application then needs to know to not look at).
+ (NSURL *)legacyTrashDirectoryURL;
{
    static NSURL *trashDirectoryURL = nil; // Avoid trying the creation on each call.

    if (!trashDirectoryURL) {
        __autoreleasing NSError *error = nil;
        NSURL *appSupportURL = [[[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error] copy];
        if (!appSupportURL) {
            NSLog(@"Error creating application support directory: %@", [error toPropertyList]);
        } else {
            trashDirectoryURL = [[appSupportURL URLByAppendingPathComponent:@"Trash" isDirectory:YES] URLByAppendingPathComponent:@"Documents" isDirectory:YES];

            error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtURL:trashDirectoryURL withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLog(@"Error creating trash directory: %@", [error toPropertyList]);
            }
        }
    }

    return trashDirectoryURL;
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

#pragma mark - Private

- (void)_accountChanged:(OFXServerAccount *)account;
{
    OFXAccountActivity *accountActivity = [_syncActivityObserver accountActivityForServerAccount:account];

    // Automatically download small files.
    for (OFXFileMetadata *metadata in accountActivity.registrationTable.values) {
        if (metadata.downloaded || metadata.hasDownloadQueued) {
            continue;
        }

        if ([_syncAgent shouldAutomaticallyDownloadItemWithMetadata:metadata]) {
            NSURL *fileURL = metadata.fileURL;
            if (!fileURL) {
                // Locally deleted file that hasn't been deleted on the server yet
                continue;
            }

            [_syncAgent requestDownloadOfItemAtURL:fileURL completionHandler:nil];
        }
    }

    if ([self _updateAgentStatusImage]) {
        [self _updateDocumentBrowserToolbarItems];
    }
}

- (nullable NSString *)_calculateCurrentAgentStatusImage;
{
    OFXAgent *agent = _agentActivity.agent;

    NSArray <OFXServerAccount *> *accounts = agent.accountRegistry.allAccounts;
    if (accounts.count == 0) {
        return nil;
    }

    // Check for accounts that weren't even able to start up
    if (agent.accountsSnapshot.failedAccounts.count != 0) {
        return @"OmniPresenceToolbarIcon-Error";
    }

    BOOL isOffline = agent.isOffline;

    // Check for errors that aren't just because our internet connection is offline
    __block BOOL accountHasError = NO;
    [_agentActivity eachAccountActivityWithError:^(OFXAccountActivity *accountActivity) {
        NSError *error = accountActivity.lastError;
        if (error != nil && (![error causedByUnreachableHost] || !isOffline))
            accountHasError = YES;
    }];

    if (accountHasError)
        return @"OmniPresenceToolbarIcon-Error";

    if (isOffline)
        return @"OmniPresenceToolbarIcon-Offline";

    if (_agentActivity.isActive)
        return @"OmniPresenceToolbarIcon-Active";

    return @"OmniPresenceToolbarIcon";
}

- (BOOL)_updateAgentStatusImage;
{
#ifdef DEBUG_kc
    NSLog(@"DEBUG: Updating agent status image");
#endif

    NSString *imageName = [self _calculateCurrentAgentStatusImage];
    if (_agentStatusImageName == imageName)
        return NO;

#ifdef DEBUG_kc
    NSLog(@"DEBUG: New agent status image: %@", imageName);
#endif

    _agentStatusImageName = imageName;
    self.agentStatusImage = [[UIImage imageNamed:imageName inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return YES;
}

- (void)_updateDocumentBrowserToolbarItems;
{
    [OUIDocumentSceneDelegate activeSceneDelegatesPerformBlock:^(OUIDocumentSceneDelegate *sceneDelegate) {
        [sceneDelegate updateBrowserToolbarItems];
    }];
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

    // <bug:///178582> (Frameworks-iOS Unassigned: Update background refresh code to us BGAppRefreshTask)
    [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:backgroundFetchInterval];
}

#pragma mark -Snapshots

- (void)didFinishWaitingForSnapshots;
{
    [super didFinishWaitingForSnapshots];
    [_backgroundFlushActivity finished];
}

@end
