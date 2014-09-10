// Copyright 2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <StoreKit/SKPaymentQueue.h> // SKPaymentTransactionObserver

@class OUIInAppStoreObserver;

@protocol OUIInAppStoreObserverDelegate
- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue transactionsFailed:(NSArray *)failedTransactions;
- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue;
- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error;
- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue successfullyPurchasedSKU:(NSString *)pricingSKU;
- (void)storeObserver:(OUIInAppStoreObserver *)storeObserver paymentQueue:(SKPaymentQueue *)queue successfullyRestoredSKU:(NSString *)pricingSKU;
@end

@interface OUIInAppStoreObserver : NSObject <SKPaymentTransactionObserver>

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions;

@property (readwrite,nonatomic,weak) id<OUIInAppStoreObserverDelegate> delegate;

@end
