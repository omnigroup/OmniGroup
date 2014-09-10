// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInAppStoreViewController.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIInAppStoreObserver.h>
#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUIAppController+InAppStore.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <StoreKit/StoreKit.h>

RCS_ID("$Id$");

@interface OUIInAppStoreViewController ()
@property (nonatomic, strong) SKProductsRequest *request;
@property (nonatomic, strong) OUIInAppStoreObserver *storeObserver;
@property (nonatomic, strong) NSString *productIdentifier;
@property (nonatomic, readonly) SKPaymentQueue *paymentQueue;
@property (nonatomic) BOOL hasPurchased;
@end

@implementation OUIInAppStoreViewController
{
    NSMutableDictionary *_productForSKU;
}

- (id)initWithProductIdentifier:(NSString *)aProductID;
{
    if (!(self = [super init]))
        return nil;

    _productForSKU = [[NSMutableDictionary alloc] init];
    [self setProductIdentifier:aProductID];

    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self)
        return nil;
    
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
    self.navigationItem.rightBarButtonItem = done;

    return self;
}

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

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [NSLayoutConstraint constraintWithItem:_featureWebView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.topLayoutGuide attribute:NSLayoutAttributeBottom multiplier:1 constant:0].active = YES;
    _featureWebView.scrollView.alwaysBounceVertical = NO;
    
    [_buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Loading", @"OmniUI", OMNI_BUNDLE, @"Buy button title while app store is loading") forState:UIControlStateNormal];
    [_buyButton addTarget:self action:@selector(purchase:) forControlEvents:UIControlEventTouchUpInside];
    [_buyButton setEnabled:NO];
    _buyButton.tintColor = [self.view.tintColor colorWithAlphaComponent:0.5];

    [self updateUIForProductIdentifier:_productIdentifier];
    if ([[OUIAppController controller] isPurchaseUnlocked:_productIdentifier])
        [self showPurchasedText:_productIdentifier];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    if ([[OUIAppController controller] isPurchaseUnlocked:_productIdentifier]) {
        [self showPurchasedText:_productIdentifier];
    } else if ([SKPaymentQueue canMakePayments]) {
        [self requestProductData];
    } else {
        NSString *purchasingDisabledTitle = NSLocalizedStringFromTableInBundle(@"Purchasing is Disabled", @"OmniUI", OMNI_BUNDLE, @"Purchasing is disabled alert title");
        NSString *purchasingDisabledDetails = NSLocalizedStringFromTableInBundle(@"In-App Purchasing is unavailable or not allowed on this device. To enable purchasing, check Restrictions in the Settings app.", @"OmniUI", OMNI_BUNDLE, @"Purchasing is disabled details");
        NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed purchase alert");
        
        [_buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Disabled", @"OmniUI", OMNI_BUNDLE, @"Button is disabled due to purchase restrictions") forState:UIControlStateDisabled];
        
        UIAlertView *cannotPurchaseAlert = [[UIAlertView alloc] initWithTitle:purchasingDisabledTitle message:purchasingDisabledDetails delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil];
        [cannotPurchaseAlert show];
    }
}

- (void)dealloc;
{
    if (_storeObserver != nil) {
        _storeObserver.delegate = nil;
        [self.paymentQueue removeTransactionObserver:_storeObserver];
    }

    [_request cancel];
}

- (void)showPurchasedText:(NSString *)aProductID;
{
    [_spinner stopAnimating];
    [_request cancel];
    _request = nil;

    if (aProductID == nil)
        return;

    self.hasPurchased = YES;

    [_buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Purchased. Thank you!", @"OmniUI", OMNI_BUNDLE, @"Buy button thank you message") forState:UIControlStateNormal];
    [_buyButton setEnabled:NO];
    _buyButton.tintColor = [self.view.tintColor colorWithAlphaComponent:0.5];
    
    NSString *purchase = NSLocalizedStringFromTableInBundle(@"%@ Purchased", @"OmniUI", OMNI_BUNDLE, @"title for successful in app purchase");
    self.navigationItem.title = [NSString stringWithFormat:purchase, [[OUIAppController controller] sheetTitleForInAppStoreProductIdentifier:aProductID]];
    
    [_featureWebView loadRequest:[NSURLRequest requestWithURL:[[OUIAppController controller] purchasedDescriptionURLForProductIdentifier:aProductID]]];
}

- (void)requestProductData;
{
    [_spinner startAnimating];

    OBASSERT(_request);
    [_request start];
}

- (NSString *)_selectedSKU;
{
    NSInteger selectedSegmentIndex = _pricingOptionsSegmentedControl.selectedSegmentIndex;
    if (selectedSegmentIndex == -1)
        return nil;

    NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:_productIdentifier];
    return pricingOptionSKUs[_pricingOptionsSegmentedControl.selectedSegmentIndex];
}

- (SKProduct *)_selectedPurchaseProduct;
{
    NSString *selectedSKU = [self _selectedSKU];
    return _productForSKU[selectedSKU];
}

- (NSString *)_localizedPriceStringForProduct:(SKProduct *)product;
{
    NSNumberFormatter *priceFormatter = [[NSNumberFormatter alloc] init];
    [priceFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    [priceFormatter setLocale:product.priceLocale];
    NSString *localizedPrice = [priceFormatter stringForObjectValue:product.price];
    return localizedPrice;
}

- (void)_refreshPricingOptions;
{
    NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:_productIdentifier];
    NSString *priceOptionFormat = NSLocalizedStringFromTableInBundle(@"%@ %@", @"OmniUI", OMNI_BUNDLE, @"In App Store pricing option format");

    NSUInteger skuIndex = 0;
    for (NSString *SKU in pricingOptionSKUs) {
        SKProduct *purchaseProduct = _productForSKU[SKU];
        if (purchaseProduct != nil) {
            NSString *localizedPrice = [self _localizedPriceStringForProduct:purchaseProduct];
            [_pricingOptionsSegmentedControl setTitle:[NSString stringWithFormat:priceOptionFormat, localizedPrice, purchaseProduct.localizedTitle] forSegmentAtIndex:skuIndex];
            [_pricingOptionsSegmentedControl setEnabled:YES forSegmentAtIndex:skuIndex];
        } else {
            [_pricingOptionsSegmentedControl setTitle:@"" forSegmentAtIndex:skuIndex];
            [_pricingOptionsSegmentedControl setEnabled:NO forSegmentAtIndex:skuIndex];
        }
        skuIndex++;
    }

    [self updateSelectedPricingOption:nil];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response;
{
    NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:_productIdentifier];
    for (NSString *invalidIdentifier in response.invalidProductIdentifiers) {
        if ([pricingOptionSKUs containsObject:invalidIdentifier]) {
            [self disableStoreInteractionWithBusyIndicator:NO];
            [self _showError];
            return;
        } else {
            OBASSERT_NOT_REACHED("received strange response from app store");
        }
    }
    
    for (SKProduct *product in response.products) {
        _productForSKU[product.productIdentifier] = product;
    }

    [_spinner stopAnimating];
    _restoreButton.enabled = YES;

    [self _refreshPricingOptions];
}

- (void)request:(SKRequest *)aRequest didFailWithError:(NSError *)error;
{
    OBASSERT(_request == aRequest);

    NSLog(@"%@: StoreKit request failed: %@", OBShortObjectDescription(self), [error toPropertyList]);

    [self disableStoreInteractionWithBusyIndicator:NO];
    [self _showError];
}

- (IBAction)updateSelectedPricingOption:(id)sender;
{
    SKProduct *purchaseProduct = [self _selectedPurchaseProduct];
    NSString *buyButtonTitle;
    BOOL buyButtonEnabled;

    if (purchaseProduct != nil) {
        _pricingOptionDescriptionLabel.text = [[OUIAppController controller] descriptionForPricingOptionSKU:[self _selectedSKU]];

        NSString *localizedPrice = [self _localizedPriceStringForProduct:purchaseProduct];
        NSString *localizedPriceFormat = NSLocalizedStringFromTableInBundle(@"Buy %@", @"OmniUI", OMNI_BUNDLE, @"'Buy' button title format. The currency symbol will be provided at run time.");
        buyButtonTitle = [NSString stringWithFormat:localizedPriceFormat, localizedPrice];
        buyButtonEnabled = _restoreButton.enabled;
    } else {
        _pricingOptionDescriptionLabel.text = @"";

        buyButtonTitle = NSLocalizedStringFromTableInBundle(@"Buy", @"OmniUI", OMNI_BUNDLE, @"Disabled 'Buy' button title string");
        buyButtonEnabled = NO;
    }

    [UIView performWithoutAnimation:^{ // Disable animation so the button doesn't draw its old title at its new size (sometimes with ellipses!)
        [_buyButton setTitle:buyButtonTitle forState:UIControlStateNormal];
        [_buyButton layoutIfNeeded];
    }];

    _buyButton.enabled = buyButtonEnabled;
    _buyButton.tintColor = buyButtonEnabled ? self.view.tintColor : [self.view.tintColor colorWithAlphaComponent:0.5];
}

- (IBAction)purchase:(id)sender;
{
    // NSString *verifyTitle = NSLocalizedStringFromTableInBundle(@"Verify", @"OmniUI", OMNI_BUNDLE, @"in app purchase verify button title");
    NSString *selectedSKU = [self _selectedSKU];

    [[OUIAppController controller] validateEligibilityForPricingOptionSKU:selectedSKU completion:^(BOOL isValidated) {
        if (isValidated) {
            [self _validatedPurchase];
        }
    }];
}

- (void)_validatedPurchase;
{
    SKProduct *purchaseProduct = [self _selectedPurchaseProduct];
    if (purchaseProduct) {
        SKPayment *payment = [SKPayment paymentWithProduct:purchaseProduct];
        [self.paymentQueue addPayment:payment];
        [self disableStoreInteractionWithBusyIndicator:NO];
    } else {
        [self _showError];
    }
}

- (IBAction)restore:(id)sender;
{
    [self disableStoreInteractionWithBusyIndicator:YES];
    [self.paymentQueue restoreCompletedTransactions];
}

- (IBAction)done:(id)sender;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)resetPurchasedFlag:(id)sender;
{
    OUIAppController *appDelegate = [OUIAppController controller];
    [appDelegate removePurchasedProductFromKeychain:_productIdentifier];
}

