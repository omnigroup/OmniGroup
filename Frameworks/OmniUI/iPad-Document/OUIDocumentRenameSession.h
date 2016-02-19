// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OUIDocumentPickerViewController, ODSItem, OUIDocumentPickerItemView;

// Helper for rename operations in OUIDocumentPickerViewController
@interface OUIDocumentRenameSession : NSObject

- initWithDocumentPicker:(OUIDocumentPickerViewController *)picker itemView:(OUIDocumentPickerItemView *)itemView;

@property(nonatomic,readonly) OUIDocumentPickerItemView *itemView;
@property(nonatomic) CGRect origMetadataFrame;
@property(nonatomic) CGRect origItemFrame;
@property(nonatomic) UIColor *origBackgroundColor;

- (void)endRenaming;
- (void)cancelRenaming;
- (void)layoutDimmingView;

@end


// Internal callbacks that we expect OUIDocumentPicker to have
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
@interface OUIDocumentPickerViewController (/*OUIDocumentRenameSession*/)
- (void)_didPerformRenameToFileURL:(NSURL *)destinationURL;
@end
