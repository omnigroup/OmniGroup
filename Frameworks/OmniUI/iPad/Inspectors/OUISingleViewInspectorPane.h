// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorPane.h>

@interface OUISingleViewInspectorPane : OUIInspectorPane

// For cases where you have a set of options in a table view and don't want it to be scrollable. Call this from -viewDidLoad.
- (void)adjustSizeToExactlyFitTableView:(UITableView *)tableView;

@end
