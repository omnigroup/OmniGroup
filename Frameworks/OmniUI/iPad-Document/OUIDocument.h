// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIDocument.h>

#import <OmniFoundation/OFSaveType.h>
#import <OmniFoundation/OFCMS.h>
#import <OmniUIDocument/OUIDocumentPreview.h> // OUIDocumentPreviewArea

@class UIResponder, UIView, UIViewController;
@class ODSFileItem, OUIDocumentViewController;
@class OUIDocumentPreview, OUIImageLocation, OUIInteractionLock;

@protocol OUIDocumentViewController;

@interface OUIDocument : UIDocument <OFCMSKeySource>

+ (BOOL)shouldShowAutosaveIndicator;

// Called when opening an existing document
- initWithExistingFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;

// Subclass this method if you need to set anything on the document after it's first been created from a template. (UUID's and the like). Callers of this method must perform file coordination on the template URL. The saveURL will be in a temporary location and doesn't need file coordination.
- initWithContentsOfTemplateAtURL:(NSURL *)templateURLOrNil toBeSavedToURL:(NSURL *)saveURL error:(NSError **)outError;

// Subclass this method to handle reading of any CFBundleDocumentTypes returned from -[OUIDocumentAppController importableFileTypes]. Callers of this method must perform file coordination on the template URL. The saveURL will be in a temporary location and doesn't need file coordination.
- initWithContentsOfImportableFileAtURL:(NSURL *)importableURL toBeSavedToURL:(NSURL *)saveURL error:(NSError **)outError;

// This can be called when creating a document to be read into and then saved by non-framework code.
- initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;

// Funnel point for initializing documents
- initWithFileItem:(ODSFileItem *)fileItem url:(NSURL *)url error:(NSError **)outError;

// Can set this before opening a document to tell it that it is being opened for preview generation. Later we might want more control of how errors are captured for off-screen document work, but for now this just makes errors get logged instead of presented to the user. The document view controller may also opt to load less data or otherwise speed up its work by only doing what is necessary for preview generation.
@property(nonatomic) BOOL forPreviewGeneration;

@property(nonatomic,readonly) ODSFileItem *fileItem;

- (void)willEditDocumentTitle;

@property(nonatomic,readonly) UIViewController *viewControllerToPresent;
@property(nonatomic,readonly) UIViewController <OUIDocumentViewController> *documentViewController;
@property(nonatomic,readonly) BOOL editingDisabled;
@property(nonatomic) BOOL isDocumentEncrypted; // If it is encrypted, it will be unreadable.
@property(nonatomic, strong) OUIInteractionLock *applicationLock;

@property(nonatomic,readonly) UIResponder *defaultFirstResponder; // Defaults to the documentViewController, or if that view controller implements -defaultFirstResponder, returns the result of that.

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

// Must be called on a successful write after the new file is written. The passed in URL should be the argument to -writeContents:toURL:forSaveOperation:originalContentsURL:error:
- (void)didWriteToURL:(NSURL *)url;

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

// Subclass points for displaying a last updated message.
@property (nonatomic, readonly, copy) NSString *lastQueuedUpdateMessage;
/// Subclasses are responsible for overriding this method and handling the acutal displaying of the UI. Use -lastQueuedUpdateMessage in your UI, which is setup for you by OUIDocument.
- (void)displayLastQueuedUpdateMessage NS_REQUIRES_SUPER;
/// Subclasses are responsible for overriding this method and dismissing the UI they displayed via -displayLastQueuedUpdateMessage.
- (void)dismissUpdateMessage NS_REQUIRES_SUPER;
/// Subclasses can override to decide if the update message should be displayed.
- (BOOL)shouldShowUpdateMessage;

- (NSString *)alertTitleForIncomingEdit;

- (id)tearDownViewController;
- (void)recreateViewControllerWithViewState:(id)viewState;
// When we get an incoming change from iCloud, OUIDocument discards the view controller it got from -makeViewController and makes a new one. These can be subclassed to help tear down the view controller and to transition view state from the old to the new, if appropriate.
- (NSDictionary *)willRebuildViewController;
- (void)didRebuildViewController:(NSDictionary *)state;

// Support for previews
+ (OUIImageLocation *)placeholderPreviewImageForFileURL:(NSURL *)fileURL area:(OUIDocumentPreviewArea)area;
+ (OUIImageLocation *)encryptedPlaceholderPreviewImageForFileURL:(NSURL *)fileURL area:(OUIDocumentPreviewArea)area;
+ (void)writePreviewsForDocument:(OUIDocument *)document withCompletionHandler:(void (^)(void))completionHandler;

// UIDocument method that we subclass and require our subclasses to call super on (though UIDocument strongly suggests it).
- (void)saveToURL:(NSURL *)url forSaveOperation:(UIDocumentSaveOperation)saveOperation completionHandler:(void (^)(BOOL success))completionHandler NS_REQUIRES_SUPER;

@end

extern OFSaveType OFSaveTypeForUIDocumentSaveOperation(UIDocumentSaveOperation saveOperation);

// A helper function to centralize the hack for -openWithCompletionHandler: leaving the document 'open-ish' when it fails.
// Radar 10694414: If UIDocument -openWithCompletionHandler: fails, it is still a presenter
extern void OUIDocumentHandleDocumentOpenFailure(OUIDocument *document, void (^completionHandler)(BOOL success));
