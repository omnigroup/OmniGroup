// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSPopUpButton.h>

extern NSString *OAContextControlToolTip(void);
extern NSMenu *OAContextControlNoActionsMenu(void);
extern void OAContextControlGetMenu(id delegate, NSControl *control, NSMenu **outMenu, NSView **outTargetView);

@interface NSObject (OAContextControlDelegate)
- (NSMenu *)menuForContextControl:(NSControl *)control;
- (NSView *)targetViewForContextControl:(NSControl *)control;
@end
