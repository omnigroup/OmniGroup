// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIVisualEffectView-OUIExtensions.h>

RCS_ID("$Id$");

@implementation UIVisualEffectView (OUIExtensions)

+ (instancetype)labelEffectViewWithText:(NSString *)text;
{
    static UIColor *labelColor = nil;
    static UIFont *smallFont = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        labelColor = [[UIColor blackColor] colorWithAlphaComponent:0.7f];
        smallFont = [UIFont systemFontOfSize:12];
    });
    
    // blur
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.60];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.clipsToBounds = YES;
    blurView.layer.borderColor = [[UIColor blackColor] colorWithAlphaComponent:0.4f].CGColor;
    blurView.layer.borderWidth = 1.0;
    blurView.layer.cornerRadius = 6.0;
    
    // label
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:text];
    [attributedString addAttribute:NSForegroundColorAttributeName value:labelColor range:NSMakeRange(0, text.length)];
    [attributedString addAttribute:NSFontAttributeName value:smallFont range:NSMakeRange(0, text.length)];
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.attributedText = attributedString;
    [label sizeToFit];
    
    // add the label to effect view
    [blurView.contentView addSubview:label];
    
    // constraints
    NSDictionary *views = @{@"label" : label};
    NSDictionary *metrics = @{@"horizontalPadding": @(16), @"verticalPadding": @(12)};
    NSMutableArray *constraints = [NSMutableArray array];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-horizontalPadding-[label]-horizontalPadding-|" options:0 metrics:metrics views:views]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-verticalPadding-[label]-verticalPadding-|" options:0 metrics:metrics views:views]];
    [NSLayoutConstraint activateConstraints:constraints];

    return blurView;
}

@end
