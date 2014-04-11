// Copyright 2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIImagePickerAssetsViewController.h>

#import <AssetsLibrary/AssetsLibrary.h>

#import <OmniUI/OUIImagePickerAssetCell.h>

RCS_ID("$Id$")

@interface OUIImagePickerAssetsViewController ()

@property (nonatomic, strong) NSMutableArray *assets;

@end

@implementation OUIImagePickerAssetsViewController

+ (instancetype)imagePickerAssetViewController;
{
    UIStoryboard *imagePickerResources = [UIStoryboard storyboardWithName:@"OUIImagePickerViewControllers" bundle:nil];
    UIViewController *newController = (UIViewController *)[imagePickerResources instantiateViewControllerWithIdentifier:@"OUIImagePickerAssetsViewController"];
    
    OBASSERT([newController isKindOfClass:[OUIImagePickerAssetsViewController class]]);
    
    return (OUIImagePickerAssetsViewController *)newController;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.title = [self.assetsGroup valueForProperty:ALAssetsGroupPropertyName];
    
    if (!self.assets) {
        _assets = [[NSMutableArray alloc] init];
    } else {
        [self.assets removeAllObjects];
    }
    
    ALAssetsGroupEnumerationResultsBlock assetsEnumerationBlock = ^(ALAsset *result, NSUInteger index, BOOL *stop) {
        
        if (result) {
            [self.assets addObject:result];
        }
    };
    
    ALAssetsFilter *onlyPhotosFilter = [ALAssetsFilter allPhotos];
    [self.assetsGroup setAssetsFilter:onlyPhotosFilter];
    [self.assetsGroup enumerateAssetsUsingBlock:assetsEnumerationBlock];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    [self.collectionView reloadData];
}

#pragma mark - UICollectionViewDataSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section;
{
    return [self.assets count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath;
{
    static NSString *assetCellId = @"assetCellId";
    OUIImagePickerAssetCell *cell = (OUIImagePickerAssetCell *)[collectionView dequeueReusableCellWithReuseIdentifier:assetCellId forIndexPath:indexPath];
    
    ALAsset *asset = self.assets[indexPath.item];
    
    cell.imageView.image = [UIImage imageWithCGImage:[asset thumbnail]];
    
    return cell;
}

#pragma mark - UICollectionViewDelegate
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
{
    if ([self.delegate respondsToSelector:@selector(imagePickerAssetsViewController:didSelectAsset:)]) {
        ALAsset *asset = self.assets[indexPath.item];
        [self.delegate imagePickerAssetsViewController:self didSelectAsset:asset];
    }
}

@end
