// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIkit/UIKit.h>

@class ODSFileItem;
@class OUIDocumentPreview;
@class OUIDocumentPreviewView;

@interface OUIDocumentPreviewingViewController : UIViewController

@property (nonatomic, strong, readonly) ODSFileItem *fileItem;

- (instancetype)initWithFileItem:(ODSFileItem *)fileItem preview:(OUIDocumentPreview *)preview;

- (void)prepareForCommitWithBackgroundView:(UIView *)backgroundView;

- (UIView *)backgroundSnapshotView;
- (UIView *)previewSnapshotView;
/// In the windows coordinate system.
- (CGRect)previewRect;

@end
