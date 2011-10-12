// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class NSFileWrapper;
@class OUIDocumentPicker, OUIDocumentStoreFileItem;

@protocol OUIDocumentPickerDelegate <NSObject>

@optional

// Export
- (NSArray *)documentPicker:(OUIDocumentPicker *)picker availableExportTypesForFileItem:(OUIDocumentStoreFileItem *)fileItem;
- (void)documentPicker:(OUIDocumentPicker *)picker exportFileWrapperOfType:(NSString *)fileType forFileItem:(OUIDocumentStoreFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;
- (BOOL)documentPicker:(OUIDocumentPicker *)picker canUseEmailBodyForType:(NSString *)fileType;
- (BOOL)documentPicker:(OUIDocumentPicker *)picker shouldRevealDocumentAfterExportingType:(NSString *)fileType;

// Specific export types (for backwards compatibility)
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PDFDataForFileItem:(OUIDocumentStoreFileItem *)fileItem error:(NSError **)outError;
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PNGDataForFileItem:(OUIDocumentStoreFileItem *)fileItem error:(NSError **)outError;

// For the export button. If implemented, a 'Send to Camera Roll' item will be in the menu. Can return nil to have a default implementation of using the document's preview, scaled to fit the current device orientation.
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker cameraRollImageForFileItem:(OUIDocumentStoreFileItem *)fileItem;

// On the iPad, it won't let you show the print panel form a sheet, so we go from the action sheet to another popover
- (void)documentPicker:(OUIDocumentPicker *)picker printFileItem:(OUIDocumentStoreFileItem *)fileItem fromButton:(UIBarButtonItem *)aButton;

// Title of the print button in the action menu
- (NSString *)documentPicker:(OUIDocumentPicker *)picker printButtonTitleForFileItem:(OUIDocumentStoreFileItem *)fileItem;

// Hook for custom export options
- (void)documentPicker:(OUIDocumentPicker *)picker addExportActions:(void (^)(NSString *title, void (^action)(void)))addAction;

- (UIImage *)documentPicker:(OUIDocumentPicker *)picker iconForUTI:(CFStringRef)fileUTI;        // used by the export file browser
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker exportIconForUTI:(CFStringRef)fileUTI;  // used by the large export options buttons
- (NSString *)documentPicker:(OUIDocumentPicker *)picker labelForUTI:(CFStringRef)fileUTI;

// The number of documents wide and height the picker should display for this orientation. Width must be integral and at least one, height must be at least one, but can be non-integral (3.5 would let 1/2 a row peek out from the bottom of the scroll view).
- (CGSize)documentPicker:(OUIDocumentPicker *)picker gridSizeForOrientation:(UIInterfaceOrientation)orientation;

- (void)documentPicker:(OUIDocumentPicker *)picker makeToolbarItems:(NSMutableArray *)toolbarItems;
- (NSString *)documentPicker:(OUIDocumentPicker *)picker toolbarPromptForRenamingFileItem:(OUIDocumentStoreFileItem *)fileItem;

- (NSString *)documentPickerMainToolbarTitle:(OUIDocumentPicker *)picker;

@end
