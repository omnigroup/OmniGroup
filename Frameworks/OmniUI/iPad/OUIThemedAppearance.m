// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIThemedAppearance.h>

RCS_ID("$Id$");

OUIThemedAppearanceTheme const OUIThemedAppearanceThemeUnset = @"OUIThemedAppearanceThemeUnset";

OUIThemedAppearanceTheme _CurrentTheme = @"OUIThemedAppearanceThemeUnset";
static NSMutableDictionary *_AppearanceInstancesByTheme = nil;

@implementation OUIThemedAppearance

+ (void)initialize
{
    OBINITIALIZE;
    
    _AppearanceInstancesByTheme = [NSMutableDictionary dictionary];
}

+ (instancetype)appearance;
{
    OUIThemedAppearance *themedAppearance = _AppearanceInstancesByTheme[[self currentTheme]];
    OBASSERT(themedAppearance != nil);
    return themedAppearance;
}

+ (void)addTheme:(OUIThemedAppearanceTheme)theme withAppearance:(OUIThemedAppearance *)appearance;
{
    OBPRECONDITION(![theme isEqualToString:OUIThemedAppearanceThemeUnset], @"should setCurrentTheme prior to first access");

    _AppearanceInstancesByTheme[theme] = appearance;
}

+ (void)setCurrentTheme:(OUIThemedAppearanceTheme)theme;
{
    if (theme == _CurrentTheme) {
        return;
    }
    
    {
        OUIThemedAppearance *themedAppearance = nil;
        if (![_CurrentTheme isEqualToString:OUIThemedAppearanceThemeUnset]) {
            themedAppearance = _AppearanceInstancesByTheme[_CurrentTheme];
        }
        
        if (themedAppearance != nil) {
            [[NSNotificationCenter defaultCenter] postNotificationName:OAAppearanceValuesWillChangeNotification object:self];
        }
        
        _CurrentTheme = theme;
        
        if (themedAppearance != nil) {
            [[NSNotificationCenter defaultCenter] postNotificationName:OAAppearanceValuesDidChangeNotification object:self];
        }
    }
}

+ (OUIThemedAppearanceTheme)currentTheme;
{
    OBPRECONDITION(![_CurrentTheme isEqualToString:OUIThemedAppearanceThemeUnset], @"should setCurrentTheme prior to first access");
    
    return _CurrentTheme;
}

@end

#pragma mark -

@implementation NSObject (OUIThemedAppearanceClient)

- (void)themedAppearanceDidChangeWithNotification:(NSNotification *)notification;
{
    OBPRECONDITION([self conformsToProtocol:@protocol(OUIThemedAppearanceClient)]);
    Class appearanceClass = notification.object;
    OBASSERT([appearanceClass respondsToSelector:@selector(appearance)]);
    OUIThemedAppearance *appearance = [appearanceClass performSelector:@selector(appearance)];
    [self notifyChildrenThatAppearanceDidChange:appearance];
}

- (void)notifyChildrenThatAppearanceDidChange:(OUIThemedAppearance *)appearance;
{
    // Traverse the client hierarchy depth first beginning with self
    NSMutableArray *clientStack = [NSMutableArray array];
    [clientStack addObject:self];
    do {
        UIView *topClient = clientStack.lastObject;
        OBASSERT([topClient conformsToProtocol:@protocol(OUIThemedAppearanceClient)]);
        
        [clientStack removeLastObject];
        [topClient themedAppearanceDidChange:appearance];
        
        [clientStack addObjectsFromArray:[topClient themedAppearanceChildClients]];
    } while (clientStack.count > 0);
}

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)appearance;
{
    // Empty implementation.
}

@end

#pragma mark -

@implementation UIView (OUIThemedAppearanceClient)

- (NSArray <id<OUIThemedAppearanceClient>> *)themedAppearanceChildClients;
{
    return [self subviews];
}

@end

#pragma mark -

@implementation UIViewController (OUIThemedAppearanceClient)

- (NSArray <id<OUIThemedAppearanceClient>> *)themedAppearanceChildClients;
{
    NSMutableArray *childClients = [[self childViewControllers] mutableCopy];
    
    // -presentedViewController will walk up the receiver's parent hierarchy a bit to find certain presentations. Make sure the thing being presented is coming from self, not a parent, before adding it to the list of children.
    UIViewController *presentedViewController = [self presentedViewController];
    if (presentedViewController != nil && presentedViewController.presentingViewController == self) {
        [childClients addObject:presentedViewController];
    }
    return childClients;
}

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)appearance;
{
    [super themedAppearanceDidChange:appearance];
}

@end

#pragma mark -

@implementation UIPresentationController (OUIThemedAppearanceClient)

- (NSArray <id<OUIThemedAppearanceClient>> *)themedAppearanceChildClients;
{
    return @[];
}

@end

