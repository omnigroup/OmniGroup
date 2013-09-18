// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniUIDocument/OUIDocumentPickerDelegate.h>

@class UINavigationController;
@class ODSStore, ODSScope, ODSFileItem, ODSFolderItem, OUIDocumentPickerViewController, OUIDocumentPickerScrollView;

@interface OUIDocumentPicker : NSObject

- (instancetype)initWithDocumentStore:(ODSStore *)documentStore;

@property (retain, nonatomic) ODSStore *documentStore;
@property (weak, nonatomic) id<OUIDocumentPickerDelegate> delegate;

@property (readonly, nonatomic) UINavigationController *navigationController; // receiver is the delegate of this navigation controller

- (void)showDocuments;
- (void)navigateToFolder:(ODSFolderItem *)folderItem animated:(BOOL)animated;
- (void)navigateToContainerForItem:(ODSItem *)item animated:(BOOL)animated;
- (void)navigateToScope:(ODSScope *)scope animated:(BOOL)animated;
- (ODSScope *)localDocumentsScope;

@property (nonatomic, readonly) OUIDocumentPickerViewController *selectedScopeViewController;

@end
