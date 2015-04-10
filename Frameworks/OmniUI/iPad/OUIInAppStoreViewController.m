// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInAppStoreViewController.h>

#import <OmniUI/OUIAppearanceColors.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIInAppStoreObserver.h>
#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUIAppController+InAppStore.h>
#import <OmniUI/OUIBorderedAuxiliaryButton.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <StoreKit/StoreKit.h>

#import "OUIInAppStoreViewControllerAppearance.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
#define DEBUG_STATE(format, ...) NSLog(@"STATE: " format, ## __VA_ARGS__)
#else
#define DEBUG_STATE(format, ...) do {} while (0)
#endif

typedef NS_ENUM(NSUInteger, OUIInAppStoreViewState) {
    OUIInAppStoreViewStateInitialLoading,
    OUIInAppStoreViewStateUpgradeUnknown, // Not a great name, but means the user needs to install v1 so we can verify a discounted upgrade
    OUIInAppStoreViewStateUpgradeEligible, // Means the user has v1 installed and is eligible for a discounted upgrade
    OUIInAppStoreViewStateUpgradeInstalled,
    OUIInAppStoreViewStatePurchaseDisabled,
    OUIInAppStoreViewStateUpgradeUnknownProcessing,
    OUIInAppStoreViewStateUpgradeEligibleProcessing,
    OUIInAppStoreViewStateUnset
};

@interface OUIInAppStoreViewController ()

@property (nonatomic, strong) IBOutlet UIWebView *featureWebView;
@property (strong, nonatomic) IBOutlet UILabel *captionLabel;
@property (strong, nonatomic) IBOutlet OUIBorderedAuxiliaryButton *priceCheckButton;
@property (strong, nonatomic) IBOutlet UIImageView *checkmarkImageView;
@property (nonatomic, strong) IBOutlet UILabel *descriptionLabel;

@property (nonatomic, strong) IBOutlet UIView *purchaseButtonsWrapperView;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *processingSpinner;
@property (nonatomic, strong) OUIBorderedAuxiliaryButton *buyButton;
@property (nonatomic, strong) OUIBorderedAuxiliaryButton *restoreButton;

@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *initialLoadingSpinner;


@property (nonatomic, strong) NSArray *preferredPurchaseButtonConstraints;
@property (nonatomic, strong) NSArray *secondaryPurchaseButtonConstraints;
@property (nonatomic, strong) NSArray *activePurchaseButtonConstraints;

@property (nonatomic, strong) NSString *productIdentifier;
@property (nonatomic, strong) SKProduct *upgradeDiscountProduct;
@property (nonatomic, strong) SKProduct *upgradePaidProduct;
@property (nonatomic, strong) SKProductsRequest *request;
@property (nonatomic, strong) OUIInAppStoreObserver *storeObserver;
@property (nonatomic, readonly) SKPaymentQueue *paymentQueue;
@property (nonatomic, assign) BOOL hasSuccessfulPurchase;

@property (nonatomic, assign) OUIInAppStoreViewState currentState;
@property (nonatomic) NSDictionary *javascriptBindingsDictionary;

// OUIAppearance Adjustable Constraits
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *captionLabelTopConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *captionLabelToDescriptionLabelConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *descriptionLabelToPurchaseButtonsWrapperViewConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *purchaseButtonsWrapperViewBottomConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *captionLabelCheckmarkImageCenterYConstraint;

@end

@implementation OUIInAppStoreViewController

