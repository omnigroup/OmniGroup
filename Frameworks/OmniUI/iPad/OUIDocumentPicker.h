// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIViewController.h>

#import <OmniUI/OUIDocumentPickerScrollView.h>
#import <OmniUI/OUIReplaceDocumentAlert.h>

@class NSFileWrapper;
@class OFSetBinding;
@class OUIDocumentStore, OUIDocumentStoreItem, OUIDocumentStoreFileItem, OUIDocumentPickerScrollView, OUIDocumentRenameViewController;

@protocol OUIDocumentPickerDelegate;

@interface OUIDocumentPicker : OUIViewController <UIGestureRecognizerDelegate, OUIDocumentPickerScrollViewDelegate, UIDocumentInteractionControllerDelegate, OUIReplaceDocumentAlertDelegate>

@property(nonatomic,retain) OUIDocumentStore *documentStore;
@property(assign, nonatomic) IBOutlet id <OUIDocumentPickerDelegate> delegate;

@property(retain) IBOutlet UIToolbar *toolbar;
@property(retain) IBOutlet OUIDocumentPickerScrollView *mainScrollView;
@property(retain) IBOutlet OUIDocumentPickerScrollView *groupScrollView;

@property(nonatomic,readonly) OUIDocumentPickerScrollView *activeScrollView;

@property(retain) id fileItemTappedTarget;
@property(assign) SEL fileItemTappedAction;

@property(nonatomic, assign) CGSize filterViewContentSize;

- (CGSize)gridSizeForOrientation:(UIInterfaceOrientation)orientation;

- (void)rescanDocuments;
- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL;
- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL animated:(BOOL)animated;

@property(readonly,nonatomic) NSSet *selectedFileItems;
- (void)clearSelection;
@property(readonly,nonatomic) OUIDocumentStoreFileItem *singleSelectedFileItem;
- (BOOL)canEditFileItem:(OUIDocumentStoreFileItem *)fileItem;

- (void)addDocumentFromURL:(NSURL *)url;
- (void)exportedDocumentToURL:(NSURL *)url;
    // For exports to iTunes, it's possible that we'll want to show the result of the export in our document picker, e.g., Outliner can export to OPML or plain text, but can also work with those document types. This method is called after a successful export to give the picker a chance to update if necessary.

- (BOOL)isExportThreadSafe;  // Graffle has a subclass that returns NO, default is YES

- (NSArray *)availableExportTypesForFileItem:(OUIDocumentStoreFileItem *)fileItem;
- (NSArray *)availableImageExportTypesForFileItem:(OUIDocumentStoreFileItem *)fileItem;
- (NSArray *)availableDocumentInteractionExportTypesForFileItem:(OUIDocumentStoreFileItem *)fileItem;
- (void)exportFileWrapperOfType:(NSString *)exportType forFileItem:(OUIDocumentStoreFileItem *)fileItem withCompletionHandler:(void (^)(NSFileWrapper *fileWrapper, NSError *error))completionHandler;

- (UIImage *)iconForUTI:(NSString *)fileUTI;
- (UIImage *)exportIconForUTI:(NSString *)fileUTI;
- (NSString *)exportLabelForUTI:(NSString *)fileUTI;

- (void)scrollToTopAnimated:(BOOL)animated;
- (void)scrollItemToVisible:(OUIDocumentStoreItem *)item animated:(BOOL)animated;

- (BOOL)okayToOpenMenu;

- (IBAction)newDocument:(id)sender;
- (IBAction)duplicateDocument:(id)sender;
- (IBAction)deleteDocument:(id)sender;
- (IBAction)export:(id)sender;
- (IBAction)emailDocument:(id)sender;
- (void)emailExportType:(NSString *)exportType;
- (void)sendEmailWithFileWrapper:(NSFileWrapper *)fileWrapper forExportType:(NSString *)exportType;
- (IBAction)filterAction:(UIView *)sender;

+ (OFPreference *)sortPreference;
- (void)updateSort;

- (NSString *)mainToolbarTitle;
- (void)updateTitle;

@end
