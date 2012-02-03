// Copyright 2010-2012 The Omni Group. All rights reserved.
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

// Can set this before opening a document to tell it that it is being opened for preview generation. Later we might want more control of how errors are captured for off-screen document work, but for now this just makes errors get logged instead of presented to the user. The document view controller may also opt to load less data or otherwise speed up its work by only doing what is necessary for preview generation.
@property(nonatomic) BOOL forPreviewGeneration;

@property(readonly, nonatomic) OFSDocumentStoreFileItem *fileItem;

@property(readonly) UIViewController <OUIDocumentViewController> *viewController;

- (void)finishUndoGroup;
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;

- (void)scheduleAutosave; // Will happen automatically for undoable changes, but for view stat changes that you want to be saved, you can call this.
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

// Support for previews
+ (NSString *)placeholderPreviewImageNameForFileURL:(NSURL *)fileURL landscape:(BOOL)landscape;
+ (void)writePreviewsForDocument:(OUIDocument *)document withCompletionHandler:(void (^)(void))completionHandler;

@end

// A helper function to centralize the hack for -openWithCompletionHandler: leaving the document 'open-ish' when it fails.
// Radar 10694414: If UIDocument -openWithCompletionHandler: fails, it is still a presenter
extern void OUIDocumentHandleDocumentOpenFailure(OUIDocument *document, void (^completionHandler)(BOOL success));
