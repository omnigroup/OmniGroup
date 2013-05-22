// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppController.h>

#import <OmniFileStore/OFSDocumentStoreDelegate.h>
#import <OmniUI/OUIUndoBarButtonItem.h>
#import <OmniUI/OUIBarButtonItemBackgroundType.h>
#import <OmniFileStore/OFSDocumentStoreDelegate.h>
#import <OmniUI/OUIMenuController.h>

@class OFSDocumentStoreFileItem, OFSDocumentStoreScope;
@class OFXAgentActivity, OFXServerAccount;
@class OUIDocument, OUIDocumentPicker, OUIMainViewController, OUIBarButtonItem;

typedef enum {
    OUIDocumentAnimationTypeZoom,
    OUIDocumentAnimationTypeDissolve,
} OUIDocumentAnimationType;

@interface OUIDocumentAppController : OUIAppController <UITextFieldDelegate, OUIUndoBarButtonItemTarget, OFSDocumentStoreDelegate, OUIMenuControllerDelegate, OFSDocumentStoreDelegate>

@property(nonatomic,retain) IBOutlet UIWindow *window;
@property(nonatomic,retain) IBOutlet OUIMainViewController *mainViewController;

@property(nonatomic,readonly) UIBarButtonItem *appMenuBarItem;
@property(nonatomic,readonly) OUIMenuController *appMenuController;

@property(nonatomic,retain) IBOutlet OUIDocumentPicker *documentPicker;

@property(nonatomic,readonly) UIBarButtonItem *documentTitleToolbarItem;
@property(nonatomic,readonly) UIBarButtonItem *closeDocumentBarButtonItem;
@property(nonatomic,readonly) OUIUndoBarButtonItem *undoBarButtonItem;
@property(nonatomic,readonly) UIBarButtonItem *infoBarButtonItem;
@property(nonatomic,readonly) BOOL shouldOpenWelcomeDocumentOnFirstLaunch;

@property(nonatomic,readonly) OFXAgentActivity *agentActivity;

- (NSArray *)editableFileTypes;
- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
- (IBAction)makeNewDocument:(id)sender;
- (IBAction)closeDocument:(id)sender;
- (void)closeDocumentWithAnimationType:(OUIDocumentAnimationType)animation completionHandler:(void (^)(void))completionHandler;

- (void)documentDidDisableEnditing:(OUIDocument *)document; // Incoming iCloud edit on an open document

- (void)updateDocumentTitle:(NSString *)newTitle;
- (void)updateTitleBarButtonItemSizeUsingInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;

- (OUIBarButtonItemBackgroundType)defaultBarButtonBackgroundType;

- (void)duplicateAndOpenFileItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem))completionHandler;

- (void)openDocument:(OFSDocumentStoreFileItem *)fileItem animation:(OUIDocumentAnimationType)animation showActivityIndicator:(BOOL)showActivityIndicator;

@property(nonatomic,readonly) OUIDocument *document;

// This is for debugging and ninja use, not production
- (void)invalidateDocumentPreviews;

// Sample documents
- (NSString *)sampleDocumentsDirectoryTitle;
- (NSURL *)sampleDocumentsDirectoryURL;
- (void)copySampleDocumentsToUserDocumentsWithCompletionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;
- (void)copySampleDocumentsFromDirectoryURL:(NSURL *)sampleDocumentsDirectoryURL toScope:(OFSDocumentStoreScope *)scope stringTableName:(NSString *)stringTableName completionHandler:(void (^)(NSDictionary *nameToURL))completionHandler;

- (NSString *)stringTableNameForSampleDocuments;
- (NSString *)localizedNameForSampleDocumentNamed:(NSString *)documentName;
- (NSURL *)URLForSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;

// UIApplicationDelegate methods we implement (see OUIAppController too)
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;
- (void)applicationWillEnterForeground:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;

// OFSDocumentStoreDelegate methods we implement
- (void)documentStore:(OFSDocumentStore *)store addedFileItems:(NSSet *)addedFileItems;
- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;
- (OFSDocumentStoreFileItem *)documentStore:(OFSDocumentStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;

// OUIDocumentPickerDelegate methods we implement
- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(OFSDocumentStoreFileItem *)fileItem;
- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(OFSDocumentStoreFileItem *)fileItem;

// Subclass responsibility
- (Class)documentClassForURL:(NSURL *)url;
- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;
- (void)mainThreadFinishedLoadingDocument:(OUIDocument *)document;  // For handling any loading that can't be done in a thread

// NSObject (OUIAppMenuTarget)
- (NSString *)aboutMenuTitle;
- (NSString *)feedbackMenuTitle;
- (void)sendFeedback:(id)sender;
- (void)showAppMenu:(id)sender;

// Optional OFSDocumentStoreDelegate that we implement
- (NSArray *)documentStoreEditableDocumentTypes:(OFSDocumentStore *)store;

// Helpful dialogs
- (void)presentSyncError:(NSError *)syncError inNavigationController:(UINavigationController *)navigationController retryBlock:(void (^)(void))retryBlock;
- (void)presentSyncError:(NSError *)syncError retryBlock:(void (^)(void))retryBlock;
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

