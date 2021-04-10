// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>

@class ODSFileItem, OFFileEdit, ODSFileItemEdit, ODSScope, ODSStore;
@class OFXAgentActivity, OFXServerAccount;
@class OUIDocument, OUIDocumentPicker, OUIDocumentPickerViewController, OUIBarButtonItem;
@class OUINewDocumentCreationRequest;

@interface OUIDocumentAppController : OUIAppController

- (UIWindow *)makeMainWindowForScene:(UIWindowScene *)scene; // Called to create the window for a new scene

@property(nonatomic,readonly) OFXAgentActivity *agentActivity;

@property(nonatomic,retain) NSURL *searchResultsURL; // document URL from continue user activity

- (NSArray <NSString *> *)editableFileTypes;
- (NSArray <NSString *> *)viewableFileTypes;

- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;

// Sample documents
- (NSInteger)builtInResourceVersion;
- (NSString *)sampleDocumentsDirectoryTitle;
- (NSURL *)sampleDocumentsDirectoryURL;
- (NSPredicate *)sampleDocumentsFilterPredicate;
- (void)copySampleDocumentsToUserDocumentsWithCompletionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;

- (NSString *)stringTableNameForSampleDocuments;
- (NSString *)localizedNameForSampleDocumentNamed:(NSString *)documentName;
- (NSURL *)URLForSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;

// Background fetch helper for OmniPresence-enabled apps
- (void)performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;

// UIApplicationDelegate methods we implement (see OUIAppController too)
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (void)applicationWillEnterForeground:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options;

// API for caching previews
- (void)updatePreviewsFor:(id <NSFastEnumeration>)fileItems;

// API for internal templates
- (NSSet *)internalTemplateFileItems;

// Subclass responsibility
- (Class)documentExporterClass;
- (NSString *)newDocumentShortcutIconImageName;
- (UIImage *)documentPickerBackgroundImage;
- (UIColor *)emptyOverlayViewTextColor;
- (Class)documentClassForURL:(NSURL *)url;
- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
- (BOOL)shouldOpenOnlineHelpOnFirstLaunch; //defaults YES, implemented this way so you can special-case demo builds.
// Optional ODSStoreDelegate that we implement
- (NSArray *)documentCreationRequestEditableDocumentTypes:(OUINewDocumentCreationRequest *)request;
/// Default is _window.tintColor.
- (UIColor *)launchActivityIndicatorColor;
@property (readonly) BOOL allowsMultiFileSharing;

// Per-app user activity definitions
+ (NSString *)openDocumentUserActivityType;
+ (NSString *)createDocumentFromTemplateUserActivityType;

// Helpful dialogs
- (void)presentSyncError:(NSError *)syncError forAccount:(OFXServerAccount *)account inViewController:(UIViewController *)viewController retryBlock:(void (^)(void))retryBlock;
- (void)warnAboutDiscardingUnsyncedEditsInAccount:(OFXServerAccount *)account fromViewController:(UIViewController *)parentViewController withCancelAction:(void (^)(void))cancelAction discardAction:(void (^)(void))discardAction;

// document state
+ (NSDictionary *)documentStateForFileEdit:(OFFileEdit *)fileEdit;
+ (void)setDocumentState:(NSDictionary *)documentState forFileEdit:(OFFileEdit *)fileEdit;
+ (void)copyDocumentStateFromFileEdit:(OFFileEdit *)fromFileEdit toFileEdit:(OFFileEdit *)toFileEdit;

// core spotlight
+ (void)registerSpotlightID:(NSString *)uniqueID forDocumentFileURL:(NSURL *)fileURL;
+ (NSString *)spotlightIDForFileURL:(NSURL *)fileURL;
+ (NSURL *)fileURLForSpotlightID:(NSString *)uniqueID;

@end

// These currently must all be implemented somewhere in the responder chain.
@interface NSObject (OUIAppMenuTarget)
- (void)showOnlineHelp:(id)sender;
- (void)sendFeedback:(id)sender;
- (void)showReleaseNotes:(id)sender;
- (void)restoreSampleDocuments:(id)sender;
- (void)runTests:(id)sender;
@end

