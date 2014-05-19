// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UICollectionViewController.h>

@class ALAsset;
@class ALAssetsGroup;
@protocol OUIImagePickerAssetsViewControllerDelegate;

@interface OUIImagePickerAssetsViewController : UICollectionViewController

+ (instancetype)imagePickerAssetViewController;

@property (nonatomic, weak) id<OUIImagePickerAssetsViewControllerDelegate> delegate;
@property (nonatomic, strong) NSURL *assetsGroupURL;

@end

@protocol OUIImagePickerAssetsViewControllerDelegate <NSObject>

@optional
- (void)imagePickerAssetsViewController:(OUIImagePickerAssetsViewController *)controller didSelectAsset:(ALAsset *)asset;

@end
