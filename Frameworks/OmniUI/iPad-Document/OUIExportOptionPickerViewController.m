// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIExportOptionPickerViewController.h"

#import <OmniUI/OUIBarButtonItem.h>

#import "OUIExportOptionViewCell.h"
#import "OUIExportOption.h"
#import "OUIExportOptionsCollectionViewLayout.h"
#import "OUIExportProgressViewController.h"

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@interface OUIExportOptionPickerViewController () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (weak, nonatomic) IBOutlet UICollectionView *collectionView;
@property (weak, nonatomic) IBOutlet UILabel *exportDestinationLabel;
@property (weak, nonatomic) IBOutlet UIButton *inAppPurchaseButton;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *collectionViewTrailingConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *bottomViewsTrailingConstraint;
@property (weak, nonatomic) IBOutlet UIView *bottomViewsContainerView;

@end

@implementation OUIExportOptionPickerViewController
{
    OUIExportProgressViewController *_progressViewController;
}

- initWithExportOptions:(NSArray <OUIExportOption *> *)exportOptions;
{
    if (!(self = [super initWithNibName:@"OUIExportOptions" bundle:OMNI_BUNDLE]))
        return nil;

    _exportOptions = [exportOptions copy];

    return self;
}

- (id)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (id)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (void)setShowInAppPurchaseButton:(BOOL)showInAppPurchaseButton;
{
    _showInAppPurchaseButton = showInAppPurchaseButton;
    [self _updateInAppPurchaseButton];
}

- (void)setInAppPurchaseButtonTitle:(NSString *)inAppPurchaseButtonTitle;
{
    _inAppPurchaseButtonTitle = [inAppPurchaseButtonTitle copy];
    [self _updateInAppPurchaseButton];
}

- (void)setExportDestination:(nullable NSString *)text;
{
    [self view]; // load our outlets
    UILabel *exportDestinationLabel = _exportDestinationLabel;
    OBASSERT(exportDestinationLabel != nil);
    exportDestinationLabel.text = text;
}

- (void)setInterfaceDisabledWhileExporting:(BOOL)shouldDisable completion:(void (^ _Nullable)(void))completion;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(self.isViewLoaded);

    self.navigationItem.leftBarButtonItem.enabled = !shouldDisable;
    self.navigationItem.rightBarButtonItem.enabled = !shouldDisable;
    self.view.userInteractionEnabled = !shouldDisable;

    if (shouldDisable) {
        OBASSERT_NULL(_progressViewController)
        _progressViewController = [[OUIExportProgressViewController alloc] initWithTranslucentBackground:YES];
        _progressViewController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
        _progressViewController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [self presentViewController:_progressViewController animated:YES completion:completion];
    } else {
        OBASSERT_NOTNULL(_progressViewController);
        [_progressViewController dismissViewControllerAnimated:NO completion:completion];
        _progressViewController = nil;
    }
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIBarButtonItem *cancel = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancel:)];
    self.navigationItem.leftBarButtonItem = cancel;

    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Choose Format", @"OmniUIDocument", OMNI_BUNDLE, @"export options title");

    self.collectionView.backgroundColor = self.view.backgroundColor;
    [self.collectionView registerNib:[UINib nibWithNibName:@"OUIExportOptionViewCell" bundle:OMNI_BUNDLE] forCellWithReuseIdentifier:exportOptionCellReuseIdentifier];
    if ([self.collectionView.collectionViewLayout isKindOfClass:[OUIExportOptionsCollectionViewLayout class]]) {
        OUIExportOptionsCollectionViewLayout *layout =((OUIExportOptionsCollectionViewLayout *)(self.collectionView.collectionViewLayout));
        layout.minimumInterItemSpacing = 0.0;
    }

    [_inAppPurchaseButton addTarget:self action:@selector(_inAppPurchaseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    [self _updateInAppPurchaseButton];
}

- (void)updateViewConstraints;
{
    // This code manipulates the bottom of the collection view and the container view that contains the "buy pro" and "where are we uploading" views, so that only the relevant views show and the collection view eats as much vertical space as possible.
    UIButton *inAppPurchaseButton = _inAppPurchaseButton;
    UILabel *exportDestinationLabel = _exportDestinationLabel;
    if (![inAppPurchaseButton isHidden] && exportDestinationLabel.text) {
        [self.view removeConstraint:self.collectionViewTrailingConstraint];
        self.collectionViewTrailingConstraint = [NSLayoutConstraint constraintWithItem:self.collectionView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.bottomViewsContainerView attribute:NSLayoutAttributeTop multiplier:1.0 constant:0];
        [self.view addConstraint:self.collectionViewTrailingConstraint];
        self.bottomViewsTrailingConstraint.constant = 0;
        exportDestinationLabel.hidden = NO;
    } else if (![inAppPurchaseButton isHidden]) {
        [self.view removeConstraint:self.collectionViewTrailingConstraint];
        self.collectionViewTrailingConstraint = [NSLayoutConstraint constraintWithItem:self.collectionView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.bottomViewsContainerView attribute:NSLayoutAttributeTop multiplier:1.0 constant:0];
        [self.view addConstraint:self.collectionViewTrailingConstraint];

        self.bottomViewsTrailingConstraint.constant = -8; //the empty text label collapses down, so we only need to account for the extra 8 pts of padding between the label & button.
        exportDestinationLabel.hidden = YES;
    } else if (exportDestinationLabel.text) {
        [self.view removeConstraint:self.collectionViewTrailingConstraint];
        self.collectionViewTrailingConstraint = [NSLayoutConstraint constraintWithItem:self.collectionView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.exportDestinationLabel attribute:NSLayoutAttributeTop multiplier:1.0 constant:-8.0]; // -8.0 to give the expected padding above the export destination label
        [self.view addConstraint:self.collectionViewTrailingConstraint];
        self.bottomViewsTrailingConstraint.constant = 0;
        exportDestinationLabel.hidden = NO;
    } else {
        [self.view removeConstraint:self.collectionViewTrailingConstraint];
        self.collectionViewTrailingConstraint = [NSLayoutConstraint constraintWithItem:self.collectionView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0];
        [self.view addConstraint:self.collectionViewTrailingConstraint];

    }

    [super updateViewConstraints];
}

#pragma mark - UICollectionViewDataSource

static NSString * const exportOptionCellReuseIdentifier = @"exportOptionCell";

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section;
{
    return [_exportOptions count];
}

// The cell that is returned must be retrieved from a call to -dequeueReusableCellWithReuseIdentifier:forIndexPath:
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIExportOption *option = _exportOptions[indexPath.item];

    OUIExportOptionViewCell *cell = (OUIExportOptionViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:exportOptionCellReuseIdentifier forIndexPath:indexPath];

    [cell.imageView setImage:option.image];
    [cell.label setText:option.label];

    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIExportOptionViewCell *cell = (OUIExportOptionViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
    OUIExportOption *selectedOption = _exportOptions[indexPath.item];

    [_delegate exportOptionPicker:self selectedExportOption:selectedOption inRect:cell.frame ofView:collectionView];
}

#pragma mark - Private

- (IBAction)_cancel:(id)sender;
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)_updateInAppPurchaseButton;
{
    UIButton *inAppPurchaseButton = _inAppPurchaseButton;
    [inAppPurchaseButton setTitle:_inAppPurchaseButtonTitle forState:UIControlStateNormal];
    inAppPurchaseButton.hidden = !_showInAppPurchaseButton;
}

- (void)_inAppPurchaseButtonTapped:(id)sender;
{
    [_delegate exportOptionPickerPerformInAppPurchase:self];
}

@end

NS_ASSUME_NONNULL_END
