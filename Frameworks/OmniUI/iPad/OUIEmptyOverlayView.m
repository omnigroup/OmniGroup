// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEmptyOverlayView.h>
#import <OmniAppKit/OAAppearanceColors.h>

RCS_ID(")$Id$");

@interface OUIEmptyOverlayView ()

- (IBAction)_buttonTapped:(id)sender;

@property (nonatomic, retain) IBOutlet UILabel *messageLabel;
@property (nonatomic, retain) IBOutlet UIButton *button;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *buttonWidth;

@end

@implementation OUIEmptyOverlayView
{
    void (^_action)(void);
    BOOL _permanentConstraintsAdded;
}

+ (instancetype)overlayViewWithMessage:(NSString *)message buttonTitle:(NSString *)buttonTitle action:(void (^)(void))action;
{
    return [self overlayViewWithMessage:message buttonTitle:buttonTitle customFontColor:[OAAppearanceDefaultColors appearance].textColorForDarkBackgroundColor action:action];
}

+ (instancetype)overlayViewWithMessage:(NSString *)message buttonTitle:(NSString *)buttonTitle customFontColor:(UIColor *)customFontColor action:(void (^)(void))action;
{
    static UINib *nib;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        nib = [UINib nibWithNibName:@"OUIEmptyOverlayView" bundle:OMNI_BUNDLE];
    });
    
    OBASSERT_NOTNULL(nib);
    NSArray *topLevelObjects = [nib instantiateWithOwner:nil options:nil];
    
    OBASSERT(topLevelObjects.count == 1);
    OBASSERT([topLevelObjects[0] isKindOfClass:[self class]]);
    
    OUIEmptyOverlayView *view = topLevelObjects[0];
    [view _setUpWithMessage:message buttonTitle:buttonTitle customFontColor:customFontColor action:action];
    
    return view;
}

// if you don't want a custom font color, pass nil.
- (void)_setUpWithMessage:(NSString *)message buttonTitle:(NSString *)buttonTitle customFontColor:(UIColor *)customFontColor action:(void (^)(void))action;
{
    OBASSERT_NOTNULL(_messageLabel);
    _messageLabel.text = message;
    if (customFontColor) {
        _messageLabel.textColor = customFontColor;
    } else {
        
    }
    
    OBASSERT_NOTNULL(_button);
    [_button setTitle:buttonTitle forState:UIControlStateNormal];
    _button.titleLabel.textAlignment = NSTextAlignmentCenter;
    if (customFontColor) {
        _button.tintColor = customFontColor;
    }
    self.buttonWidth = [NSLayoutConstraint constraintWithItem:_button
                                                    attribute:NSLayoutAttributeWidth
                                                    relatedBy:NSLayoutRelationEqual
                                                       toItem:nil
                                                    attribute:NSLayoutAttributeNotAnAttribute
                                                   multiplier:1.0f
                                                     constant:[self preferredLayoutWidth]];
    [self addConstraint:self.buttonWidth];
    
    
#if 0 && defined(DEBUG_jake)
    self.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.4];
    _messageLabel.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.4];
    _button.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.4];
#endif
    
    _action = action;
}

- (CGFloat)preferredLayoutWidth{
    return self.bounds.size.width * [OAAppearance appearance].emptyOverlayViewLabelMaxWidthRatio;
}

- (void)layoutSubviews;
{
    // -layoutSubviews should be called after our superview has been laid out (and our own frame has therefore been determined and set).
    _messageLabel.preferredMaxLayoutWidth = [self preferredLayoutWidth];
    if (self.buttonWidth.constant != _messageLabel.preferredMaxLayoutWidth) {
        self.buttonWidth.constant = _messageLabel.preferredMaxLayoutWidth;
    }
    [super layoutSubviews];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self)
        return nil;
    else
        return hitView;
}

#pragma mark - Helpers
- (void)_buttonTapped:(id)sender;
{
    if (_action) {
        _action();
    }
}

@end
