// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIToolbarViewControllerBackgroundView.h"

#import "OUIToolbarViewController.h"
#import "OUIToolbarViewControllerToolbar.h"

RCS_ID("$Id$");

static const CGFloat kToolbarHeight = 44;

@implementation OUIToolbarViewControllerBackgroundView

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    CGRect bounds = self.bounds;
    
    self.autoresizesSubviews = YES;
    
    [self setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    
    _toolbar = [[OUIToolbarViewControllerToolbar alloc] initWithFrame:CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds), CGRectGetWidth(bounds), kToolbarHeight)];
    _toolbar.barStyle = UIBarStyleBlack;
    [_toolbar setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin];
    [self addSubview:_toolbar];
    
    _contentView = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds) + kToolbarHeight, CGRectGetWidth(bounds), CGRectGetHeight(bounds) - kToolbarHeight)];
    [_contentView setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [self addSubview:_contentView];
    
    return self;
}

- (void)dealloc;
{
    [_toolbar release];
    [_contentView release];
    [super dealloc];
}

@synthesize toolbar = _toolbar;
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

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
    CGRect bounds = self.bounds;
    
    CGRect contentFrame;
    
    if (_toolbar.hidden) {
        // Position the toolbar above our top edge, making it slide up if we are animating.
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

