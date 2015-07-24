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
        labelColor = [UIColor colorWithWhite:0.4f alpha:1.0f];
        smallFont = [UIFont systemFontOfSize:12];
    });
    
    
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:text];
    [attributedString addAttribute:NSForegroundColorAttributeName value:labelColor range:NSMakeRange(0, text.length)];
    [attributedString addAttribute:NSFontAttributeName value:smallFont range:NSMakeRange(0, text.length)];
    
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.attributedText = attributedString;
    [label sizeToFit];
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    UIVisualEffectView *labelVisualEffecView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    labelVisualEffecView.translatesAutoresizingMaskIntoConstraints = NO;
    labelVisualEffecView.clipsToBounds = YES;
    labelVisualEffecView.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    labelVisualEffecView.layer.borderWidth = 1.0;
    labelVisualEffecView.layer.cornerRadius = 6.0;
    
    [labelVisualEffecView.contentView addSubview:label];
    
    NSDictionary *views = @{@"label": label};
    NSDictionary *metrics = @{@"horizontalPadding": @(16), @"verticalPadding": @(12)};
    NSMutableArray *constraints = [NSMutableArray array];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-horizontalPadding-[label]-horizontalPadding-|" options:0 metrics:metrics views:views]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-verticalPadding-[label]-verticalPadding-|" options:0 metrics:metrics views:views]];
    [NSLayoutConstraint activateConstraints:constraints];

    return labelVisualEffecView;
}

@end
