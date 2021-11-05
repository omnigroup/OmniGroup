// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIDocument.h>

#import <OmniFoundation/OFSaveType.h>
#import <OmniFoundation/OFCMS.h>

@class UIResponder, UIView, UIViewController;
@class OUIDocumentViewController;
@class OUIDocumentPreview, OUIImageLocation, OUIInteractionLock;

@protocol OUIDocumentViewController;

@interface OUIDocument : UIDocument <OFCMSKeySource>

// Can be overridden to provide a file inside the app wrapper to read into a new document. Returns nil by default.
+ (NSURL *)builtInBlankTemplateURL;

// This method should return YES when the file will be opened with one file type but saved using another file type (i.e., when .savingFileType will return a different value than .fileType).
+ (BOOL)shouldImportFileAtURL:(NSURL *)fileURL;

+ (BOOL)shouldShowAutosaveIndicator;

// Called when opening an existing document
- (instancetype)initWithExistingFileURL:(NSURL *)fileURL error:(NSError **)outError;

// Subclass this method if you need to set anything on the document after it's first been created from a template. (UUID's and the like). Callers of this method must perform file coordination on the template URL. The saveURL will be in a temporary location and doesn't need file coordination.
- (instancetype)initWithContentsOfTemplateAtURL:(NSURL *)templateURLOrNil toBeSavedToURL:(NSURL *)saveURL activityViewController:(UIViewController *)activityViewController error:(NSError **)outError;

// Subclass this method to handle reading of any files where +shouldImportFileAtURL: returns YES. Callers of this method must perform file coordination on the template URL. The saveURL will be in a temporary location and doesn't need file coordination.
- (instancetype)initWithContentsOfImportableFileAtURL:(NSURL *)importableURL toBeSavedToURL:(NSURL *)saveURL error:(NSError **)outError;

// This can be called when creating a document to be read into and then saved by non-framework code.
- (instancetype)initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;

// Funnel point for initializing documents
- (instancetype)initWithFileURL:(NSURL *)fileURL error:(NSError **)outError;

// Can set this before opening a document to tell it that it is being opened for preview generation. Later we might want more control of how errors are captured for off-screen document work, but for now this just makes errors get logged instead of presented to the user. The document view controller may also opt to load less data or otherwise speed up its work by only doing what is necessary for preview generation.
@property(nonatomic) BOOL forPreviewGeneration;

// Can set this before opening a document to tell it that it is being opened for the purpose of generating exported content.
@property(nonatomic) BOOL forExportOnly;

- (void)willEditDocumentTitle;

@property(nonatomic,readonly) UIViewController *viewControllerToPresent;
@property(nonatomic,readonly) __kindof UIViewController <OUIDocumentViewController> *documentViewController;
@property(nonatomic,readonly) BOOL editingDisabled;
@property(nonatomic) BOOL isDocumentEncrypted; // If it is encrypted, it will be unreadable.
@property(nonatomic, strong) OUIInteractionLock *applicationLock;

@property(nonatomic,readonly) BOOL isClosing;

@property(nonatomic,readonly) UIResponder *defaultFirstResponder; // Defaults to the documentViewController, or if that view controller implements -defaultFirstResponder, returns the result of that.

// If a document is being opened to be processed by a UIActivity, this can be set to the UIActivity's activityViewController to allow looking up a view controller on which to present UI (since the document won't have a view controller/scene of its own).
@property(nonatomic,weak) UIViewController *activityViewController;

- (void)finishUndoGroup;
- (void)forceUndoGroupClosed;
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;

// Convenience properties that are only valid during a save operation (between -saveToURL:... and invocation of its completion handler
@property (readonly) UIDocumentSaveOperation currentSaveOperation; // see OFSaveTypeForUIDocumentSaveOperation
@property (readonly) NSURL *currentSaveURL;

// Called after an incoming rename, but before -enableEditing. Subclasses can refresh their references to child file wrappers. Called on a background queue via -performAsynchronousFileAccessUsingBlock:.
- (void)reacquireSubItemsAfterMovingFromURL:(NSURL *)oldURL completionHandler:(void (^)(void))completionHandler;

- (void)viewStateChanged; // Marks the document as dirty w/o logging an undo. If the app is backgrounded or the document closed it will be saved, but it won't be saved if the editor state change is the only change.
- (void)beganUncommittedDataChange; // Can be used when the user has started a change (like editing a value in a text field) to request that the value be autosaved eventually. This requires that the document subclass knows how to save the partial edits and that the act of doing so makes a real undoable change. Calling this for editor state changes can result in taps to Undo resulting in data loss in the case that you make UIDocument think it is back to its last saved state.

// Gives the document a chance to break retain cycles.
- (void)didClose;

// Subclass responsibility

/*
 self.fileItem and self.undoManager will be set appropriately when this is called. If fileItem is nil, this is a new document, but the UIDocument's fileURL will be set no matter what.
 */
- (UIViewController <OUIDocumentViewController> *)makeViewController;
- (void)updateViewControllerToPresent;

// Optional subclass methods
- (void)willFinishUndoGroup;
- (BOOL)shouldUndo;
- (BOOL)shouldRedo;
- (void)didUndo;
- (void)didRedo;
- (UIView *)viewToMakeFirstResponderWhenInspectorCloses;

- (id)tearDownViewController;
- (void)recreateViewControllerWithViewState:(id)viewState;
// When we get an incoming change from iCloud, OUIDocument discards the view controller it got from -makeViewController and makes a new one. These can be subclassed to help tear down the view controller and to transition view state from the old to the new, if appropriate.
- (NSDictionary *)willRebuildViewController;
- (void)didRebuildViewController:(NSDictionary *)state;

// UIDocument method that we subclass and require our subclasses to call super on (though UIDocument strongly suggests it).
- (void)saveToURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation completionHandler:(void (^)(BOOL success))completionHandler NS_REQUIRES_SUPER;

- (void)accessSecurityScopedResourcesForBlock:(void (^ NS_NOESCAPE)(void))block;

//
+ (NSString *)displayNameForFileURL:(NSURL *)fileURL;
+ (NSString *)editingNameForFileURL:(NSURL *)fileURL;
+ (NSString *)exportingNameForFileURL:(NSURL *)fileURL;

@property(readonly,nonatomic) NSString *editingName;
@property(readonly,nonatomic) NSString *name;
@property(readonly,nonatomic) NSString *exportingName;

@property (readonly, nonatomic) BOOL canRename;
- (void)renameToName:(NSString *)name completionBlock:(void (^)(BOOL success, NSError *error))completionBlock;

/// Application-specific subclasses of OUIDocument can subclass this to report the file type identifiers that are available for this file. The argument `isFileExportToLocalDocuments` is YES only if we are doing a filesystem-based export (not send-to-app, etc) to the local iTunes accessible Documents folder. The default implementation returns nil, in which case the export interface will build a default set of types. A NSNull may be inserted into this array to represent "the current type".
+ (NSArray *)availableExportTypesForFileType:(NSString *)fileType isFileExportToLocalDocuments:(BOOL)isFileExportToLocalDocuments;
- (NSArray *)availableExportTypesToLocalDocuments:(BOOL)isFileExportToLocalDocuments;

@end

extern OFSaveType OFSaveTypeForUIDocumentSaveOperation(UIDocumentSaveOperation saveOperation);
