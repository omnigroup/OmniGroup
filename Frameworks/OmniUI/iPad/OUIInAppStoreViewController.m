// Copyright 2010-2013 The Omni Group. All rights reserved.
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

@end

@implementation OUIInAppStoreViewController
{
    BOOL _addedTopMarginConstraint;
}

@synthesize request;
@synthesize purchaseProduct;
@synthesize buyButton;
@synthesize restoreButton;
@synthesize storeObserver;
@synthesize leftMarginConstraint;
@synthesize featureDescriptionTextView;
@synthesize featureTitleLabel;
@synthesize featureSubtitleLabel;
@synthesize featureImageWell;
@synthesize spinner;
@synthesize productIdentifier;

- (id)initWithProductIdentifier:(NSString *)aProductID;
{
    if (!(self = [super init]))
        return nil;
        
    [self setProductIdentifier:aProductID];
    
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self)
        return nil;
    
    storeObserver = [[OUIInAppStoreObserver alloc] init];
    storeObserver.delegate = self;
    [[SKPaymentQueue defaultQueue] addTransactionObserver:storeObserver];
    
    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(done:)];
    self.navigationItem.leftBarButtonItem = cancel;
    
    restoreButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Restore", @"OmniUI", OMNI_BUNDLE, @"Restore purchases button title") style:UIBarButtonItemStylePlain target:self action:@selector(restore:)];
    [restoreButton setEnabled:NO];
    self.navigationItem.rightBarButtonItem = restoreButton;

    return self;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Loading", @"OmniUI", OMNI_BUNDLE, @"Buy button title while app store is loading") forState:UIControlStateNormal];
    [buyButton addTarget:self action:@selector(purchase:) forControlEvents:UIControlEventTouchUpInside];
    [buyButton setEnabled:NO];
    
    [self updateUIForProductIdentifier:productIdentifier];
    if ([[OUIAppController controller] importIsUnlocked:productIdentifier])
        [self showPurchasedText:productIdentifier];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    if ([[OUIAppController controller] importIsUnlocked:productIdentifier]) {
        [self showPurchasedText:productIdentifier];
    } else if ([SKPaymentQueue canMakePayments]) {
        [self requestProductData];
    } else {
        NSString *purchasingDisabledTitle = NSLocalizedStringFromTableInBundle(@"Purchasing is Disabled", @"OmniUI", OMNI_BUNDLE, @"Purchasing is disabled alert title");
        NSString *purchasingDisabledDetails = NSLocalizedStringFromTableInBundle(@"In-App Purchasing is unavailable or not allowed on this device. To enable purchasing, check Restrictions in the Settings app.", @"OmniUI", OMNI_BUNDLE, @"Purchasing is disabled details");
        NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed purchase alert");
        
        [buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Disabled", @"OmniUI", OMNI_BUNDLE, @"Button is disabled due to purchase restrictions") forState:UIControlStateDisabled];
        
        UIAlertView *cannotPurchaseAlert = [[UIAlertView alloc] initWithTitle:purchasingDisabledTitle message:purchasingDisabledDetails delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil];
        [cannotPurchaseAlert show];
    }
}

- (void)updateViewConstraints;
{
    [super updateViewConstraints];
    
    if (!_addedTopMarginConstraint) {
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:featureImageWell attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.topLayoutGuide attribute:NSLayoutAttributeBottom multiplier:1 constant:self.leftMarginConstraint.constant]];
    }
}

- (void)dealloc;
{
    storeObserver.delegate = nil;
    [self.request cancel];
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:storeObserver];
}

