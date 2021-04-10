// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@class NSFileWrapper;
@class OUIDocumentPicker, OUIDocumentPickerFilter, ODSItem, ODSFileItem, ODSScope, OFXServerAccount;

#import <OmniUI/OUIMenuOption.h>
#import <OmniUIDocument/OUIExportOptionsType.h>
#import <OmniUIDocument/OUIDocumentPickerItemView.h>
#import <OmniBase/OBUtilities.h> // OB_DEPRECATED_ATTRIBUTE

@protocol OUIDocumentPickerDelegate <NSObject>

@optional

- (BOOL)documentPickerPresentCloudSetup:(OUIDocumentPicker *)picker OB_DEPRECATED_ATTRIBUTE;

// Sample restoration
- (BOOL)documentPickerShouldOpenSampleDocuments OB_DEPRECATED_ATTRIBUTE;  // Default is YES

// Filter
- (NSArray *)documentPickerAvailableFilters:(OUIDocumentPicker *)picker OB_DEPRECATED_ATTRIBUTE; // array of OUIDocumentPickerFilter
- (NSPredicate *)documentPickerAvailableUTTypesPredicate:(OUIDocumentPicker *)picker OB_DEPRECATED_ATTRIBUTE; //expects a string of the fileType
- (BOOL)documentPickerShouldAlwaysStackFilterControls OB_DEPRECATED_ATTRIBUTE;

// Open
- (void)documentPicker:(OUIDocumentPicker *)picker openTappedFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;
- (void)documentPicker:(OUIDocumentPicker *)picker openCreatedFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;

// Duplicate
- (void)documentPicker:(OUIDocumentPicker *)picker didDuplicateFileItem:(ODSFileItem *)originalFileItem toFileItem:(ODSFileItem *)newFileItem OB_DEPRECATED_ATTRIBUTE;

// New file creation with template support. By implementing this you will get a template picker when trying to create new documents.
- (OUIDocumentPickerFilter *)documentPickerDocumentFilter:(OUIDocumentPicker *)picker OB_DEPRECATED_ATTRIBUTE;
- (OUIDocumentPickerFilter *)documentPickerTemplateDocumentFilter:(OUIDocumentPicker *)picker OB_DEPRECATED_ATTRIBUTE;

// Default documentStoreFilter's filterPredicate
- (NSPredicate *)defaultDocumentStoreFilterFilterPredicate:(OUIDocumentPicker *)picker OB_DEPRECATED_ATTRIBUTE;

// Notification that the document picker is about to appear
- (void)documentPicker:(OUIDocumentPicker *)picker viewWillAppear:(BOOL)animated OB_DEPRECATED_ATTRIBUTE;

// Your opportunity to customize the default item view before it's in its superview
- (void)documentPicker:(OUIDocumentPicker *)picker willDisplayItemView:(OUIDocumentPickerItemView *)itemView OB_DEPRECATED_ATTRIBUTE;
- (void)documentPicker:(OUIDocumentPicker *)picker willEndDisplayingItemView:(OUIDocumentPickerItemView *)itemView OB_DEPRECATED_ATTRIBUTE;

// name label for item
- (NSString *)documentPicker:(OUIDocumentPicker *)picker nameLabelForItem:(ODSItem *)item OB_DEPRECATED_ATTRIBUTE;

- (NSString *)documentPickerMainToolbarTitle:(OUIDocumentPicker *)picker OB_DEPRECATED_ATTRIBUTE;

// The items are provided in case the receiver would return a different format based on the selected file types. This is not called if any folders are selected (all the items are ODSFileItem instances).
- (NSString *)documentPickerMainToolbarSelectionFormatForFileItems:(NSSet *)fileItems OB_DEPRECATED_ATTRIBUTE;

// Only called if there are 2 or more files being duplicated (not if any items are folders). The return value should be a format string taking one %ld argument. The file items are provided in case the receiver would return a different title based on the file types.
- (NSString *)documentPickerAlertTitleFormatForDuplicatingFileItems:(NSSet *)fileItems OB_DEPRECATED_ATTRIBUTE;

- (BOOL)documentPickerWantsVisibleNavigationBarAtRoot:(OUIDocumentPicker *)picker OB_DEPRECATED_ATTRIBUTE;

// Deprecated
- (NSString *)documentPicker:(OUIDocumentPicker *)picker toolbarPromptForRenamingFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;

@end
