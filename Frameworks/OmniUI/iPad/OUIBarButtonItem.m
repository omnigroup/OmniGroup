// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIBarButtonItem.h>

#import <OmniUI/OUIToolbarButton.h>
#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$");

// We don't implement this, but UIBarButtonItem doesn't declare that is does (though it really does). If UIBarButtonItem doesn't implement coder later, then our subclass method will never get called and we'll never fail on the call to super.
@interface UIBarButtonItem (NSCoding) <NSCoding>
@end

@interface OUIBarButtonItem ()
- (void)_buttonAction:(id)sender;
@end

@implementation OUIBarButtonItem

+ (id)spacerWithWidth:(CGFloat)width;
{
    UIBarButtonItem *spacer = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:NULL] autorelease];
    spacer.width = width;
    return spacer;
}

+ (Class)buttonClass;
{
    return [OUIToolbarButton class];
}

// Sadly we can't query the normal UIBarButtonItem for its localized titles. It just reports nil. Thanks guys!
static NSString *_titleForItemStyle(UIBarButtonSystemItem itemStyle)
{
    switch (itemStyle) {
        case UIBarButtonSystemItemDone:
            return NSLocalizedStringFromTableInBundle(@"Done", @"OmniUI", OMNI_BUNDLE, @"toolbar item title");
        case UIBarButtonSystemItemEdit:
            return NSLocalizedStringFromTableInBundle(@"Edit", @"OmniUI", OMNI_BUNDLE, @"toolbar item title");
        case UIBarButtonSystemItemCancel:
            return NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"toolbar item title");
        default:
            OBASSERT_NOT_REACHED("Unhandled item style");
            return nil;
    }
}

+ (NSSet *)possibleTitlesForEditBarButtonItems;
{
    static NSSet *editTitles = nil;
    
    if (!editTitles) {
        NSMutableSet *titles = [NSMutableSet set];
        
        // Might need to split this up into Edit+Done and Edit+Cancel if one string is excessively long in a localization
        [titles addObject:_titleForItemStyle(UIBarButtonSystemItemEdit)];
        [titles addObject:_titleForItemStyle(UIBarButtonSystemItemCancel)];
        [titles addObject:_titleForItemStyle(UIBarButtonSystemItemDone)];
        
        editTitles = [titles copy];
    }
    
    return editTitles;
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
    OUIBarButtonItem *item;
    
    switch (systemItem) {
        case UIBarButtonSystemItemDone: {
            item = [self initWithBackgroundType:OUIBarButtonItemBackgroundTypeBlue image:nil title:NSLocalizedStringFromTableInBundle(@"Done", @"OmniUI", OMNI_BUNDLE, @"toolbar item title") target:target action:action];
            item.possibleTitles = [[self class] possibleTitlesForEditBarButtonItems];
            break;
        }
        case UIBarButtonSystemItemEdit: {
            item = [self initWithBackgroundType:OUIBarButtonItemBackgroundTypeBlack image:nil title:NSLocalizedStringFromTableInBundle(@"Edit", @"OmniUI", OMNI_BUNDLE, @"toolbar item title") target:target action:action];
            item.possibleTitles = [[self class] possibleTitlesForEditBarButtonItems];
            break;
        }
        case UIBarButtonSystemItemCancel: {
            item = [self initWithBackgroundType:OUIBarButtonItemBackgroundTypeBlack image:nil title:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"toolbar item title") target:target action:action];
            item.possibleTitles = [[self class] possibleTitlesForEditBarButtonItems];
            break;
        }
        default:
            OBRejectUnusedImplementation(self, _cmd);
            return nil;
    }

    OUIWithoutAnimating(^{
        [item.button layoutIfNeeded];
    });
    
    return item;
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
    
    OUIWithoutAnimating(^{
        OUIToolbarButton *button = (OUIToolbarButton *)self.customView;
        [button setImage:image forState:UIControlStateNormal];
        [button setTitle:title forState:UIControlStateNormal];
        [button sizeToFit];
        [button layoutIfNeeded];
    });
    
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

- (void)setPossibleTitles:(NSSet *)possibleTitles;
{
    [super setPossibleTitles:possibleTitles];
    
    OUIToolbarButton *button = (OUIToolbarButton *)self.customView;
    [button setPossibleTitles:possibleTitles];
}

#pragma mark -
#pragma mark Private

- (void)_buttonAction:(id)sender;
{
    if (![[UIApplication sharedApplication] sendAction:self.action to:self.target from:self forEvent:nil])
        NSLog(@"Unable to send action %@ from %@ to %@", NSStringFromSelector(self.action), self, self.target);
}

@end
