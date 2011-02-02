// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIBarButtonItem.h>

#import <OmniUI/OUIToolbarButton.h>

RCS_ID("$Id$");

// We don't implement this, but UIBarButtonItem doesn't declare that is does (though it really does). If UIBarButtonItem doesn't implement coder later, then our subclass method will never get called and we'll never fail on the call to super.
@interface UIBarButtonItem (NSCoding) <NSCoding>
@end

@interface OUIBarButtonItem ()
- (void)_buttonAction:(id)sender;
@end

@implementation OUIBarButtonItem

+ (Class)buttonClass;
{
    return [OUIToolbarButton class];
}

static OUIBarButtonItemBackgroundType _backgroundTypeForStyle(UIBarButtonItemStyle style)
{
    switch (style) {
        case UIBarButtonItemStylePlain:
            return OUIBarButtonItemBackgroundTypeNone;
        case UIBarButtonItemStyleDone:
            return OUIBarButtonItemBackgroundTypeBlue;
        case UIBarButtonItemStyleBordered:
        default:
            return OUIBarButtonItemBackgroundTypeBlack;
    }
}

- (id)initWithImage:(UIImage *)image style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action;
{
    OUIBarButtonItemBackgroundType backgroundType = _backgroundTypeForStyle(style);
    
    OUIBarButtonItem *item = [self initWithBackgroundType:backgroundType image:image title:nil target:target action:action];
    
    if (style == UIBarButtonItemStylePlain)
        item.button.showsTouchWhenHighlighted = YES;
    
    return item;
}

- (id)initWithTitle:(NSString *)title style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action;
{
    OUIBarButtonItemBackgroundType backgroundType;
    
    if (style == UIBarButtonItemStyleDone)
        backgroundType = OUIBarButtonItemBackgroundTypeBlue;
    else if (style == UIBarButtonItemStyleBordered)
        backgroundType = OUIBarButtonItemBackgroundTypeBlack;
    else {
        // Deal with plain text items here?
        OBRejectUnusedImplementation(self, _cmd);
    }
    
    return [self initWithBackgroundType:backgroundType image:nil title:title target:target action:action];
}

- (id)initWithBarButtonSystemItem:(UIBarButtonSystemItem)systemItem target:(id)target action:(SEL)action;
{
    switch (systemItem) {
        case UIBarButtonSystemItemDone:
            return [self initWithBackgroundType:OUIBarButtonItemBackgroundTypeBlue image:nil title:NSLocalizedStringFromTableInBundle(@"Done", @"OmniUI", OMNI_BUNDLE, @"toolbar item title") target:target action:action];
        case UIBarButtonSystemItemEdit:
            return [self initWithBackgroundType:OUIBarButtonItemBackgroundTypeBlack image:nil title:NSLocalizedStringFromTableInBundle(@"Edit", @"OmniUI", OMNI_BUNDLE, @"toolbar item title") target:target action:action];
        case UIBarButtonSystemItemCancel:
            return [self initWithBackgroundType:OUIBarButtonItemBackgroundTypeBlack image:nil title:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"toolbar item title") target:target action:action];
        default:
            OBRejectUnusedImplementation(self, _cmd);
            return nil;
    }
}

- (id)initWithCustomView:(UIView *)customView;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

static void _commonInit(OUIBarButtonItem *self, OUIBarButtonItemBackgroundType backgroundType)
{
    Class buttonClass = [[self class] buttonClass];
    OBASSERT(OBClassIsSubclassOfClass(buttonClass, [OUIToolbarButton class]));
    
    OUIToolbarButton *button = [[buttonClass alloc] init];
    [button sizeToFit];
    self.customView = button;
    [button release];
    
    [button addTarget:self action:@selector(_buttonAction:) forControlEvents:UIControlEventTouchUpInside];
    
    [button configureForBackgroundType:backgroundType];
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    _commonInit(self, OUIBarButtonItemBackgroundTypeBlack);
    return self;
}

- init;
{
    return [self initWithBackgroundType:OUIBarButtonItemBackgroundTypeBlack image:nil title:nil target:nil action:NULL];
}

- initWithBackgroundType:(OUIBarButtonItemBackgroundType)backgroundType image:(UIImage *)image title:(NSString *)title target:(id)target action:(SEL)action;
{
    if (!(self = [super init]))
        return nil;
    _commonInit(self, backgroundType);
    
    OUIToolbarButton *button = (OUIToolbarButton *)self.customView;
    [button setImage:image forState:UIControlStateNormal];
    [button setTitle:title forState:UIControlStateNormal];
    [button sizeToFit];
    [button layoutIfNeeded];
    
    self.target = target;
    self.action = action;
    
    return self;
}

- (OUIToolbarButton *)button;
{
    return (OUIToolbarButton *)self.customView;
}

- (void)setNormalBackgroundImage:(UIImage *)image;
{
    OUIToolbarButton *button = (OUIToolbarButton *)self.customView;
    [button setNormalBackgroundImage:image];
}

- (void)setHighlightedBackgroundImage:(UIImage *)image;
{
    OUIToolbarButton *button = (OUIToolbarButton *)self.customView;
    [button setHighlightedBackgroundImage:image];
}

#pragma mark -
#pragma mark Private

- (void)_buttonAction:(id)sender;
{
    if (![[UIApplication sharedApplication] sendAction:self.action to:self.target from:self forEvent:nil])
        NSLog(@"Unable to send action %@ from %@ to %@", NSStringFromSelector(self.action), self, self.target);
}

@end
