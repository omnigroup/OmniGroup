// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIDocument.h>

#import <OmniFoundation/OFSaveType.h>

@class OFSDocumentStoreFileItem, OUIDocumentViewController, OUIDocumentPreview;

@protocol OUIDocumentViewController;

@interface OUIDocument : UIDocument

+ (BOOL)shouldShowAutosaveIndicator;

- initWithExistingFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;
- initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;
- initWithFileItem:(OFSDocumentStoreFileItem *)fileItem url:(NSURL *)url error:(NSError **)outError;

// Can set this before opening a document to tell it that it is being opened for preview generation. Later we might want more control of how errors are captured for off-screen document work, but for now this just makes errors get logged instead of presented to the user. The document view controller may also opt to load less data or otherwise speed up its work by only doing what is necessary for preview generation.
@property(nonatomic) BOOL forPreviewGeneration;

@property(nonatomic,readonly) OFSDocumentStoreFileItem *fileItem;

@property(nonatomic,readonly) UIViewController <OUIDocumentViewController> *viewController;
@property(nonatomic,readonly) BOOL editingDisabled;

- (void)finishUndoGroup;
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;

// Called after an incoming rename, but before -enableEditing. Subclasses can refresh their references to child file wrappers. Called on a background queue via -performAsynchronousFileAccessUsingBlock:.
- (void)reacquireSubItemsAfterMovingFromURL:(NSURL *)oldURL completionHandler:(void (^)(void))completionHandler;

- (void)viewStateChanged; // Marks the document as dirty w/o logging an undo. If the app is backgrounded or the document closed it will be saved, but it won't be saved if the editor state change is the only change.
- (void)beganUncommittedDataChange; // Can be used when the user has started a change (like editing a value in a text field) to request that the value be autosaved eventually. This requires that the document subclass knows how to save the partial edits and that the act of doing so makes a real undoable change. Calling this for editor state changes can result in taps to Undo resulting in data loss in the case that you make UIDocument think it is back to its last saved state.
- (void)willClose;

// Subclass responsibility

/*
 self.fileItem and self.undoManager will be set appropriately when this is called. If fileItem is nil, this is a new document, but the UIDocument's fileURL will be set no matter what.
 */
- (UIViewController <OUIDocumentViewController> *)makeViewController;

// Optional subclass methods
- (void)willFinishUndoGroup;
- (BOOL)shouldUndo;
- (BOOL)shouldRedo;
- (void)didUndo;
- (void)didRedo;
- (UIView *)viewToMakeFirstResponderWhenInspectorCloses;

- (NSString *)alertTitleForIncomingEdit;

// When we get an incoming change from iCloud, OUIDocument discards the view controller it got from -makeViewController and makes a new one. These can be subclassed to help tear down the view controller and to transition view state from the old to the new, if appropriate.
- (id)willRebuildViewController;
- (void)didRebuildViewController:(id)state;

// Support for a bar button item to add to your document view controller to show OmniPresence progress
- (UIBarButtonItem *)omniPresenceBarButtonItem;

// Support for previews
+ (NSString *)placeholderPreviewImageNameForFileURL:(NSURL *)fileURL landscape:(BOOL)landscape;
+ (void)writePreviewsForDocument:(OUIDocument *)document withCompletionHandler:(void (^)(void))completionHandler;

@end

// A helper function to centralize the hack for -openWithCompletionHandler: leaving the document 'open-ish' when it fails.
// Radar 10694414: If UIDocument -openWithCompletionHandler: fails, it is still a presenter
extern void OUIDocumentHandleDocumentOpenFailure(OUIDocument *document, void (^completionHandler)(BOOL success));