- (instancetype)initWithProductIdentifier:(NSString *)aProductID;
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        OBASSERT([[[OUIAppController controller] inAppPurchaseIdentifiers] containsObject:aProductID]);
        
        self.currentState = OUIInAppStoreViewStateUnset;
        self.productIdentifier = aProductID;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.captionLabelTopConstraint.constant = [[OUIInAppStoreViewControllerAppearance appearance] floatForKeyPath:@"PaddingAboveCaptionLabel"];
    self.captionLabelToDescriptionLabelConstraint.constant = [[OUIInAppStoreViewControllerAppearance appearance] floatForKeyPath:@"PaddingBetweenCaptionAndDescriptionLabels"];
    self.descriptionLabelToPurchaseButtonsWrapperViewConstraint.constant = [[OUIInAppStoreViewControllerAppearance appearance] floatForKeyPath:@"PaddingBetweenDescriptionLabelAndPurchaseButtonWrapperView"];
    self.purchaseButtonsWrapperViewBottomConstraint.constant = [[OUIInAppStoreViewControllerAppearance appearance] floatForKeyPath:@"PaddingBelowPurchaseButtonWrapperView"];
    self.captionLabelCheckmarkImageCenterYConstraint.constant = [[OUIInAppStoreViewControllerAppearance appearance] floatForKeyPath:@"CaptionLabelCheckmarkImageCneterYOffset"];
    
    self.featureWebView.scrollView.alwaysBounceVertical = NO;

    NSString *localizedTitleFormat = NSLocalizedStringFromTableInBundle(@"About %@", @"OmniUI", OMNI_BUNDLE, @"title for in app purchase - placeholder is product title");
    self.navigationItem.title = [NSString stringWithFormat:localizedTitleFormat, [[OUIAppController controller] sheetTitleForInAppStoreProductIdentifier:_productIdentifier]];
    
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonTapped:)];
    self.navigationItem.rightBarButtonItem = done;
    
    [self.priceCheckButton addTarget:self action:@selector(priceCheckButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.priceCheckButton setTitle:NSLocalizedStringFromTableInBundle(@"Check for Free Upgrade", @"OmniUI", OMNI_BUNDLE, @"Button title that, when tapped, will display an alert explaining to the user how to check to see if they are eligilbe for a free upgrade.")
                           forState:UIControlStateNormal];
    
    self.checkmarkImageView.image = [[UIImage imageNamed:@"OUITableViewItemSelection-Selected"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.checkmarkImageView.tintColor = [OUIAppearanceDefaultColors appearance].omniExplanotextColor;
    
    CGFloat captionLabelFontSize = [[OUIInAppStoreViewControllerAppearance appearance] floatForKeyPath:@"CaptionLabelFontSize"];
    self.captionLabel.font = [[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1] fontWithSize:captionLabelFontSize];
    self.captionLabel.textColor = [OUIAppearanceDefaultColors appearance].omniExplanotextColor;

    CGFloat descriptionLabelFontSize = [[OUIInAppStoreViewControllerAppearance appearance] floatForKeyPath:@"DescriptionLabelFontSize"];
    self.descriptionLabel.font = [[UIFont preferredFontForTextStyle:UIFontTextStyleCaption2] fontWithSize:descriptionLabelFontSize];
    self.descriptionLabel.textColor = [OUIAppearanceDefaultColors appearance].omniExplanotextColor;

    self.restoreButton = [OUIBorderedAuxiliaryButton buttonWithType:UIButtonTypeSystem];
    self.restoreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.restoreButton setTitle:NSLocalizedStringFromTableInBundle(@"Restore Purchases", @"OmniUI", OMNI_BUNDLE, @"'Restore Purchases' button title string")
                        forState:UIControlStateNormal];
    [self.restoreButton addTarget:self action:@selector(restoreButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.purchaseButtonsWrapperView addSubview:self.restoreButton];

    self.buyButton = [OUIBorderedAuxiliaryButton buttonWithType:UIButtonTypeSystem];
    self.buyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.buyButton addTarget:self action:@selector(buyButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.purchaseButtonsWrapperView addSubview:self.buyButton];

    NSDictionary *views = @{
                            @"descriptionLabel" : self.descriptionLabel,
                            @"wrapperView" : self.purchaseButtonsWrapperView,
                            @"restoreButton" : self.restoreButton,
                            @"buyButton" : self.buyButton,
                            };

    NSMutableArray *preferredConstraints = [NSMutableArray array];
    [preferredConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[restoreButton]-(>=8)-[buyButton]-|"
                                                                                      options:NSLayoutFormatAlignAllBaseline
                                                                                      metrics:nil
                                                                                        views:views]];
    [preferredConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[restoreButton(32)]|"
                                                                                      options:0
                                                                                      metrics:nil
                                                                                        views:views]];
    [preferredConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[buyButton(32)]"
                                                                                      options:0
                                                                                      metrics:nil
                                                                                        views:views]];
    self.preferredPurchaseButtonConstraints = [NSArray arrayWithArray:preferredConstraints];
    
    NSMutableArray *secondaryConstraints = [NSMutableArray array];
    [secondaryConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=8)-[buyButton]-|"
                                                                                      options:0
                                                                                      metrics:nil
                                                                                        views:views]];
    [secondaryConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=8)-[restoreButton]-|"
                                                                                      options:0
                                                                                      metrics:nil
                                                                                        views:views]];
    [secondaryConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[buyButton(32)]-[restoreButton(32)]|"
                                                                                      options:0
                                                                                      metrics:nil
                                                                                        views:views]];
    self.secondaryPurchaseButtonConstraints = [NSArray arrayWithArray:secondaryConstraints];

    [self _applyBestConstraintsForPurchaseButtonsWrapperView];
}

- (void)viewWillLayoutSubviews;
{
    [super viewWillLayoutSubviews];
    
    [self _applyBestConstraintsForPurchaseButtonsWrapperView];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    [self _switchToViewState:OUIInAppStoreViewStateInitialLoading];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    [self performInitialRequestOrStateTransition];
}

