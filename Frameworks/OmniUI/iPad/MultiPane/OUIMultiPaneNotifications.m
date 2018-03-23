// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMultiPaneNotifications.h>

@import OmniBase;

RCS_ID("$Id$")

NSNotificationName const OUIMultiPaneControllerWillHidePaneNotification = @"OUIMultiPaneControllerWillHidePaneNotification";
NSNotificationName const OUIMultiPaneControllerDidHidePaneNotification = @"OUIMultiPaneControllerDidHidePaneNotification";

NSNotificationName const OUIMultiPaneControllerWillShowPaneNotification = @"OUIMultiPaneControllerWillShowPaneNotification";
NSNotificationName const OUIMultiPaneControllerDidShowPaneNotification = @"OUIMultiPaneControllerDidShowPaneNotification";

NSNotificationName const OUIMultiPaneControllerWillNavigateToPaneNotification = @"OUIMultiPaneControllerWillNavigateToPaneNotification";
NSNotificationName const OUIMultiPaneControllerDidNavigateToPaneNotification = @"OUIMultiPaneControllerDidNavigateToPaneNotification";

NSNotificationName const OUIMultiPaneControllerWillPresentPaneNotification = @"OUIMultiPaneControllerWillPresentPaneNotification";

NSString * const OUIMultiPaneControllerPaneLocationUserInfoKey = @"OUIMultiPaneControllerPaneLocationUserInfoKey"; // NSNumber representing rawValue of the OUIMultiPaneLocation
