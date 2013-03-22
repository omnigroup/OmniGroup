// Copyright 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class NSFileWrapper;
@class OUIDocumentPicker, OFSDocumentStoreFileItem;

@protocol OUIDocumentPickerDelegate <NSObject>

@optional

// Filter
- (NSArray *)documentPickerAvailableFilters:(OUIDocumentPicker *)picker; // array of OUIDocumentPickerFilter

// Open
- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(OFSDocumentStoreFileItem *)fileItem;
- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(OFSDocumentStoreFileItem *)fileItem;

// Export
- (NSArray *)documentPicker:(OUIDocumentPicker *)picker availableExportTypesForFileItem:(OFSDocumentStoreFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
- (void)documentPicker:(OUIDocumentPicker *)picker exportFileWrapperOfType:(NSString *)fileType forFileItem:(OFSDocumentStoreFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;
- (BOOL)documentPicker:(OUIDocumentPicker *)picker canUseEmailBodyForType:(NSString *)fileType;

// Specific export types (for backwards compatibility)
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PDFDataForFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PNGDataForFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;

- (NSData *)documentPicker:(OUIDocumentPicker *)picker copyAsImageDataForFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;

// For the export button. If implemented, a 'Send to Camera Roll' item will be in the menu. Can return nil to have a default implementation of using the document's preview, scaled to fit the current device orientation.
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker cameraRollImageForFileItem:(OFSDocumentStoreFileItem *)fileItem;

// On the iPad, it won't let you show the print panel form a sheet, so we go from the action sheet to another popover
- (void)documentPicker:(OUIDocumentPicker *)picker printFileItem:(OFSDocumentStoreFileItem *)fileItem fromButton:(UIBarButtonItem *)aButton;

// Title of the print button in the action menu
- (NSString *)documentPicker:(OUIDocumentPicker *)picker printButtonTitleForFileItem:(OFSDocumentStoreFileItem *)fileItem;

// Hook for custom export options
- (void)documentPicker:(OUIDocumentPicker *)picker addExportActions:(void (^)(NSString *title, void (^action)(void)))addAction;

- (UIImage *)documentPicker:(OUIDocumentPicker *)picker iconForUTI:(CFStringRef)fileUTI;        // used by the export file browser
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker exportIconForUTI:(CFStringRef)fileUTI;  // used by the large export options buttons
- (NSString *)documentPicker:(OUIDocumentPicker *)picker labelForUTI:(CFStringRef)fileUTI;

- (void)documentPicker:(OUIDocumentPicker *)picker makeToolbarItems:(NSMutableArray *)toolbarItems;
- (NSString *)documentPicker:(OUIDocumentPicker *)picker toolbarPromptForRenamingFileItem:(OFSDocumentStoreFileItem *)fileItem;

- (NSString *)documentPickerMainToolbarTitle:(OUIDocumentPicker *)picker;

// The file items are provided in case the receiver would return a different format based on the selected file types.
- (NSString *)documentPickerMainToolbarSelectionFormatForFileItems:(NSSet *)fileItems;

// Only called if there are 2 or more items being duplicated. The return value should be a format string taking one %ld argument. The file items are provided in case the receiver would return a different title based on the file types.
- (NSString *)documentPickerAlertTitleFormatForDuplicatingFileItems:(NSSet *)fileItems;

@end
