// Copyright 2005-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniAppKit/OAToolbarWindowController.h>

@class NSNotification;

@interface OAToolbarWindowController (OIExtensions)

// Actions
- (IBAction)toggleFrontColorPanel:(id)sender;

// Toolbar notifications
- (void)toolbarWillAddItem:(NSNotification *)notification;
- (void)toolbarDidRemoveItem:(NSNotification *)notification;

@end