- (void)performInitialRequestOrStateTransition;
{
    OBPRECONDITION(self.currentState == OUIInAppStoreViewStateInitialLoading);
    
    if ([[OUIAppController controller] isPurchaseUnlocked:_productIdentifier]) {
        [self _switchToViewState:OUIInAppStoreViewStateUpgradeInstalled];
    }
    else if ([SKPaymentQueue canMakePayments] == NO) {
        [self _switchToViewState:OUIInAppStoreViewStatePurchaseDisabled];
    }
    else {
        [self _requestProductData];
    }
}

- (void)dealloc;
{
    if (_storeObserver != nil) {
        _storeObserver.delegate = nil;
        [self.paymentQueue removeTransactionObserver:_storeObserver];
    }

    [_request cancel];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
}

#pragma mark - Private API
- (SKPaymentQueue *)paymentQueue;
{
    SKPaymentQueue *paymentQueue = [SKPaymentQueue defaultQueue];
    if (_storeObserver == nil) {
        _storeObserver = [[OUIInAppStoreObserver alloc] init];
        _storeObserver.delegate = self;
        [paymentQueue addTransactionObserver:_storeObserver];
    }
    return paymentQueue;
}

#pragma mark Actions
- (void)priceCheckButtonTapped:(id)sender;
{
    NSString *description = [[OUIAppController controller] descriptionForPricingOptionSKU:self.upgradeDiscountProduct.productIdentifier];
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed purchase alert");
    NSString *moreInfoString = NSLocalizedStringFromTableInBundle(@"More Info", @"OmniUI", OMNI_BUNDLE, @"Button title that will launch safari to give the user more information about getting the disscounted/free upgrade.");
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:description preferredStyle:UIAlertControllerStyleAlert];
    
    NSURL *proUpgradeMoreInfoURL = [[OUIAppController controller] proUpgradeMoreInfoURL];
    if (proUpgradeMoreInfoURL != nil) {
        [alertController addAction:[UIAlertAction actionWithTitle:moreInfoString style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[UIApplication sharedApplication] openURL:proUpgradeMoreInfoURL];
        }]];
    }
    [alertController addAction:[UIAlertAction actionWithTitle:dismissAlertString style:UIAlertActionStyleDefault handler:nil]];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)buyButtonTapped:(id)sender;
{
    OBASSERT(self.currentState == OUIInAppStoreViewStateUpgradeEligible || self.currentState == OUIInAppStoreViewStateUpgradeUnknown);
    
    SKProduct *upgradeProduct = [self _productForCurrentUpgradeState];
    NSString *upgradeSKU = upgradeProduct.productIdentifier;
    
    [[OUIAppController controller] validateEligibilityForPricingOptionSKU:upgradeSKU completion:^(BOOL isValidated) {
        if (isValidated) {
            [self _validatedPurchaseWithProduct:upgradeProduct];
        }
    }];
}

- (void)restoreButtonTapped:(id)sender;
{
    [self _switchToViewState:[self _processingStateForCurrentUpgradeState]];
    [self.paymentQueue restoreCompletedTransactions];
}

- (void)doneButtonTapped:(id)sender;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark Helpers
// Not in love with this code. I'm sorry.
- (SKProduct *)_productForCurrentUpgradeState;
{
    if (self.currentState == OUIInAppStoreViewStateUpgradeUnknown ||
        self.currentState == OUIInAppStoreViewStateUpgradeUnknownProcessing) {
        return self.upgradePaidProduct;
    }
    else if (self.currentState == OUIInAppStoreViewStateUpgradeEligible ||
             self.currentState == OUIInAppStoreViewStateUpgradeEligibleProcessing) {
        return self.upgradeDiscountProduct;
    }
    else {
        OBASSERT_NOT_REACHED(@"no product exists for current state: %ld", (long)self.currentState);
        return nil;
    }
}
// Not in love with this code. I'm sorry.
- (OUIInAppStoreViewState)_processingStateForCurrentUpgradeState;
{
    if (self.currentState == OUIInAppStoreViewStateUpgradeUnknown) {
        return OUIInAppStoreViewStateUpgradeUnknownProcessing;
    }
    else if (self.currentState == OUIInAppStoreViewStateUpgradeEligible) {
        return OUIInAppStoreViewStateUpgradeEligibleProcessing;
    }
    else {
        OBASSERT_NOT_REACHED(@"processing state does not exist for current state: %ld", (long)self.currentState);
        return OUIInAppStoreViewStateUnset;
    }
}

/*!
 @discussion Switches to Upgrade Eligible or Upgrade Unknown depending on [[OUIAppController controller] isEligibleForProUpgradeDiscount]
 */
