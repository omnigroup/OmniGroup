// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIMainViewControllerBackgroundView.h"

#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIMainViewController.h>

RCS_ID("$Id$");

static const CGFloat kToolbarHeight = 44;

@implementation OUIMainViewControllerBackgroundView

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    CGRect bounds = self.bounds;
    
    self.autoresizesSubviews = YES;
    
    [self setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    
    _contentView = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds) + kToolbarHeight, CGRectGetWidth(bounds), CGRectGetHeight(bounds) - kToolbarHeight)];
    [_contentView setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [self addSubview:_contentView];
    
    return self;
}


@synthesize toolbar = _toolbar;
- (void)setToolbar:(UIToolbar *)toolbar;
{
    if (_toolbar == toolbar)
        return;
    
    if (_toolbar) {
        OBASSERT(_toolbar.superview == self);
        [_toolbar removeFromSuperview];
    }
    
    _toolbar = toolbar;
    
    if (toolbar != nil) {
        OBASSERT(toolbar.superview == nil);
        [toolbar setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin];
        OUIWithoutAnimating(^{
            CGRect toolbarFrame = toolbar.frame;
            toolbarFrame.size.width = CGRectGetWidth(_contentView.bounds);
            toolbar.frame = toolbarFrame;
            [toolbar layoutIfNeeded];
        });
        [self addSubview:toolbar];
    }
    
    [self setNeedsLayout];
}

@synthesize contentView = _contentView;

@synthesize avoidedBottomHeight = _avoidedBottomHeight;
- (void)setAvoidedBottomHeight:(CGFloat)avoidedBottomHeight;
{
    OBPRECONDITION(avoidedBottomHeight >= 0);
    
    if (_avoidedBottomHeight == avoidedBottomHeight)
        return;
    
    _avoidedBottomHeight = avoidedBottomHeight;
    [self setNeedsLayout];
}

- (CGRect)contentViewFullScreenBounds;
{
    CGRect _fullScreenBounds = CGRectMake(CGRectGetMinX(self.bounds), CGRectGetMinY(self.bounds) + kToolbarHeight, CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds) - kToolbarHeight);
    return _fullScreenBounds;
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
    CGRect bounds = self.bounds;
    
    CGRect contentFrame;
    
    if (!_toolbar || _toolbar.hidden) {
        // Position any toolbar above our top edge, making it slide up if we are animating.
        _toolbar.frame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds) - kToolbarHeight, CGRectGetWidth(bounds), kToolbarHeight);

        // Take up the rest with the content (possibly avoiding the keyboard).
        contentFrame = bounds;
    } else {
        _toolbar.frame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds), CGRectGetWidth(bounds), kToolbarHeight);
        contentFrame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds) + kToolbarHeight, CGRectGetWidth(bounds), CGRectGetHeight(bounds) - kToolbarHeight);
    }

    contentFrame.size.height -= _avoidedBottomHeight;
    OBASSERT(contentFrame.size.height > 0); // Keyboard should never be that big.
    
    _contentView.frame = contentFrame;
}

@end

