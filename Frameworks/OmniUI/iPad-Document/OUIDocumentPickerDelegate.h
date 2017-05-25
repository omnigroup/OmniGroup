// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class NSFileWrapper;
@class OUIDocumentPicker, OUIDocumentPickerHomeScreenViewController, OUIDocumentPickerFilter, ODSItem, ODSFileItem, ODSScope, OFXServerAccount;

#import <OmniUI/OUIMenuOption.h>
#import <OmniUIDocument/OUIExportOptionsType.h>
#import <OmniUIDocument/OUIDocumentPickerItemView.h>
#import <OmniBase/OBUtilities.h> // OB_DEPRECATED_ATTRIBUTE

@protocol OUIDocumentPickerDelegate <NSObject>

@optional

- (OUIDocumentPickerHomeScreenViewController *)documentPickerHomeViewController:(OUIDocumentPicker *)picker;
- (BOOL)documentPickerPresentCloudSetup:(OUIDocumentPicker *)picker;

// Sample restoration
- (BOOL)documentPickerShouldOpenSampleDocuments;  // Default is YES

// Filter
- (NSArray *)documentPickerAvailableFilters:(OUIDocumentPicker *)picker; // array of OUIDocumentPickerFilter
- (BOOL)documentPickerShouldOpenButNotDisplayUTType:(NSString *)fileType;
- (NSPredicate *)documentPickerAvailableUTTypesPredicate:(OUIDocumentPicker *)picker; //expects a string of the fileType
- (BOOL)documentPickerShouldAlwaysStackFilterControls;

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

// Notification that the document picker is about to appear
- (void)documentPicker:(OUIDocumentPicker *)picker viewWillAppear:(BOOL)animated;

// Your opportunity to customize the default item view before it's in its superview
- (void)documentPicker:(OUIDocumentPicker *)picker willDisplayItemView:(OUIDocumentPickerItemView *)itemView;
- (void)documentPicker:(OUIDocumentPicker *)picker willEndDisplayingItemView:(OUIDocumentPickerItemView *)itemView;

// name label for item
- (NSString *)documentPicker:(OUIDocumentPicker *)picker nameLabelForItem:(ODSItem *)item;

// Conversion
- (void)documentPicker:(OUIDocumentPicker *)picker saveNewFileIfAppropriateFromFile:(NSURL *)fileURL completionHandler:(void (^)(BOOL success, ODSFileItem *savedItem, ODSScope *currentScope))completionBlock;

- (NSString *)documentPicker:(OUIDocumentPicker *)picker toolbarPromptForRenamingItem:(ODSItem *)item;

- (NSString *)documentPickerMainToolbarTitle:(OUIDocumentPicker *)picker;

// The items are provided in case the receiver would return a different format based on the selected file types. This is not called if any folders are selected (all the items are ODSFileItem instances).
- (NSString *)documentPickerMainToolbarSelectionFormatForFileItems:(NSSet *)fileItems;

// Only called if there are 2 or more files being duplicated (not if any items are folders). The return value should be a format string taking one %ld argument. The file items are provided in case the receiver would return a different title based on the file types.
- (NSString *)documentPickerAlertTitleFormatForDuplicatingFileItems:(NSSet *)fileItems;

- (BOOL)documentPickerWantsVisibleNavigationBarAtRoot:(OUIDocumentPicker *)picker;

// Deprecated
- (NSString *)documentPicker:(OUIDocumentPicker *)picker toolbarPromptForRenamingFileItem:(ODSFileItem *)fileItem OB_DEPRECATED_ATTRIBUTE;

@end