- (void)_switchToAppropriateUpgradeState;
{
    BOOL isEligibleForDiscount = [[OUIAppController controller] isEligibleForProUpgradeDiscount];
    
    if (isEligibleForDiscount) {
        [self _switchToViewState:OUIInAppStoreViewStateUpgradeEligible];
    }
    else {
        [self _switchToViewState:OUIInAppStoreViewStateUpgradeUnknown];
    }
    
}

- (NSString *)_localizedPriceStringForProduct:(SKProduct *)product;
{
    NSNumberFormatter *priceFormatter = [[NSNumberFormatter alloc] init];
    [priceFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    [priceFormatter setLocale:product.priceLocale];
    NSString *localizedPrice = [priceFormatter stringForObjectValue:product.price];
    return localizedPrice;
}

- (void)_validatedPurchaseWithProduct:(SKProduct *)product;
{
    OBPRECONDITION(product != nil);
    SKPayment *payment = [SKPayment paymentWithProduct:product];
    [self.paymentQueue addPayment:payment];
    [self _switchToViewState:[self _processingStateForCurrentUpgradeState]];
}

- (void)_showError;
{
    NSString *storeErrorAlertTitle = NSLocalizedStringFromTableInBundle(@"Unable to reach App Store", @"OmniUI", OMNI_BUNDLE, @"Alert title for error loading product information");
    NSString *storeErrorAlertDescription = NSLocalizedStringFromTableInBundle(@"This device might not be connected to the Internet.", @"OmniUI", OMNI_BUNDLE, @"Alert description for error loading product information");
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed purchase alert");
    
    [_buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Error", @"OmniUI", OMNI_BUNDLE, @"In app Buy button error title") forState:UIControlStateDisabled];
    
    UIAlertView *cannotPurchaseAlert = [[UIAlertView alloc] initWithTitle:storeErrorAlertTitle message:storeErrorAlertDescription delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil];
    [cannotPurchaseAlert show];
}

#pragma mark Constraints Helpers
- (void)_applyBestConstraintsForPurchaseButtonsWrapperView;
{
    [NSLayoutConstraint deactivateConstraints:self.activePurchaseButtonConstraints];
    self.activePurchaseButtonConstraints = nil;
    
    // Test with title of Buy button to be biggest possible text.
    NSString *currentNormalBuyButtonTitle = [self.buyButton titleForState:UIControlStateNormal];
    [self.buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Purchased. Thank you!", @"OmniUI", OMNI_BUNDLE, @"Buy button thank you message")
                    forState:UIControlStateNormal];
    
    [NSLayoutConstraint activateConstraints:self.preferredPurchaseButtonConstraints];
    CGSize sizeWithPreferredConstraints = [self.purchaseButtonsWrapperView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    if (sizeWithPreferredConstraints.width <= self.view.bounds.size.width) {
        self.activePurchaseButtonConstraints = self.preferredPurchaseButtonConstraints;
    }
    else {
        [NSLayoutConstraint deactivateConstraints:self.preferredPurchaseButtonConstraints];
        [NSLayoutConstraint activateConstraints:self.secondaryPurchaseButtonConstraints];
        self.activePurchaseButtonConstraints = self.secondaryPurchaseButtonConstraints;
    }
    
    [self.buyButton setTitle:currentNormalBuyButtonTitle
                    forState:UIControlStateNormal];
}

#pragma mark Observers
- (void)appWillEnterForeground:(NSNotification *)notification;
{
    [self _switchToViewState:OUIInAppStoreViewStateInitialLoading];
    [self performInitialRequestOrStateTransition];
}

#pragma mark - SKProductsRequestDelegate and Helpers
- (void)_requestProductData;
{
    OBASSERT(self.currentState == OUIInAppStoreViewStateInitialLoading);
    
    if (self.request == nil) {
        NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:_productIdentifier];
        self.request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:pricingOptionSKUs]];
        self.request.delegate = self;
    }
    
    [self.request start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response;
{
    NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:_productIdentifier];
    for (NSString *invalidIdentifier in response.invalidProductIdentifiers) {
        if ([pricingOptionSKUs containsObject:invalidIdentifier]) {
            [self _switchToViewState:OUIInAppStoreViewStatePurchaseDisabled];
            [self _showError];
            return;
        } else {
            OBASSERT_NOT_REACHED("received strange response from app store");
        }
    }

    NSString *proUpgradePaidSKU = [[OUIAppController controller] proUpgradePaidSKU];
    NSString *proUpgradeDiscountSKU = [[OUIAppController controller] proUpgradeDiscountSKU];
    
    // Note that there may be other SKUs in the list (legacy SKUs which unlock our product), but this interface only cares about these two products
    for (SKProduct *product in response.products) {
        if ([product.productIdentifier isEqualToString:proUpgradePaidSKU]) {
            self.upgradePaidProduct = product;
        } else if ([product.productIdentifier isEqualToString:proUpgradeDiscountSKU]) {
            self.upgradeDiscountProduct = product;
        }
    }

    OBASSERT(self.upgradePaidProduct != nil && self.upgradeDiscountProduct != nil);
    [self _switchToAppropriateUpgradeState];
}

- (void)requestDidFinish:(SKRequest *)request;
{
    OBPRECONDITION(_request == request);
    self.request = nil;
}

- (void)request:(SKRequest *)aRequest didFailWithError:(NSError *)error;
{
    OBASSERT(_request == aRequest);
    OBASSERT(self.currentState == OUIInAppStoreViewStateInitialLoading);
    
    NSLog(@"%@: StoreKit request failed: %@", OBShortObjectDescription(self), [error toPropertyList]);
    
    [self _switchToViewState:OUIInAppStoreViewStatePurchaseDisabled];
    [self _showError];
    self.request = nil;
}

#pragma mark - OUIInAppStoreObserverDelegate
- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue transactionsFailed:(NSArray *)failedTransactions;
{
    NSString *message = [[failedTransactions valueForKeyPath:@"error.localizedDescription"] componentsJoinedByString:@"\n"];
    
    NSLog(@"%@", message);
    NSString *purchaseFailedString = NSLocalizedStringFromTableInBundle(@"Purchase Failed", @"OmniUI", OMNI_BUNDLE, @"Purchase failed alert title");
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed purchase alert");
    
    UIAlertController *transactionFailedAlertController = [UIAlertController alertControllerWithTitle:purchaseFailedString message:message preferredStyle:UIAlertControllerStyleAlert];
    [transactionFailedAlertController addAction:[UIAlertAction actionWithTitle:dismissAlertString style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:transactionFailedAlertController animated:YES completion:nil];
    
    [self _switchToViewState:OUIInAppStoreViewStateInitialLoading];
    [self _switchToAppropriateUpgradeState];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue;
{
    OBASSERT(self.currentState == OUIInAppStoreViewStateUpgradeEligibleProcessing || self.currentState == OUIInAppStoreViewStateUpgradeUnknownProcessing);
    if (self.hasSuccessfulPurchase) {
        [self _switchToViewState:OUIInAppStoreViewStateUpgradeInstalled];
    }
    else {
        NSString *noPurchasesFoundTitle = NSLocalizedStringFromTableInBundle(@"Restore Complete", @"OmniUI", OMNI_BUNDLE, @"No purchases found title");
        NSString *noPurchasesFoundMessageFormat = NSLocalizedStringFromTableInBundle(@"All purchases for your current App Store account have been restored, but %@ wasn't one of those purchases.", @"OmniUI", OMNI_BUNDLE, @"No purchases found message format");
        NSString *noPurchasesFoundMessage = [NSString stringWithFormat:noPurchasesFoundMessageFormat, [[OUIAppController controller] sheetTitleForInAppStoreProductIdentifier:_productIdentifier]];
        NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss alert");

        UIAlertView *transactionFailedAlert = [[UIAlertView alloc] initWithTitle:noPurchasesFoundTitle message:noPurchasesFoundMessage delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil, nil];
        [transactionFailedAlert show];

        [self _switchToViewState:OUIInAppStoreViewStateInitialLoading];
        [self _switchToAppropriateUpgradeState];
    }
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error;
{
    NSLog(@"%@", error);
    NSString *restoreFailedString = NSLocalizedStringFromTableInBundle(@"Restore Failed", @"OmniUI", OMNI_BUNDLE, @"Restore failed alert title");
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed restore alert");
    
    UIAlertController *transactionFailedAlertController = [UIAlertController alertControllerWithTitle:restoreFailedString message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
    [transactionFailedAlertController addAction:[UIAlertAction actionWithTitle:dismissAlertString style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:transactionFailedAlertController animated:YES completion:nil];
    
    [self _switchToViewState:OUIInAppStoreViewStateInitialLoading];
    [self _switchToAppropriateUpgradeState];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue successfullyPurchasedSKU:(NSString *)pricingSKU;
{
    NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:_productIdentifier];
    if (![pricingOptionSKUs containsObject:pricingSKU]) {
        OBASSERT_NOT_REACHED("How are we hearing about a SKU we don't recognize?");
        return; // We don't know this SKU
    }
    
    self.hasSuccessfulPurchase = YES;

    // They've purchased one of the SKUs for our products. (Note that SKProduct.productIdentifier is the identifier for a single SKU, while our productIdentifier represents multiple SKUs that have the same effect.)
    // With restore, we wait until we know all restores are done before switching our view state. We don't need to do this for purchases because a user can only purchase one IAP at a time, and we currently only support one. (Technically two, free uprgarde or paid upgrade, but the user can only actually purchase one.)
    [self _switchToViewState:OUIInAppStoreViewStateUpgradeInstalled];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue successfullyRestoredSKU:(NSString *)pricingSKU;
{
    NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:_productIdentifier];
    if (![pricingOptionSKUs containsObject:pricingSKU]) {
        OBASSERT_NOT_REACHED("How are we hearing about a SKU we don't recognize?");
        return; // We don't know this SKU
    }
    
    self.hasSuccessfulPurchase = YES;

    // They've purchased one of the SKUs for our products. (Note that SKProduct.productIdentifier is the identifier for a single SKU, while our productIdentifier represents multiple SKUs that have the same effect.)
    // When restoring, successfullyRestoredSKU could potentially get called multipul times. We want to delay our view state change to -storeObserver:paymentQueueRestoreCompletedTransactionsFinished: which will get called once all SKUs have been restored.
//    [self _switchToViewState:OUIInAppStoreViewStateUpgradeInstalled];
}

#pragma mark - Private View State Helpers
- (void)_switchToViewState:(OUIInAppStoreViewState)toState;
{
    if ([self _isValidTransitionFromState:self.currentState toState:toState] == NO) {
        DEBUG_STATE(@"Invalid transition from: %@ to: %@", [self _debugNameForState:self.currentState], [self _debugNameForState:toState]);
        return;
    }

    DEBUG_STATE(@"Transitioning from: %@ State to: %@ State", [self _debugNameForState:self.currentState], [self _debugNameForState:toState]);
    self.currentState = toState;
    [self _updateViewForCurrentState];
}

- (BOOL)_isValidTransitionFromState:(OUIInAppStoreViewState)fromState toState:(OUIInAppStoreViewState)toState;
{
    BOOL isValid = NO;
    
    switch (fromState) {
        case OUIInAppStoreViewStateUnset:
            isValid = (toState == OUIInAppStoreViewStateInitialLoading);
            break;
        case OUIInAppStoreViewStateInitialLoading:
            isValid = (toState == OUIInAppStoreViewStateUpgradeUnknown) || (toState == OUIInAppStoreViewStateUpgradeEligible) || (toState == OUIInAppStoreViewStateUpgradeInstalled) || (toState == OUIInAppStoreViewStatePurchaseDisabled);
            break;
        case OUIInAppStoreViewStatePurchaseDisabled:
            isValid = (toState == OUIInAppStoreViewStateInitialLoading); // Can only retry from the start (e.g. after purchases are reenabled from Settings.app)
            break;
        case OUIInAppStoreViewStateUpgradeEligible:
            isValid = (toState == OUIInAppStoreViewStateUpgradeEligibleProcessing);
            break;
        case OUIInAppStoreViewStateUpgradeEligibleProcessing:
            isValid = (toState == OUIInAppStoreViewStateInitialLoading) || (toState == OUIInAppStoreViewStateUpgradeInstalled);
            break;
        case OUIInAppStoreViewStateUpgradeInstalled:
            isValid = NO; // Yur done!
            break;
        case OUIInAppStoreViewStateUpgradeUnknown:
            isValid = (toState == OUIInAppStoreViewStateInitialLoading) || (toState == OUIInAppStoreViewStateUpgradeUnknownProcessing);
            break;
        case OUIInAppStoreViewStateUpgradeUnknownProcessing:
            isValid = (toState == OUIInAppStoreViewStateUpgradeInstalled) || (toState == OUIInAppStoreViewStateInitialLoading);
            break;
            
        default:
            OBASSERT_NOT_REACHED(@"unknown state");
            isValid = NO;
            break;
    }
    
    return isValid;
}

- (void)_updateViewForCurrentState;
{
    DEBUG_STATE(@"Updating view for %@ State.", [self _debugNameForState:self.currentState]);
    switch (self.currentState) {
        case OUIInAppStoreViewStateInitialLoading:
            [self _updateViewForInitialLoading];
            break;
        case OUIInAppStoreViewStatePurchaseDisabled:
            [self _updateViewForPurchaseDisabled];
            break;
        case OUIInAppStoreViewStateUpgradeEligible:
            [self _updateViewForUpgradeEligible];
            break;
        case OUIInAppStoreViewStateUpgradeEligibleProcessing:
            [self _updateViewForUpgradeEligibleProcessing];
            break;
        case OUIInAppStoreViewStateUpgradeInstalled:
            [self _updateViewForUpgradeInstalled];
            break;
        case OUIInAppStoreViewStateUpgradeUnknown:
            [self _updateViewForUpgradeUnknown];
            break;
        case OUIInAppStoreViewStateUpgradeUnknownProcessing:
            [self _updateViewForUpgradeUnknownProcessing];
            break;
            
        default:
            OBASSERT_NOT_REACHED(@"unknown state");
            break;
    }
}

- (void)_updateViewForInitialLoading;
{
    _javascriptBindingsDictionary = [[OUIAppController controller] aboutScreenBindingsDictionary];
    [self.featureWebView loadRequest:[NSURLRequest requestWithURL:[[OUIAppController controller] descriptionURLForProductIdentifier:_productIdentifier]]];
    self.captionLabel.hidden = YES;
    self.priceCheckButton.hidden = YES;
    self.checkmarkImageView.hidden = YES;
    self.descriptionLabel.hidden = YES;
    self.restoreButton.hidden = YES;
    self.buyButton.hidden = YES;
    [self.processingSpinner stopAnimating];
    [self.initialLoadingSpinner startAnimating];
}

- (void)_updateViewForPurchaseDisabled;
{
    self.captionLabel.hidden = NO;
    self.captionLabel.text = NSLocalizedStringFromTableInBundle(@"Purchasing is Disabled", @"OmniUI", OMNI_BUNDLE, @"Purchasing is disabled alert title");
 
    self.priceCheckButton.hidden = YES;
    self.checkmarkImageView.hidden = YES;

    self.descriptionLabel.hidden = NO;
    self.descriptionLabel.text = NSLocalizedStringFromTableInBundle(@"In-App Purchasing is unavailable or not allowed on this device. To enable purchasing, check Restrictions in the Settings app.", @"OmniUI", OMNI_BUNDLE, @"Purchasing is disabled details");

    self.restoreButton.hidden = NO;
    self.restoreButton.enabled = NO;
    self.restoreButton.tintColor = [self.view.tintColor colorWithAlphaComponent:0.5];
    
    self.buyButton.hidden = NO;
    self.buyButton.enabled = NO;
    self.buyButton.tintColor = [self.view.tintColor colorWithAlphaComponent:0.5];
    [self.buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Disabled", @"OmniUI", OMNI_BUNDLE, @"Button is disabled due to purchase restrictions") forState:UIControlStateDisabled];
    
    [self.processingSpinner stopAnimating];
    [self.initialLoadingSpinner stopAnimating];
}

- (void)_updateViewForUpgradeEligible;
{
    self.captionLabel.hidden = NO;
    self.captionLabel.text = NSLocalizedStringFromTableInBundle(@"Eligible for free upgrade", @"OmniUI", OMNI_BUNDLE, @"Title explaining that user is eligible for discounted upgrade ");
    
    self.priceCheckButton.hidden = YES;
    self.checkmarkImageView.hidden = NO;
    
    self.descriptionLabel.hidden = NO;
    self.descriptionLabel.text = [[OUIAppController controller] descriptionForPricingOptionSKU:self.upgradeDiscountProduct.productIdentifier];
    
    self.restoreButton.hidden = NO;
    self.restoreButton.enabled = YES;
    
    self.buyButton.hidden = NO;
    self.buyButton.enabled = YES;
    NSString *localizedPrice = [self _localizedPriceStringForProduct:self.upgradeDiscountProduct];
    NSString *localizedPriceFormat = NSLocalizedStringFromTableInBundle(@"Buy %@", @"OmniUI", OMNI_BUNDLE, @"'Buy' button title format. Placeholder is the price. The currency symbol will be provided at run time.");
    [self.buyButton setTitle:[NSString stringWithFormat:localizedPriceFormat, localizedPrice]
                    forState:UIControlStateNormal];
    
    [self.processingSpinner stopAnimating];
    [self.initialLoadingSpinner stopAnimating];
}

- (void)_updateViewForUpgradeEligibleProcessing;
{
    self.captionLabel.hidden = NO;
    self.captionLabel.text = NSLocalizedStringFromTableInBundle(@"Eligible for free upgrade", @"OmniUI", OMNI_BUNDLE, @"Title explaining that user is eligible for discounted upgrade ");
    
    self.priceCheckButton.hidden = YES;
    self.checkmarkImageView.hidden = NO;
    
    self.descriptionLabel.hidden = NO;
    self.descriptionLabel.text = [[OUIAppController controller] descriptionForPricingOptionSKU:self.upgradeDiscountProduct.productIdentifier];
    
    self.restoreButton.hidden = YES;
    self.buyButton.hidden = YES;
    
    [self.processingSpinner startAnimating];
    [self.initialLoadingSpinner stopAnimating];
}

- (void)_updateViewForUpgradeInstalled;
{
    [self.request cancel];
    self.request = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInAppStoreViewControllerUpgradeInstalledNotification object:self];

    _javascriptBindingsDictionary = [[OUIAppController controller] aboutScreenBindingsDictionary];
    [self.featureWebView stringByEvaluatingJavaScriptFromString:[[self _javascriptBindingsString] stringByAppendingString:@"aboutOnLoad();"]];
    [self.featureWebView.scrollView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:YES]; // Scroll to an arbitrary rect at the top of the web view to get it to 'scroll to top'.
    self.captionLabel.hidden = YES;
    self.priceCheckButton.hidden = YES;
    self.checkmarkImageView.hidden = YES;
    self.descriptionLabel.hidden = YES;
    
    self.restoreButton.hidden = NO;
    self.restoreButton.enabled = NO;
    self.restoreButton.tintColor = [self.view.tintColor colorWithAlphaComponent:0.5];
    
    self.buyButton.hidden = NO;
    self.buyButton.enabled = NO;
    self.buyButton.tintColor = [self.view.tintColor colorWithAlphaComponent:0.5];
    [self.buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Purchased. Thank you!", @"OmniUI", OMNI_BUNDLE, @"Buy button thank you message") forState:UIControlStateDisabled];
    
    [self.processingSpinner stopAnimating];
    [self.initialLoadingSpinner stopAnimating];
}

- (void)_updateViewForUpgradeUnknown;
{
    self.captionLabel.hidden = YES;
    
    self.priceCheckButton.hidden = NO;
    self.priceCheckButton.enabled = YES;
    self.priceCheckButton.tintColor = self.view.tintColor;
    
    self.checkmarkImageView.hidden = YES;
    self.descriptionLabel.hidden = YES;
    
    self.restoreButton.hidden = NO;
    self.restoreButton.enabled = YES;
    
    self.buyButton.hidden = NO;
    self.buyButton.enabled = YES;
    NSString *localizedPrice = [self _localizedPriceStringForProduct:self.upgradePaidProduct];
    NSString *localizedPriceFormat = NSLocalizedStringFromTableInBundle(@"Buy %@", @"OmniUI", OMNI_BUNDLE, @"'Buy' button title format. Placeholder is the price. The currency symbol will be provided at run time.");
    [self.buyButton setTitle:[NSString stringWithFormat:localizedPriceFormat, localizedPrice]
                    forState:UIControlStateNormal];
    
    [self.processingSpinner stopAnimating];
    [self.initialLoadingSpinner stopAnimating];
}

- (void)_updateViewForUpgradeUnknownProcessing;
{
    self.captionLabel.hidden = YES;
    
    self.priceCheckButton.hidden = NO;
    self.priceCheckButton.enabled = NO;
    self.priceCheckButton.tintColor = [self.view.tintColor colorWithAlphaComponent:0.5];
    
    self.checkmarkImageView.hidden = YES;
    self.descriptionLabel.hidden = YES;
    
    self.restoreButton.hidden = YES;
    self.buyButton.hidden = YES;
    
    [self.processingSpinner startAnimating];
    [self.initialLoadingSpinner stopAnimating];
}

- (NSString *)_debugNameForState:(OUIInAppStoreViewState)state;
{
    NSString *debugName = nil;
    
    switch (state) {
        case OUIInAppStoreViewStateInitialLoading:
            debugName = @"Initial Loading";
            break;
        case OUIInAppStoreViewStatePurchaseDisabled:
            debugName = @"Purchase Disabled";
            break;
        case OUIInAppStoreViewStateUpgradeEligible:
            debugName = @"Upgrade Eligible";
            break;
        case OUIInAppStoreViewStateUpgradeEligibleProcessing:
            debugName = @"Upgrade Eligible Processing";
            break;
        case OUIInAppStoreViewStateUpgradeInstalled:
            debugName = @"Upgrade Installed";
            break;
        case OUIInAppStoreViewStateUpgradeUnknown:
            debugName = @"Upgrade Unknown";
            break;
        case OUIInAppStoreViewStateUpgradeUnknownProcessing:
            debugName = @"Upgrade Unknown Processing";
            break;
            
        case OUIInAppStoreViewStateUnset:
            debugName = @"Unset";
            break;
            
        default:
            OBASSERT_NOT_REACHED(@"unknown state");
            break;
    }
    
    return debugName;
}

- (NSString *)_javascriptBindingsString;
{
    if (_javascriptBindingsDictionary == nil)
        return @"";

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_javascriptBindingsDictionary options:0 error:&jsonError];
    assert(jsonData != nil);

    NSString *jsonValue = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *jsonBindingsString = [NSString stringWithFormat:@"aboutBindings=%@;", jsonValue];
    return jsonBindingsString;
}

#pragma mark - UIWebViewDelegate protocol

- (void)webViewDidStartLoad:(UIWebView *)webView;
{
    [webView stringByEvaluatingJavaScriptFromString:[self _javascriptBindingsString]];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView;
{
    [webView stringByEvaluatingJavaScriptFromString:[self _javascriptBindingsString]];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error;
{
    NSLog(@"About: Load failed: %@", [error userInfo]);
    OBASSERT_NOT_REACHED("Bad link? The In-App Purchase screen shouldn't be trying to load things that could fail to load.");
}

@end
