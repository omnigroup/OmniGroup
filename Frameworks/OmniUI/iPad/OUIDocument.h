// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIDocument.h>

#import <OmniFoundation/OFSaveType.h>

@class OUIDocumentStoreFileItem, OUIDocumentViewController, OUIDocumentPreview;

@protocol OUIDocumentViewController;

@interface OUIDocument : UIDocument

+ (BOOL)shouldShowAutosaveIndicator;

- initWithExistingFileItem:(OUIDocumentStoreFileItem *)fileItem error:(NSError **)outError;
- initEmptyDocumentToBeSavedToURL:(NSURL *)url error:(NSError **)outError;

@property(readonly, nonatomic) OUIDocumentStoreFileItem *fileItem;

@property(readonly) UIViewController <OUIDocumentViewController> *viewController;

- (BOOL)saveAsNewDocumentToURL:(NSURL *)url error:(NSError **)outError;

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
+ (CGSize)previewSizeForTargetSize:(CGSize)targetSize aspectRatio:(CGFloat)aspectRatio;
+ (NSURL *)fileURLForPreviewOfFileItem:(OUIDocumentStoreFileItem *)fileItem withLandscape:(BOOL)landscape;
+ (OUIDocumentPreview *)loadPreviewForFileItem:(OUIDocumentStoreFileItem *)fileItem withLandscape:(BOOL)landscape error:(NSError **)outError;
+ (UIImage *)placeholderPreviewImageForFileItem:(OUIDocumentStoreFileItem *)fileItem landscape:(BOOL)landscape;
+ (BOOL)writePreviewsForDocument:(OUIDocument *)document error:(NSError **)outError;

// Camera roll
+ (UIImage *)cameraRollImageForFileItem:(OUIDocumentStoreFileItem *)fileItem;

@end
