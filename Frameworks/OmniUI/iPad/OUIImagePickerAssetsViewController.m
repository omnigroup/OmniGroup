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

@property (nonatomic, strong) ALAssetsLibrary *library;
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

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.library = [[ALAssetsLibrary alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_assetsLibraryDidChange:) name:ALAssetsLibraryChangedNotification object:self.library];
    
    self.assets = [[NSMutableArray alloc] init];
    [self _updateAssets];
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Private
- (void)_assetsLibraryDidChange:(NSNotification *)notification;
{
    // Accroding to the documentation:
    //   If the user information dictionary is nil, reload all assets and asset groups.
    //   If the user information dictionary an empty dictionary, there is no need to reload assets and asset groups.
    //   If the user information dictionary is not empty, reload the effected assets and asset groups. For the keys used, see “Notification Keys.”
    // We're currently being lazy about non-nil/empty userInfo. We could optimize by selectively reloading. We can switch to that if we find this is too slow.
    NSDictionary *userInfo = [notification userInfo];
    BOOL shouldReload = ((userInfo == nil) || ([userInfo allKeys] > 0));
    if (shouldReload) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self _updateAssets];
        }];
    }
}

- (void)_updateAssets;
{
    OBPRECONDITION(self.assetsGroupURL);
    OBASSERT([NSThread isMainThread]);
    
    [self.assets removeAllObjects];
    
    [self.library groupForURL:self.assetsGroupURL resultBlock:^(ALAssetsGroup *group) {
        self.title = [group valueForProperty:ALAssetsGroupPropertyName];
        
        ALAssetsFilter *onlyPhotosFilter = [ALAssetsFilter allPhotos];
        [group setAssetsFilter:onlyPhotosFilter];
        [group enumerateAssetsUsingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
            if (result) {
                [self.assets addObject:result];
            }
        }];
        
        [self.collectionView reloadData];
    } failureBlock:^(NSError *error) {
        NSLog(@"Could not load group with url: %@ error: %@", self.assetsGroupURL, error);
    }];
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
