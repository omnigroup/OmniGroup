// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppController.h>

#import <OmniDocumentStore/ODSStoreDelegate.h>
#import <OmniUI/OUIUndoBarButtonItem.h>
#import <OmniDocumentStore/ODSStoreDelegate.h>

@class ODSFileItem, OFFileEdit, ODSFileItemEdit, ODSScope;
@class OFXAgentActivity, OFXServerAccount;
@class OUIDocument, OUIDocumentPicker, OUIDocumentPickerViewController, OUIDocumentOpenAnimator, OUIBarButtonItem, UIViewController;

@interface OUIDocumentAppController : OUIAppController <OUIUndoBarButtonItemTarget, ODSStoreDelegate, ODSStoreDelegate>

@property(nonatomic,retain) IBOutlet UIWindow *window;
- (UIWindow *)makeMainWindow; // Called at app startup if the main xib didn't have a window outlet hooked up.

@property(nonatomic,retain) OUIDocumentPicker *documentPicker;

@property(nonatomic,readonly) BOOL useCompactBarButtonItemsIfApplicable; // will allow for possible compact versions of navbar items
@property(nonatomic,readonly) UIBarButtonItem *closeDocumentBarButtonItem;
@property(nonatomic,readonly) UIBarButtonItem *compactCloseDocumentBarButtonItem;
@property(nonatomic,readonly) UIBarButtonItem *infoBarButtonItem;
@property(nonatomic,readonly) UIBarButtonItem *uniqueInfoBarButtonItem; // This will be generated eachtime it is asked for

@property(nonatomic,readonly) OFXAgentActivity *agentActivity;

@property(nonatomic,retain) NSURL *searchResultsURL; // document URL from continue user activity

- (NSArray *)editableFileTypes;
- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;

- (IBAction)makeNewDocument:(id)sender;
- (IBAction)closeDocument:(id)sender;
- (void)closeAndDismissDocumentWithCompletionHandler:(void(^)(void))completionHandler;
- (void)closeDocumentWithCompletionHandler:(void(^)(void))completionHandler;

// Incoming iCloud edit on an open document
- (void)documentDidDisableEnditing:(OUIDocument *)document;
- (void)documentWillRebuildViewController:(OUIDocument *)document;
- (void)documentDidRebuildViewController:(OUIDocument *)document;

- (void)openDocument:(ODSFileItem *)fileItem;
- (void)openDocument:(ODSFileItem *)fileItem fromPeekWithWillPresentHandler:(void (^)(OUIDocumentOpenAnimator *openAnimator))willPresentHandler completionHandler:(void (^)(void))completionHandler;

@property(nonatomic,readonly) OUIDocument *document;

// This is for debugging and ninja use, not production
- (void)invalidateDocumentPreviews;

// For Quick Actions
- (NSArray <ODSFileItem *>*)recentlyEditedFileItems;

// Sample documents
- (NSInteger)builtInResourceVersion;
- (NSString *)sampleDocumentsDirectoryTitle;
- (NSURL *)sampleDocumentsDirectoryURL;
- (NSPredicate *)sampleDocumentsFilterPredicate;
- (void)copySampleDocumentsToUserDocumentsWithCompletionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
- (void)copySampleDocumentsFromDirectoryURL:(NSURL *)sampleDocumentsDirectoryURL toScope:(ODSScope *)scope stringTableName:(NSString *)stringTableName completionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;

- (NSString *)stringTableNameForSampleDocuments;
- (NSString *)localizedNameForSampleDocumentNamed:(NSString *)documentName;
- (NSURL *)URLForSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;

// Background fetch helper for OmniPresence-enabled apps
- (void)performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;

// UIApplicationDelegate methods we implement (see OUIAppController too)
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;
- (void)applicationWillEnterForeground:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;

// ODSStoreDelegate methods we implement
- (void)documentStore:(ODSStore *)store addedFileItems:(NSSet *)addedFileItems;
- (void)documentStore:(ODSStore *)store fileItemEdit:(ODSFileItemEdit *)fileItemEdit willCopyToURL:(NSURL *)newURL;
- (void)documentStore:(ODSStore *)store fileItemEdit:(ODSFileItemEdit *)fileItemEdit finishedCopyToURL:(NSURL *)destinationURL withFileItemEdit:(ODSFileItemEdit *)destinationFileItemEditOrNil;
- (ODSFileItem *)documentStore:(ODSStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;

// OUIDocumentPickerDelegate methods we implement
- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(ODSFileItem *)fileItem;
- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(ODSFileItem *)fileItem;

// API for linking to external documents
- (void)linkDocumentFromExternalContainer:(id)sender;
- (NSURL *)documentProviderMoreInfoURL;

// Subclass responsibility
- (Class)documentExporterClass;
- (NSString *)recentDocumentShortcutIconImageName;
- (NSString *)newDocumentShortcutIconImageName;
- (UIImage *)documentPickerBackgroundImage;
- (Class)documentClassForURL:(NSURL *)url;
- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;
- (void)mainThreadFinishedLoadingDocument:(OUIDocument *)document;  // For handling any loading that can't be done in a thread
- (BOOL)shouldOpenOnlineHelpOnFirstLaunch; //defaults YES, implemented this way so you can special-case demo builds.
// Optional ODSStoreDelegate that we implement
- (NSArray *)documentStoreEditableDocumentTypes:(ODSStore *)store;

// Helpful dialogs
- (void)presentSyncError:(NSError *)syncError forAccount:(OFXServerAccount *)account inViewController:(UIViewController *)viewController retryBlock:(void (^)(void))retryBlock;
- (void)warnAboutDiscardingUnsyncedEditsInAccount:(OFXServerAccount *)account withCancelAction:(void (^)(void))cancelAction discardAction:(void (^)(void))discardAction;

// document state
+ (NSDictionary *)documentStateForFileEdit:(OFFileEdit *)fileEdit;
+ (void)setDocumentState:(NSDictionary *)documentState forFileEdit:(OFFileEdit *)fileEdit;
+ (void)copyDocumentStateFromFileEdit:(OFFileEdit *)fromFileEdit toFileEdit:(OFFileEdit *)toFileEdit;

// core spotlight
+ (void)registerSpotlightID:(NSString *)uniqueID forDocumentFileURL:(NSURL *)fileURL;
+ (NSString *)spotlightIDForFileURL:(NSURL *)fileURL;
+ (NSURL *)fileURLForSpotlightID:(NSString *)uniqueID;

// Available for subclasses to override, in case it's not always a good time to process special URLs.
- (void)handleCachedSpecialURLIfNeeded;

@end


// These currently must all be implemented somewhere in the responder chain.
@interface NSObject (OUIAppMenuTarget)
- (void)showOnlineHelp:(id)sender;
- (void)sendFeedback:(id)sender;
- (void)showReleaseNotes:(id)sender;
- (void)restoreSampleDocuments:(id)sender;
- (void)runTests:(id)sender;
@end

