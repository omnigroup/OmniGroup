// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInAppStoreObserver.h>

#import <OmniUI/OUIAppController+InAppStore.h>
#import <OmniUI/OUIInAppStoreViewController.h>
#import <StoreKit/StoreKit.h>

RCS_ID("$Id$");

@implementation OUIInAppStoreObserver

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    OUIAppController *appDelegate = [OUIAppController controller];
    
    NSArray *productIdentifiers = [appDelegate inAppPurchaseIdentifiers];
    NSMutableDictionary *productIdentifierForSKU = [NSMutableDictionary dictionary];
    for (NSString *productIdentifier in productIdentifiers) {
        NSArray *pricingOptionSKUs = [[OUIAppController controller] pricingOptionSKUsForProductIdentifier:productIdentifier];
        for (NSString *pricingOptionSKU in pricingOptionSKUs) {
            productIdentifierForSKU[pricingOptionSKU] = productIdentifier;
        }
    }
    
    id <OUIInAppStoreObserverDelegate> myDelegate = self.delegate; // Strong reference to our delegate for the duration of this method

    NSMutableArray *failedTransactions = [NSMutableArray array];
    
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStatePurchased:
            case SKPaymentTransactionStateRestored:
            {
                NSString *purchasedSKU = transaction.payment.productIdentifier;
                NSString *productIdentifier = productIdentifierForSKU[purchasedSKU];

                if (![productIdentifiers containsObject:productIdentifier])
                    continue;

                if (![appDelegate addPurchasedProductToKeychain:productIdentifier])
                    continue;

                [appDelegate didUnlockInAppPurchase:productIdentifier];

                if (transaction.transactionState == SKPaymentTransactionStatePurchased)
                    [myDelegate storeObserver:self paymentQueue:queue successfullyPurchasedSKU:purchasedSKU];
                else
                    [myDelegate storeObserver:self paymentQueue:queue successfullyRestoredSKU:purchasedSKU];

                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];

                break;
            }

            case SKPaymentTransactionStateFailed:
            {
                [failedTransactions addObject:transaction];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            }

            default:
                break;
        }
    }
    
    if (failedTransactions.count)
        [myDelegate storeObserver:self paymentQueue:queue transactionsFailed:failedTransactions];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue;
{
    [self.delegate storeObserver:self paymentQueueRestoreCompletedTransactionsFinished:queue];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    [self.delegate storeObserver:self paymentQueue:queue restoreCompletedTransactionsFailedWithError:error];
}


@end
