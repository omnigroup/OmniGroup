// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>

@class OFFileEdit;
@class OFXAgentActivity, OFXServerAccount;
@class OUIDocument, OUIBarButtonItem;
@class OUINewDocumentCreationRequest;

NS_ASSUME_NONNULL_BEGIN

@interface OUIDocumentAppController : OUIAppController

@property (class, nonatomic, copy) NSString *localDocumentsDisplayName;

- (UIWindow *)makeMainWindowForScene:(UIWindowScene *)scene; // Called to create the window for a new scene
@property (nonatomic, nullable, readonly) __kindof OUIDocument *mostRecentlyActiveDocument;

@property (nonatomic, nullable, readonly) OFXAgentActivity *agentActivity;
@property (nonatomic, nullable, readonly) UIImage *agentStatusImage;

@property (nonatomic, nullable, strong) NSURL *searchResultsURL; // document URL from continue user activity

@property (nonatomic, readonly) NSURL *localDocumentsURL;
@property (atomic, nullable, readonly) NSURL *iCloudDocumentsURL;

- (NSArray <NSString *> *)editableFileTypes;
- (NSArray <NSString *> *)viewableFileTypes;
@property (nonatomic, nullable, readonly) NSArray <NSString *> *templateFileTypes;

- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;

// Sample documents
- (NSInteger)builtInResourceVersion;
- (nullable NSString *)sampleDocumentsDirectoryTitle;
- (NSURL *)sampleDocumentsDirectoryURL;
- (nullable NSPredicate *)sampleDocumentsFilterPredicate;
- (void)copySampleDocumentsToUserDocumentsWithCompletionHandler:(void (^)(NSDictionary <NSString *, NSURL *> *nameToURL))completionHandler;

- (NSString *)stringTableNameForSampleDocuments;
- (NSString *)localizedNameForSampleDocumentNamed:(NSString *)documentName;
- (NSURL *)URLForSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;

// UIApplicationDelegate methods we implement (see OUIAppController too)
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(nullable NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions;
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options; // If you just want to substitute the default scene delegate class, use the .defaultSceneDelegateClass property rather than subclassing this. (Subclass this method when doing more advanced customizations, such as setting up a custom scene for an external display.)

@property (nonatomic, readonly) Class defaultSceneDelegateClass;

// Subclass responsibility
- (Class)documentExporterClass;
- (NSString *)newDocumentShortcutIconImageName;
- (nullable Class)documentClassForURL:(NSURL *)url;
- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;

// Per-app user activity definitions
+ (NSString *)openDocumentUserActivityType;
+ (NSString *)createDocumentFromTemplateUserActivityType;

// Sync support
@property (nonatomic, readonly) OUIMenuOption *configureOmniPresenceMenuOption;
- (void)presentSyncError:(nullable NSError *)syncError inViewController:(UIViewController *)viewController retryBlock:(void (^ _Nullable)(void))retryBlock;
- (void)warnAboutDiscardingUnsyncedEditsInAccount:(OFXServerAccount *)account fromViewController:(UIViewController *)parentViewController withCancelAction:(void (^ _Nullable)(void))cancelAction discardAction:(void (^)(void))discardAction;

// core spotlight
+ (void)registerSpotlightID:(NSString *)uniqueID forDocumentFileURL:(NSURL *)fileURL;
+ (NSString *)spotlightIDForFileURL:(NSURL *)fileURL;
+ (NSURL *)fileURLForSpotlightID:(NSString *)uniqueID;

// Where our old document picker used to put trashed files.
+ (NSURL *)legacyTrashDirectoryURL;

@end

extern NSString * const OUIShortcutTypeNewDocument;

NS_ASSUME_NONNULL_END
