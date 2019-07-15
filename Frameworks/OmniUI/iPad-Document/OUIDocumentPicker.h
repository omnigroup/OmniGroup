// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIWrappingViewController.h>
#import <OmniUIDocument/OUIDocumentPickerDelegate.h>

@protocol OUIInternalTemplateDelegate;

@class UINavigationController;
@class ODSStore, ODSScope, ODSFileItem, ODSFolderItem, OUIDocumentPickerViewController, OUIDocumentPickerScrollView;

@interface OUIDocumentPicker : OUIWrappingViewController

@property (class, readonly) BOOL shouldShowExternalScope;

- (instancetype)initWithDocumentStore:(ODSStore *)documentStore;

@property (retain, nonatomic) ODSStore *documentStore;
@property (weak, nonatomic) id<OUIDocumentPickerDelegate> delegate;
@property (weak, nonatomic) id<OUIInternalTemplateDelegate> internalTemplateDelegate;

- (void)showDocuments;
- (void)navigateToFolder:(ODSFolderItem *)folderItem animated:(BOOL)animated;
- (BOOL)navigateToContainerForItem:(ODSItem *)item dismissingAnyOpenDocument:(BOOL)dismissOpenDocument animated:(BOOL)animated;
- (void)navigateToScope:(ODSScope *)scope animated:(BOOL)animated;
- (ODSScope *)localDocumentsScope;

@property(nonatomic,readonly) ODSFolderItem *currentFolder;

// Go somewhere, even if the file item can't be found.
- (void)navigateToBestEffortContainerForItem:(ODSFileItem *)fileItem;

- (void)editSettingsForAccount:(OFXServerAccount *)account;

@property (nonatomic, readonly) OUIDocumentPickerViewController *selectedScopeViewController;

- (void)enableAppMenuBarButtonItem:(BOOL)enable;

- (UINavigationController *)topLevelNavigationController;

@end
