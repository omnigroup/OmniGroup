// Copyright 2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <StoreKit/SKProductsRequest.h>

#import <OmniUI/OUIInAppStoreObserver.h>

@class SKProduct;

@interface OUIInAppStoreViewController : UIViewController <SKProductsRequestDelegate, OUIInAppStoreObserverDelegate>

@property (nonatomic,strong) SKProductsRequest *request;
@property (nonatomic,strong) SKProduct *purchaseProduct;
@property (nonatomic,strong) UIBarButtonItem *restoreButton;
@property (nonatomic,strong) OUIInAppStoreObserver *storeObserver;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *leftMarginConstraint;
@property (nonatomic,strong) IBOutlet UIImageView *featureImageWell;
@property (nonatomic,strong) IBOutlet UITextView *featureDescriptionTextView;
@property (nonatomic,strong) IBOutlet UILabel *featureTitleLabel;
@property (nonatomic,strong) IBOutlet UILabel *featureSubtitleLabel;
@property (nonatomic,strong) IBOutlet UIButton *buyButton;
@property (nonatomic,strong) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic,strong) NSString *productIdentifier;

- (id)initWithProductIdentifier:(NSString *)aProductID;

- (IBAction)purchase:(id)sender;
- (IBAction)restore:(id)sender;
- (IBAction)done:(id)sender;
- (void)disableStoreInteraction;
- (void)enableStoreInteraction;
- (void)showPurchasedText:(NSString *)aProductID;

- (void)updateUIForProductIdentifier:(NSString *)aProductID;

@end
