// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSStore.h>
#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUIDocument/OUIReplaceDocumentAlert.h>
#import <OmniUIDocument/OUIExportOptionsType.h>

@class NSFileWrapper;
@class ODSScope, ODSItem, ODSFileItem, ODSFolderItem, OUIDocumentPicker, OUIDocumentPickerScrollView, OUIDocumentPickerFilter, ODSFilter, OFXServerAccount;
@class OUIEmptyOverlayView;

@protocol OUIDocumentPickerDelegate;

@interface OUIDocumentPickerViewController : UIViewController <UIGestureRecognizerDelegate, OUIDocumentPickerScrollViewDelegate, UIDocumentInteractionControllerDelegate, OUIReplaceDocumentAlertDelegate>

- (instancetype)initWithDocumentPicker:(OUIDocumentPicker *)picker scope:(ODSScope *)scope;
- (instancetype)initWithDocumentPicker:(OUIDocumentPicker *)picker folderItem:(ODSFolderItem *)folderItem;

- (ODSFilter *)newDocumentStoreFilter;

@property (nonatomic, readonly) OUIDocumentPicker *documentPicker;
@property (nonatomic, retain) IBOutlet UIImageView *backgroundView;
@property(nonatomic,retain) IBOutlet OUIDocumentPickerScrollView *mainScrollView;

@property(nonatomic,readonly) ODSStore *documentStore;

@property(nonatomic,readonly) ODSFilter *documentStoreFilter;
@property(nonatomic,readonly) ODSScope *selectedScope;
@property(nonatomic,readonly) ODSFolderItem *folderItem;
@property(nonatomic,readonly) NSSet *filteredItems;

@property(nonatomic,readonly) BOOL canAddDocuments;
@property(nonatomic,assign) BOOL isReadOnly;

@property(nonatomic,retain) IBOutlet UIToolbar *toolbar;

- (OUIEmptyOverlayView *)newEmptyOverlayView;

- (void)rescanDocuments;
- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL;
- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler;

@property(nonatomic,readonly) NSSet *selectedItems;
@property(nonatomic,readonly) NSSet *selectedFolders;

- (void)clearSelection:(BOOL)shouldEndEditing;
@property(nonatomic,readonly) ODSFileItem *singleSelectedFileItem;

- (void)addDocumentFromURL:(NSURL *)url;
- (void)addSampleDocumentFromURL:(NSURL *)url;
- (void)exportedDocumentToURL:(NSURL *)url;
    // For exports to iTunes, it's possible that we'll want to show the result of the export in our document picker, e.g., Outliner can export to OPML or plain text, but can also work with those document types. This method is called after a successful export to give the picker a chance to update if necessary.

- (NSArray *)availableFilters;
- (NSArray *)availableExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
- (NSArray *)availableImageExportTypesForFileItem:(ODSFileItem *)fileItem;
- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(ODSFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;

- (UIImage *)iconForUTI:(NSString *)fileUTI;
- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
- (NSString *)exportLabelForUTI:(NSString *)fileUTI;

- (NSArray *)availableInAppPurchaseExportTypesForFileItem:(ODSFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
- (NSString *)purchaseDescriptionForExportType:(NSString *)fileUTI;
- (void)purchaseExportType:(NSString *)fileUTI navigationController:(UINavigationController *)navigationController;

- (void)scrollToTopAnimated:(BOOL)animated;
- (void)scrollItemToVisible:(ODSItem *)item animated:(BOOL)animated;
- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated completion:(void (^)(void))completion;

- (IBAction)newDocument:(id)sender;
- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem documentType:(ODSDocumentType)type;
- (void)newDocumentWithTemplateFileItem:(ODSFileItem *)templateFileItem;
- (IBAction)duplicateDocument:(id)sender;
- (IBAction)deleteDocument:(id)sender;
- (IBAction)export:(id)sender;
- (IBAction)emailDocument:(id)sender;
- (IBAction)sortSegmentChanged:(id)sender;
- (void)emailExportType:(NSString *)exportType;
- (void)sendEmailWithFileWrapper:(NSFileWrapper *)fileWrapper forExportType:(NSString *)exportType;

+ (OFPreference *)scopePreference;
+ (OFPreference *)folderPreference;
+ (OFPreference *)filterPreference; // value is the identifier of an OUIDocumentPickerFilter returned by the delegate's -documentPickerAvailableFilters:
+ (OUIDocumentPickerFilter *)documentFilterForPicker:(OUIDocumentPicker *)picker scope:(ODSScope *)scope;
+ (OUIDocumentPickerFilter *)selectedFilterForPicker:(OUIDocumentPicker *)picker;
+ (OFPreference *)sortPreference;
+ (NSArray *)sortDescriptors;
- (BOOL)supportsUpdatingSorting;

- (void)ensureSelectedFilterMatchesFileURL:(NSURL *)fileURL;
- (void)ensureSelectedFilterMatchesFileItem:(ODSFileItem *)fileItem;

- (void)selectedFilterChanged;
- (void)selectedSortChanged;

- (void)addDocumentStoreInitializationAction:(void (^)(OUIDocumentPickerViewController *blockSelf))action; // Note: performed immediately once the document store is initialized

- (void)updateTitle;

- (NSString *)nameLabelForItem:(ODSItem *)item;

@property(nonatomic,readonly) NSError *selectedScopeError;

@end