- (void)showPurchasedText:(NSString *)aProductID;
{
    [spinner stopAnimating];
    [request cancel];
    request = nil;

    [buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Purchased. Thank you!", @"OmniUI", OMNI_BUNDLE, @"Buy button thank you message") forState:UIControlStateNormal];
    [buyButton setEnabled:NO];
    
    [self.navigationItem setRightBarButtonItem:nil];
    
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
    [self.navigationItem setLeftBarButtonItem:doneButton];
    
    NSString *purchase = NSLocalizedStringFromTableInBundle(@"%@ Purchased", @"OmniUI", OMNI_BUNDLE, @"title for successful in app purchase");
    self.navigationItem.title = [NSString stringWithFormat:purchase, [[OUIAppController controller] sheetTitleForInAppStoreProductIdentifier:aProductID]];
}

- (void)requestProductData;
{
    [spinner startAnimating];

#ifdef DEBUG_ryan0
    [self afterDelay:1 performBlock:^{
        if ([[OUIAppController controller] importIsUnlocked:@"com.omnigroup.InAppPurchase.Visio"]) {
            [self showPurchasedText:@"com.omnigroup.InAppPurchase.Visio"];
        } else {
            NSString *localizedPriceString = NSLocalizedStringFromTableInBundle(@"Buy $%@", @"OmniUI", OMNI_BUNDLE, @"'Buy' and a currency symbol for purchase button");
            
            NSString *buyWithPriceString = [NSString stringWithFormat:localizedPriceString, @"1,000,000"];
            [buyButton setTitle:buyWithPriceString forState:UIControlStateNormal];
            [buyButton setEnabled:YES];
            [restoreButton setEnabled:YES];
        }
        
        [spinner stopAnimating];
    }];
    return;
#endif

    OBASSERT(request);
    [request start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response;
{
    for (NSString *invalid in response.invalidProductIdentifiers) {
        if ([productIdentifier isEqualToString:invalid]) {
            [self disableStoreInteraction];
            [self _showError];
            
            [spinner stopAnimating];
            
            return;
        } else {
            OBASSERT_NOT_REACHED("received strange response from app store");
        }
    }
    
    for (SKProduct *product in response.products) {
        if ([productIdentifier isEqualToString:product.productIdentifier]) {
            purchaseProduct = product;
            
            NSNumberFormatter *priceFormatter = [[NSNumberFormatter alloc] init];
            [priceFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
            [priceFormatter setLocale:product.priceLocale];
            NSString *localizedPrice = [priceFormatter stringForObjectValue:purchaseProduct.price];
            
            NSString *localizedPriceString = NSLocalizedStringFromTableInBundle(@"Buy %@", @"OmniUI", OMNI_BUNDLE, @"'Buy' button title format. The currency symbol will be provided at run time.");
            
            NSString *buyWithPriceString = [NSString stringWithFormat:localizedPriceString, localizedPrice];
            [buyButton setTitle:buyWithPriceString forState:UIControlStateNormal];
            [buyButton setEnabled:YES];
            [restoreButton setEnabled:YES];
            
            [spinner stopAnimating];
            
            return;
        } else {
            OBASSERT_NOT_REACHED("received strange response from app store");
        }
    }
}

- (void)request:(SKRequest *)aRequest didFailWithError:(NSError *)error;
{
    OBASSERT(request == aRequest);
    [self disableStoreInteraction];
    [self _showError];
}

- (IBAction)purchase:(id)sender;
{
#ifdef DEBUG_ryan0
    [spinner startAnimating];
    
    [self afterDelay:.5 performBlock:^{
        [[OUIAppController controller] unlockImport:@"com.omnigroup.InAppPurchase.Visio"];
    }];
    
    return;
#endif
    
    if (purchaseProduct) {
        [spinner startAnimating];

        SKPayment *payment = [SKPayment paymentWithProduct:purchaseProduct];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        [self disableStoreInteraction];
    } else {
        [self _showError];
    }
}

- (IBAction)restore:(id)sender;
{
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
    [self disableStoreInteraction];
}

- (IBAction)done:(id)sender;
{
    if ([[[self navigationController] viewControllers] count] && [[[self navigationController] viewControllers] objectAtIndex:0] == self)
        [self dismissViewControllerAnimated:YES completion:nil];
    else
        [[self navigationController] popViewControllerAnimated:YES];
}

- (IBAction)resetPurchasedFlag:(id)sender;
{
    OUIAppController *appDelegate = [OUIAppController controller];
    [appDelegate deleteImportPurchasedFlag:nil];
}

- (void)disableStoreInteraction;
{
    [buyButton setEnabled:NO];
    [restoreButton setEnabled:NO];
}

- (void)enableStoreInteraction;
{
    [buyButton setEnabled:YES];
    [restoreButton setEnabled:YES];
}

- (void)updateUIForProductIdentifier:(NSString *)aProductID;
{
    NSString *purchase = NSLocalizedStringFromTableInBundle(@"Purchase %@", @"OmniUI", OMNI_BUNDLE, @"title for successful in app purchase");
    self.navigationItem.title = [NSString stringWithFormat:purchase, [[OUIAppController controller] sheetTitleForInAppStoreProductIdentifier:aProductID]];
    
    featureTitleLabel.text = [[OUIAppController controller] titleForInAppStoreProductIdentifier:aProductID];
    featureSubtitleLabel.text = [[OUIAppController controller] subtitleForInAppStoreProductIdentifier:aProductID];
    featureDescriptionTextView.text = [[OUIAppController controller] descriptionForInAppStoreProductIdentifier:aProductID];
    featureImageWell.image = [[OUIAppController controller] imageForInAppStoreProductIdentifier:aProductID];
}

- (void)_showError;
{
    NSString *storeErrorAlertTitle = NSLocalizedStringFromTableInBundle(@"Error Loading Store", @"OmniUI", OMNI_BUNDLE, @"Alert title for error loading product information");
    NSString *storeErrorAlertDescription = NSLocalizedStringFromTableInBundle(@"There was an error loading information from the App Store", @"OmniUI", OMNI_BUNDLE, @"Alert description for error loading product information");
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed purchase alert");
    
    [buyButton setTitle:NSLocalizedStringFromTableInBundle(@"Error", @"OmniUI", OMNI_BUNDLE, @"In app Buy button error title") forState:UIControlStateDisabled];

    UIAlertView *cannotPurchaseAlert = [[UIAlertView alloc] initWithTitle:storeErrorAlertTitle message:storeErrorAlertDescription delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil];
    [cannotPurchaseAlert show];
}

- (void)setProductIdentifier:(NSString *)aProductID;
{
    productIdentifier = aProductID;
    
    OBASSERT([[[OUIAppController controller] inAppPurchaseIdentifiers] containsObject:productIdentifier]);
    request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObject:productIdentifier]];
    request.delegate = self;
    
    [self updateUIForProductIdentifier:productIdentifier];
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
    
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error;
{
    if ([error.domain isEqualToString:SKErrorDomain] && error.code == SKErrorPaymentCancelled) {
        [self enableStoreInteraction];
        
        return;
    }
    
    NSLog(@"%@", error);
    NSString *restoreFailedString = NSLocalizedStringFromTableInBundle(@"Restore Failed", @"OmniUI", OMNI_BUNDLE, @"Restore failed alert title");
    NSString *dismissAlertString = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Dismiss failed restore alert");
    
    UIAlertView *transactionFailedAlert = [[UIAlertView alloc] initWithTitle:restoreFailedString message:[error localizedDescription] delegate:nil cancelButtonTitle:dismissAlertString otherButtonTitles:nil, nil];
    [transactionFailedAlert show];
    
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue successfullyPurchasedProduct:(NSString *)purchasedProductIdentifier;
{
    [self showPurchasedText:purchasedProductIdentifier];
}

- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue successfullyRestoredProduct:(NSString *)purchasedProductIdentifier;
{
    [self showPurchasedText:purchasedProductIdentifier];
}

@end
