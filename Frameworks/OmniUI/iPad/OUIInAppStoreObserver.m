// Copyright 2010-2013 The Omni Group. All rights reserved.
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
    NSArray *inAppPurchaseIdentifiers = [appDelegate inAppPurchaseIdentifiers];
    NSMutableArray *failedTransactions = [NSMutableArray array];
    
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStatePurchased:
            {
                NSString *productIdentifier = transaction.payment.productIdentifier;
                if ([inAppPurchaseIdentifiers containsObject:productIdentifier]) {
                    if ([appDelegate addImportUnlockedFlagToKeychain:productIdentifier]) {
                        [self.delegate storeObserver:self paymentQueue:queue successfullyPurchasedProduct:productIdentifier];
                        [appDelegate didUnlockInAppPurchase:productIdentifier];
                        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                    }
                }
                break;
            }
            case SKPaymentTransactionStateRestored:
            {
                NSString *productIdentifier = transaction.payment.productIdentifier;
                if ([appDelegate addImportUnlockedFlagToKeychain:productIdentifier]) {
                    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                    [self.delegate storeObserver:self paymentQueue:queue successfullyRestoredProduct:productIdentifier];
                    [appDelegate didUnlockInAppPurchase:productIdentifier];
                }
                
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
        [self.delegate storeObserver:self paymentQueue:queue transactionsFailed:failedTransactions];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    [self.delegate storeObserver:self paymentQueue:queue restoreCompletedTransactionsFailedWithError:error];
}


@end
