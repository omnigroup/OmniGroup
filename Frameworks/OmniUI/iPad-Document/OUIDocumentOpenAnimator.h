// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewControllerTransitioning.h>

@class OUIDocumentPicker;
@class ODSFileItem;

@interface OUIDocumentOpenAnimator : NSObject <UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning>

+ (instancetype)sharedAnimator;

@property (nonatomic) OUIDocumentPicker *documentPicker;
@property (nonatomic) ODSFileItem *fileItem;
@property (nonatomic) ODSFileItem *actualFileItem;

@property (nonatomic, assign) BOOL isOpeningFromPeek;
@property (nonatomic, strong) UIView *backgroundSnapshotView;
@property (nonatomic, strong) UIView *previewSnapshotView;
@property (nonatomic, assign) CGRect previewRect;

@end
