// Copyright 2004-2005, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSPopUpButton.h>

// As a special case, NSViews in the responder chain can implement -menuForContextControl: and not -targetViewForContextControl: (and they will be used for the view).
@protocol OAContextControlDelegate <NSObject>
- (NSMenu *)menuForContextControl:(NSControl *)control;
- (NSView *)targetViewForContextControl:(NSControl *)control;
@end

extern NSString *OAContextControlToolTip(void);
extern NSMenu *OAContextControlNoActionsMenu(void);
extern void OAContextControlGetMenu(id <OAContextControlDelegate> delegate, NSControl *control, NSMenu **outMenu, NSView **outTargetView);
