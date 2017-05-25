// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OMniUIDocument/OUIDocumentPickerScrollView.h>

@interface OUIDocumentPickerViewController (/*Internal*/) <OUIDocumentPickerScrollViewDelegate>

- (void)_applicationWillOpenDocument;

- (void)_beginIgnoringDocumentsDirectoryUpdates;
- (void)_endIgnoringDocumentsDirectoryUpdates;

- (void)_updateToolbarItemsForTraitCollection:(UITraitCollection *)traitCollection animated:(BOOL)animated;

- (ODSFileItem *)_preferredVisibleItemFromSet:(NSSet *)fileItemsNeedingPreviewUpdate;

- (void)_renameItem:(ODSItem *)item baseName:(NSString *)baseName completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

@end
