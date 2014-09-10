// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
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

@class ODSFileItem, ODSScope;
@class OFXAgentActivity, OFXServerAccount;
@class OUIDocument, OUIDocumentPicker, OUIDocumentPickerViewController, OUIBarButtonItem;

@interface OUIDocumentAppController : OUIAppController <OUIUndoBarButtonItemTarget, ODSStoreDelegate, ODSStoreDelegate>

@property(nonatomic,retain) IBOutlet UIWindow *window;
- (UIWindow *)makeMainWindow; // Called at app startup if the main xib didn't have a window outlet hooked up.

@property(nonatomic,retain) OUIDocumentPicker *documentPicker;

@property(nonatomic,readonly) UIBarButtonItem *closeDocumentBarButtonItem;
@property(nonatomic,readonly) OUIUndoBarButtonItem *undoBarButtonItem;
@property(nonatomic,readonly) UIBarButtonItem *infoBarButtonItem;

@property(nonatomic,readonly) OFXAgentActivity *agentActivity;

- (NSArray *)editableFileTypes;
- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;

- (IBAction)makeNewDocument:(id)sender;
- (IBAction)closeDocument:(id)sender;
- (void)closeDocumentWithCompletionHandler:(void(^)(void))completionHandler;

// Incoming iCloud edit on an open document
- (void)documentDidDisableEnditing:(OUIDocument *)document;
- (void)documentWillRebuildViewController:(OUIDocument *)document;
- (void)documentDidRebuildViewController:(OUIDocument *)document;

- (void)openDocument:(ODSFileItem *)fileItem;

@property(nonatomic,readonly) OUIDocument *document;

// This is for debugging and ninja use, not production
- (void)invalidateDocumentPreviews;

// Sample documents
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
- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate willMoveToURL:(NSURL *)newURL;
- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date finishedMoveToURL:(NSURL *)newURL successfully:(BOOL)successfully;
- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate willCopyToURL:(NSURL *)newURL;
- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate finishedCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate successfully:(BOOL)successfully;
- (ODSFileItem *)documentStore:(ODSStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;

// OUIDocumentPickerDelegate methods we implement
- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(ODSFileItem *)fileItem;
- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(ODSFileItem *)fileItem;

// Subclass responsibility
- (UIImage *)documentPickerBackgroundImage;
- (Class)documentClassForURL:(NSURL *)url;
- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;
- (void)mainThreadFinishedLoadingDocument:(OUIDocument *)document;  // For handling any loading that can't be done in a thread

// Optional ODSStoreDelegate that we implement
- (NSArray *)documentStoreEditableDocumentTypes:(ODSStore *)store;

// Helpful dialogs
- (void)presentSyncError:(NSError *)syncError inViewController:(UIViewController *)viewController retryBlock:(void (^)(void))retryBlock;
- (void)warnAboutDiscardingUnsyncedEditsInAccount:(OFXServerAccount *)account withCancelAction:(void (^)(void))cancelAction discardAction:(void (^)(void))discardAction;

// document state
+ (NSDictionary *)documentStateForURL:(NSURL *)documentURL;
+ (void)setDocumentState:(NSDictionary *)documentState forURL:(NSURL *)documentURL;
+ (void)moveDocumentStateFromURL:(NSURL *)fromDocumentURL toURL:(NSURL *)toDocumentURL deleteOriginal:(BOOL)deleteOriginal;

@end


// These currently must all be implemented somewhere in the responder chain.
@interface NSObject (OUIAppMenuTarget)
- (void)showOnlineHelp:(id)sender;
- (void)sendFeedback:(id)sender;
- (void)showReleaseNotes:(id)sender;
- (void)restoreSampleDocuments:(id)sender;
- (void)runTests:(id)sender;
@end

