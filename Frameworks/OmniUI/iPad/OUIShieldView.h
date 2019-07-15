// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

@protocol OUIShieldViewDelegate;

@interface OUIShieldView : UIView 

@property (nonatomic, strong) NSArray *passthroughViews;
@property (nonatomic, weak) id<OUIShieldViewDelegate> delegate;
@property (nonatomic) BOOL useBlur;

/// Setting this flag to YES will always return nil from -hitTest:... to forward the event up the stream. Before that, we check to see if the hit fell within us and if so, we send the -shieldViewWasTouched: delegate message. Setting this flag also makes the passthroughViews array irrelevant.
@property (nonatomic, assign) BOOL shouldForwardAllEvents;

+ (OUIShieldView *)shieldViewWithView:(UIView *)view;

@end

@protocol OUIShieldViewDelegate <NSObject>
- (void)shieldViewWasTouched:(OUIShieldView *)shieldView;
@end
