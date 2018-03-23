// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIBarButtonItem.h>

#import <OmniUI/OUIAppController.h>
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
    UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:NULL];
    spacer.width = width;
    return spacer;
}

+ (Class)buttonClass;
{
    return [OUIToolbarButton class];
}

// Sadly we can't query the normal UIBarButtonItem for its localized titles. It just reports nil. Thanks guys!
static NSString *_titleForSystemItem(UIBarButtonSystemItem systemItem)
{
    switch (systemItem) {
        case UIBarButtonSystemItemDone:
            return NSLocalizedStringFromTableInBundle(@"Done", @"OmniUI", OMNI_BUNDLE, @"toolbar item title");
        case UIBarButtonSystemItemEdit:
            return NSLocalizedStringFromTableInBundle(@"Edit", @"OmniUI", OMNI_BUNDLE, @"toolbar item title");
        case UIBarButtonSystemItemCancel:
            return NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"toolbar item title");
        default:
            OBASSERT_NOT_REACHED("Unhandled system item");
            return nil;
    }
}

+ (NSSet *)possibleTitlesForEditBarButtonItems;
{
    static NSSet *editTitles = nil;
    
    if (!editTitles) {
        NSMutableSet *titles = [NSMutableSet set];
        
        // Might need to split this up into Edit+Done and Edit+Cancel if one string is excessively long in a localization
        [titles addObject:_titleForSystemItem(UIBarButtonSystemItemEdit)];
        [titles addObject:_titleForSystemItem(UIBarButtonSystemItemCancel)];
        [titles addObject:_titleForSystemItem(UIBarButtonSystemItemDone)];
        
        editTitles = [titles copy];
    }
    
    return editTitles;
}

+ (NSString *)titleForEditButtonBarSystemItem:(UIBarButtonSystemItem)systemItem;
{
    return _titleForSystemItem(systemItem);
}

- (id)initWithImage:(UIImage *)image style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action;
{
    OUIBarButtonItem *item = [self initWithTintColor:nil image:image title:nil target:target action:action];
    
    if (style == UIBarButtonItemStylePlain)
        item.button.showsTouchWhenHighlighted = NO; // iOS 7iffy this thang!
    
    return item;
}

- (id)initWithTitle:(NSString *)title style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action;
{
    return [self initWithTintColor:nil image:nil title:title target:target action:action];
}

- (id)initWithBarButtonSystemItem:(UIBarButtonSystemItem)systemItem target:(id)target action:(SEL)action;
{
    OUIBarButtonItem *item = [self initWithTintColor:nil image:nil title:_titleForSystemItem(systemItem) target:target action:action];
    item.possibleTitles = [[self class] possibleTitlesForEditBarButtonItems];

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

static void _commonInit(OUIBarButtonItem *self, UIColor *tintColor)
{
    Class buttonClass = [[self class] buttonClass];
    OBASSERT(OBClassIsSubclassOfClass(buttonClass, [OUIToolbarButton class]));
    
    OUIToolbarButton *button = [buttonClass buttonWithType:UIButtonTypeSystem];
    [button sizeToFit];
    self.customView = button;
    
    [button addTarget:self action:@selector(_buttonAction:) forControlEvents:UIControlEventTouchUpInside];

    // Don't set a default tint color if the incoming color is nil. We want to allow the containing view hierarchy to control it.
    button.tintColor = tintColor;
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    _commonInit(self, nil);
    return self;
}

- init;
{
   return [self initWithTintColor:nil image:nil title:nil target:nil action:NULL];
}

- initWithTintColor:(UIColor *)tintColor image:(UIImage *)image title:(NSString *)title target:(id)target action:(SEL)action;
{
    if (!(self = [super init]))
        return nil;
    _commonInit(self, tintColor);

    OUIWithoutAnimating(^{
        OUIToolbarButton *button = (OUIToolbarButton *)self.customView;
        [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
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

- (void)setPossibleTitles:(NSSet *)possibleTitles;
{
    [super setPossibleTitles:possibleTitles];
    
    OUIToolbarButton *button = (OUIToolbarButton *)self.customView;
    [button setPossibleTitles:possibleTitles];
}

#pragma mark -
#pragma mark Private

- (void)_buttonAction:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
{
    id target = self.target;
    if (![[UIApplication sharedApplication] sendAction:self.action to:target from:self forEvent:nil])
        NSLog(@"Unable to send action %@ from %@ to %@", NSStringFromSelector(self.action), self, target);
}

@end
