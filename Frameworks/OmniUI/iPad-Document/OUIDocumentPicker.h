// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIViewController.h>

#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUIDocument/OUIReplaceDocumentAlert.h>
#import <OmniUIDocument/OUIExportOptionsType.h>

@class NSFileWrapper;
@class OFSDocumentStore, OFSDocumentStoreScope, OFSDocumentStoreItem, OFSDocumentStoreFileItem, OUIDocumentPickerScrollView, OFSDocumentStoreFilter, OFXServerAccount;

@protocol OUIDocumentPickerDelegate;

@interface OUIDocumentPicker : OUIViewController <UIGestureRecognizerDelegate, OUIDocumentPickerScrollViewDelegate, UIDocumentInteractionControllerDelegate, OUIReplaceDocumentAlertDelegate>

@property(nonatomic,retain) OFSDocumentStore *documentStore;
@property(nonatomic,weak) IBOutlet id <OUIDocumentPickerDelegate> delegate;

@property(nonatomic,readonly) OFSDocumentStoreFilter *documentStoreFilter;
@property(nonatomic,retain) OFSDocumentStoreScope *selectedScope;

@property(nonatomic,retain) IBOutlet UIToolbar *toolbar;
@property(nonatomic, strong) IBOutlet UIToolbar *bottomToolbar;
@property(nonatomic,retain) IBOutlet OUIDocumentPickerScrollView *mainScrollView;
@property(nonatomic,retain) IBOutlet OUIDocumentPickerScrollView *groupScrollView;

@property (strong, nonatomic) IBOutlet UIView *trashControls;
@property (strong, nonatomic) IBOutlet UIButton *emptyTrashButton;
- (IBAction)emptyTrash:(id)sender;

@property (strong, nonatomic) IBOutlet UIView *emptyPickerView;
@property (strong, nonatomic) IBOutlet UIView *emptyPickerViewMoveView;
@property (strong, nonatomic) IBOutlet UIButton *emptyPickerViewMoveButton;
- (IBAction)moveAllDocumentsToCloudButtonTapped:(id)sender;

@property(nonatomic,readonly) OUIDocumentPickerScrollView *activeScrollView;

- (void)rescanDocuments;
- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL;
- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL animated:(BOOL)animated completionHandler:(void (^)(void))completionHandler;

@property(nonatomic,readonly) NSSet *selectedFileItems;
- (void)clearSelection:(BOOL)shouldEndEditing;
@property(nonatomic,readonly) OFSDocumentStoreFileItem *singleSelectedFileItem;

- (void)addDocumentFromURL:(NSURL *)url;
- (void)addSampleDocumentFromURL:(NSURL *)url;
- (void)exportedDocumentToURL:(NSURL *)url;
    // For exports to iTunes, it's possible that we'll want to show the result of the export in our document picker, e.g., Outliner can export to OPML or plain text, but can also work with those document types. This method is called after a successful export to give the picker a chance to update if necessary.

- (NSArray *)availableExportTypesForFileItem:(OFSDocumentStoreFileItem *)fileItem serverAccount:(OFXServerAccount *)serverAccount exportOptionsType:(OUIExportOptionsType)exportOptionsType;
- (NSArray *)availableImageExportTypesForFileItem:(OFSDocumentStoreFileItem *)fileItem;
- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(OFSDocumentStoreFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;

- (UIImage *)iconForUTI:(NSString *)fileUTI;
- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
- (NSString *)exportLabelForUTI:(NSString *)fileUTI;

- (void)scrollToTopAnimated:(BOOL)animated;
- (void)scrollItemToVisible:(OFSDocumentStoreItem *)item animated:(BOOL)animated;
- (void)scrollItemsToVisible:(id <NSFastEnumeration>)items animated:(BOOL)animated;

- (IBAction)newDocument:(id)sender;
- (IBAction)duplicateDocument:(id)sender;
- (IBAction)deleteDocument:(id)sender;
- (IBAction)export:(id)sender;
- (IBAction)emailDocument:(id)sender;
- (void)emailExportType:(NSString *)exportType;
- (void)sendEmailWithFileWrapper:(NSFileWrapper *)fileWrapper forExportType:(NSString *)exportType;

+ (OFPreference *)filterPreference; // value is the identifier of an OUIDocumentPickerFilter returned by the delegate's -documentPickerAvailableFilters:
+ (OFPreference *)sortPreference;

- (void)ensureSelectedFilterMatchesFileURL:(NSURL *)fileURL;
- (void)ensureSelectedFilterMatchesFileItem:(OFSDocumentStoreFileItem *)fileItem;

- (void)selectedFilterChanged;
- (void)selectedSortChanged;

- (void)addDocumentStoreInitializationAction:(void (^)(OUIDocumentPicker *blockSelf))action; // Note: performed immediately once the document store is initialized

- (NSString *)mainToolbarTitle;
- (void)updateTitle;

@property(nonatomic,readonly) NSError *selectedScopeError;

@end