- (void)disableStoreInteractionWithBusyIndicator:(BOOL)isBusy;
{
    _pricingOptionsSegmentedControl.enabled = NO;
    _restoreButton.enabled = NO;
    _buyButton.enabled = NO;
    UIColor *disabledTintColor = [self.view.tintColor colorWithAlphaComponent:0.5];
    _restoreButton.tintColor = disabledTintColor;
    _buyButton.tintColor = disabledTintColor;

    if (isBusy)
        [_spinner startAnimating];
    else
        [_spinner stopAnimating];
}

- (void)enableStoreInteraction;
{
    _pricingOptionsSegmentedControl.enabled = YES;
    _restoreButton.enabled = YES;
    _buyButton.enabled = YES;
    UIColor *enabledTintColor = self.view.tintColor;
    _restoreButton.tintColor = enabledTintColor;
    _buyButton.tintColor = enabledTintColor;

    [_spinner stopAnimating];
}

- (void)updateUIForProductIdentifier:(NSString *)aProductID;
{
    NSString *purchase = NSLocalizedStringFromTableInBundle(@"Purchase %@", @"OmniUI", OMNI_BUNDLE, @"title for successful in app purchase");
    self.navigationItem.title = [NSString stringWithFormat:purchase, [[OUIAppController controller] sheetTitleForInAppStoreProductIdentifier:aProductID]];
    [_featureWebView loadRequest:[NSURLRequest requestWithURL:[[OUIAppController controller] descriptionURLForProductIdentifier:_productIdentifier]]];

    [self _refreshPricingOptions];
}

