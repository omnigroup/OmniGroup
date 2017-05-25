// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniAppKit/OAAppearance.h>

typedef NSString *OUIThemedAppearanceTheme; //NS_EXTENSIBLE_STRING_ENUM;

extern OUIThemedAppearanceTheme const OUIThemedAppearanceThemeUnset;

@interface OUIThemedAppearance : OAAppearance

+ (void)addTheme:(OUIThemedAppearanceTheme)theme withAppearance:(OUIThemedAppearance *)appearance;

+ (void)setCurrentTheme:(OUIThemedAppearanceTheme)theme;
+ (OUIThemedAppearanceTheme)currentTheme;

@end


@protocol OUIThemedAppearanceClient <NSObject>
/// Extracts the object from the given notification. The object must be an instance of OUIThemedAppearance. Invokes notifyViewsThatAppearanceDidChange: on self. Clients can register a view to observe OAAppearanceValuesDidChangeNotification invoking this selector to notify all views in a view hierarchy without each of those views having to register independently for notifications.
- (void)themedAppearanceDidChangeWithNotification:(NSNotification *)notification;

/// Sends themedAppearanceDidChange: to self and all child clients recursively.
- (void)notifyChildrenThatAppearanceDidChange:(OUIThemedAppearance *)appearance;

/// Child clients that should be recursively notified when the current appearance changes.
- (NSArray <id<OUIThemedAppearanceClient>> *)themedAppearanceChildClients;

/// Conforming classes can override as needed. They should call super. We cannot enforce this via NS_REQUIRES_SUPER because this is a protocol.
- (void)themedAppearanceDidChange:(OUIThemedAppearance *)appearance;
@end

/// NSObject implements a subset of OUIThemedAppearanceClient
/// In particular, this is here so that it is always safe to call super from an override of -themedAppearanceDidChange:
@interface NSObject (OUIThemedAppearanceClient)

- (void)themedAppearanceDidChangeWithNotification:(NSNotification *)notification;
- (void)notifyChildrenThatAppearanceDidChange:(OUIThemedAppearance *)appearance;
- (void)themedAppearanceDidChange:(OUIThemedAppearance *)appearance;

@end

/// UIView conforms to OUIThemedAppearanceClient by forwarding appearance notifications to its entire subview hierarchy recursively. Call -notifyChildrenThatAppearanceDidChange: on any UIView to update appearance for the hierarchy rooted at that view.
@interface UIView (OUIThemedAppearanceClient) <OUIThemedAppearanceClient>
@end

/// UIViewController conforms to OUIThemedAppearanceClient by forwarding appearance notifications to any child view controllers and its presented view controller, if there is one. UIViewController does not automatically forward appearance notifications to its view; implement -themedAppearanceDidChange: on a view controller subclass and call -notifyChildrenThatAppearanceDidChange: on a view to push an appearance notification across the controller/view barrier.
@interface UIViewController (OUIThemedAppearanceClient) <OUIThemedAppearanceClient>
@end

#pragma mark -

/// UINavigationController conforms to OUIThemedAppearanceClient.
@interface UINavigationController (OUIThemedAppearanceClient)

// Considers the current navigation stack when updating with the changing appearance
- (void)themedAppearanceDidChange:(OUIThemedAppearance *)appearance;

@end

/// UIPresentationController conforms to OUIThemedAppearanceClient by doing nothing. UIPopoverPresentationController overrides the conformance to update its background color. This conformance is to allow a presentingViewController to call -themedAppearanceDidChange: on behalf of the presentedViewController.
@interface UIPresentationController (OUIThemedAppearanceClient) <OUIThemedAppearanceClient>
@end
