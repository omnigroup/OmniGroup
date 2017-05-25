// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

// These notifications only post when the pane involved is embeded

extern NSNotificationName const OUIMultiPaneControllerWillHidePaneNotification;
extern NSNotificationName const OUIMultiPaneControllerWillShowPaneNotification;
extern NSNotificationName const OUIMultiPaneControllerDidHidePaneNotification;
extern NSNotificationName const OUIMultiPaneControllerDidShowPaneNotification;

// I would love for the will/did hide/show notifications above to cover willPresent also, but they currently do not. Perhaps in the future we can colapse this, but that would require uses of these to not care about the difference between the view controller being a child view controller or a presentation. I can't guarantee that right now.

extern NSNotificationName const OUIMultiPaneControllerWillPresentPaneNotification;

extern NSString * const OUIMultiPaneControllerPaneLocationUserInfoKey;