- (void)_showError;
{
    NSString *storeErrorAlertTitle = NSLocalizedStringFromTableInBundle(@"Error Loading Store", @"OmniUI", OMNI_BUNDLE, @"Alert title for error loading product information");
    NSString *storeErrorAlertDescription = NSLocalizedStringFromTableInBundle(@"There was an error loading information from the App Store", @"OmniUI", OMNI_BUNDLE, @"Alert description for error loading product information");
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed purchase alert");
    
    [_buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Error", @"OmniUI", OMNI_BUNDLE, @"In app Buy button error title") forState:UIControlStateDisabled];

    UIAlertView *cannotPurchaseAlert = [[UIAlertView alloc] initWithTitle:storeErrorAlertTitle message:storeErrorAlertDescription delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil];
    [cannotPurchaseAlert show];
}

- (void)setProductIdentifier:(NSString *)aProductID;
{
    _productIdentifier = aProductID;
    
    OBASSERT([[[OUIAppController controller] inAppPurchaseIdentifiers] containsObject:_productIdentifier]);
    NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:_productIdentifier];
    _request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:pricingOptionSKUs]];
    _request.delegate = self;
    
    [self updateUIForProductIdentifier:_productIdentifier];
}

// OUIInAppStoreObserver delegate
- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue transactionsFailed:(NSArray *)failedTransactions;
{
    NSString *message = [[failedTransactions valueForKeyPath:@"error.localizedDescription"] componentsJoinedByString:@"\n"];
    
    NSLog(@"%@", message);
    NSString *purchaseFailedString = NSLocalizedStringFromTableInBundle(@"Purchase Failed", @"OmniUI", OMNI_BUNDLE, @"Purchase failed alert title");
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed purchase alert");
    
    UIAlertView *transactionFailedAlert = [[UIAlertView alloc] initWithTitle:purchaseFailedString message:message delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil, nil];
    [transactionFailedAlert show];
    
    [self enableStoreInteraction];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue;
{
    if (!self.hasPurchased) {
        NSString *noPurchasesFoundTitle = NSLocalizedStringFromTableInBundle(@"Restore Complete", @"OmniUI", OMNI_BUNDLE, @"No purchases found title");
        NSString *noPurchasesFoundMessageFormat = NSLocalizedStringFromTableInBundle(@"All purchases for your current App Store account have been restored, but %@ wasn't one of those purchases.", @"OmniUI", OMNI_BUNDLE, @"No purchases found message format");
        NSString *noPurchasesFoundMessage = [NSString stringWithFormat:noPurchasesFoundMessageFormat, [[OUIAppController controller] sheetTitleForInAppStoreProductIdentifier:_productIdentifier]];
        NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss alert");

        UIAlertView *transactionFailedAlert = [[UIAlertView alloc] initWithTitle:noPurchasesFoundTitle message:noPurchasesFoundMessage delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil, nil];
        [transactionFailedAlert show];
        
        [self enableStoreInteraction];
    }
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error;
{
    NSLog(@"%@", error);
    NSString *restoreFailedString = NSLocalizedStringFromTableInBundle(@"Restore Failed", @"OmniUI", OMNI_BUNDLE, @"Restore failed alert title");
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed restore alert");
    
    UIAlertView *transactionFailedAlert = [[UIAlertView alloc] initWithTitle:restoreFailedString message:[error localizedDescription] delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil, nil];
    [transactionFailedAlert show];
    
    [self enableStoreInteraction];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue successfullyPurchasedSKU:(NSString *)pricingSKU;
{
    if (_productForSKU[pricingSKU] == nil)
        return; // We don't know this SKU

    // They've purchased one of the SKUs for our products. (Note that SKProduct.productIdentifier is the identifier for a single SKU, while our productIdentifier represents multiple SKUs that have the same effect.)
    [self showPurchasedText:_productIdentifier];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue successfullyRestoredSKU:(NSString *)pricingSKU;
{
    if (_productForSKU[pricingSKU] == nil)
        return; // We don't know this SKU

    // They've purchased one of the SKUs for our products. (Note that SKProduct.productIdentifier is the identifier for a single SKU, while our productIdentifier represents multiple SKUs that have the same effect.)
    [self showPurchasedText:_productIdentifier];
}

@end
