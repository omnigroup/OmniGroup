// Copyright 2011, 2013-2014 Omni Development, Inc. All rights reserved.
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

@property (nonatomic, strong) IBOutlet UIWebView *featureWebView;
@property (nonatomic, strong) IBOutlet UISegmentedControl *pricingOptionsSegmentedControl;
@property (nonatomic, strong) IBOutlet UILabel *pricingOptionDescriptionLabel;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic, strong) IBOutlet UIButton *buyButton;
@property (nonatomic, strong) IBOutlet UIButton *restoreButton;

- (id)initWithProductIdentifier:(NSString *)aProductID;

- (IBAction)updateSelectedPricingOption:(id)sender;
- (IBAction)purchase:(id)sender;
- (IBAction)restore:(id)sender;
- (IBAction)done:(id)sender;

@end
