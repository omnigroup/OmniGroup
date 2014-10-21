// Copyright 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class NSFileWrapper;
@class OUIDocumentPicker, OUIDocumentPickerHomeScreenViewController, OUIDocumentPickerFilter, ODSItem, ODSFileItem, OFXServerAccount;

#import <OmniUIDocument/OUIExportOptionsType.h>
#import <OmniUIDocument/OUIDocumentPickerItemView.h>

@protocol OUIDocumentPickerDelegate <NSObject>

@optional

- (OUIDocumentPickerHomeScreenViewController *)documentPickerHomeViewController:(OUIDocumentPicker *)picker;
- (BOOL)documentPickerPresentCloudSetup:(OUIDocumentPicker *)picker;

// Sample restoration
- (BOOL)documentPickerShouldOpenSampleDocuments;  // Default is YES

// Filter
- (NSArray *)documentPickerAvailableFilters:(OUIDocumentPicker *)picker; // array of OUIDocumentPickerFilter

// Open
- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(ODSFileItem *)fileItem;
- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(ODSFileItem *)fileItem fileItemToRevealFrom:(ODSFileItem *)fileItemToRevealFrom;
- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(ODSFileItem *)fileItem;

// Duplicate
- (void)documentPicker:(OUIDocumentPicker *)picker didDuplicateFileItem:(ODSFileItem *)originalFileItem toFileItem:(ODSFileItem *)newFileItem;

// New file creation with template support. By implementing this you will get a template picker when trying to create new documents.
- (OUIDocumentPickerFilter *)documentPickerDocumentFilter:(OUIDocumentPicker *)picker;
- (OUIDocumentPickerFilter *)documentPickerTemplateDocumentFilter:(OUIDocumentPicker *)picker;

// Default documentStoreFilter's filterPredicate
- (NSPredicate *)defaultDocumentStoreFilterFilterPredicate:(OUIDocumentPicker *)picker;

// Your opportunity to customize the default item view before it's in its superview
- (void)documentPicker:(OUIDocumentPicker *)picker willDisplayItemView:(OUIDocumentPickerItemView *)itemView;
- (void)documentPicker:(OUIDocumentPicker *)picker willEndDisplayingItemView:(OUIDocumentPickerItemView *)itemView;

// name label for item
- (NSString *)documentPicker:(OUIDocumentPicker *)picker nameLabelForItem:(ODSItem *)item;

// Export
- (NSArray *)documentPicker:(OUIDocumentPicker *)picker availableExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
- (void)documentPicker:(OUIDocumentPicker *)picker exportFileWrapperOfType:(NSString *)fileType forFileItem:(ODSFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;
- (BOOL)documentPicker:(OUIDocumentPicker *)picker canUseEmailBodyForType:(NSString *)fileType;
- (NSArray *)documentPicker:(OUIDocumentPicker *)picker availableInAppPurchaseExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType; // these would be the export types that have not been purchased yet so that we can offer the user access to the store

// Specific export types (for backwards compatibility)
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PDFDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;
- (NSData *)documentPicker:(OUIDocumentPicker *)picker PNGDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;

- (NSData *)documentPicker:(OUIDocumentPicker *)picker copyAsImageDataForFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;

// For the export button. If implemented, a 'Send to Camera Roll' item will be in the menu. Can return nil to have a default implementation of using the document's preview, scaled to fit the current device orientation.
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker cameraRollImageForFileItem:(ODSFileItem *)fileItem;

// On the iPad, it won't let you show the print panel form a sheet, so we go from the action sheet to another popover
- (void)documentPicker:(OUIDocumentPicker *)picker printFileItem:(ODSFileItem *)fileItem fromButton:(UIBarButtonItem *)aButton;

// Title of the print button in the action menu
- (NSString *)documentPicker:(OUIDocumentPicker *)picker printButtonTitleForFileItem:(ODSFileItem *)fileItem;

// Hook for custom export options
- (void)documentPicker:(OUIDocumentPicker *)picker addExportActions:(void (^)(NSString *title, UIImage *image, void (^action)(void)))addAction;

- (UIImage *)documentPicker:(OUIDocumentPicker *)picker iconForUTI:(CFStringRef)fileUTI;        // used by the export file browser
- (UIImage *)documentPicker:(OUIDocumentPicker *)picker exportIconForUTI:(CFStringRef)fileUTI;  // used by the large export options buttons
- (NSString *)documentPicker:(OUIDocumentPicker *)picker labelForUTI:(CFStringRef)fileUTI;

- (NSString *)documentPicker:(OUIDocumentPicker *)picker purchaseDescriptionForExportType:(CFStringRef)fileUTI;
- (void)documentPicker:(OUIDocumentPicker *)picker purchaseExportType:(CFStringRef)fileUTI navigationController:(UINavigationController *)navigationController;

- (NSString *)documentPicker:(OUIDocumentPicker *)picker toolbarPromptForRenamingItem:(ODSItem *)item;

- (NSString *)documentPickerMainToolbarTitle:(OUIDocumentPicker *)picker;

// The items are provided in case the receiver would return a different format based on the selected file types. This is not called if any folders are selected (all the items are ODSFileItem instances).
- (NSString *)documentPickerMainToolbarSelectionFormatForFileItems:(NSSet *)fileItems;

// Only called if there are 2 or more files being duplicated (not if any items are folders). The return value should be a format string taking one %ld argument. The file items are provided in case the receiver would return a different title based on the file types.
- (NSString *)documentPickerAlertTitleFormatForDuplicatingFileItems:(NSSet *)fileItems;


// Deprecated
- (NSString *)documentPicker:(OUIDocumentPicker *)picker toolbarPromptForRenamingFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;

@end
