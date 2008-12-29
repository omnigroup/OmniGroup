// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OADataSourceTableColumn.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OADataSourceTableColumn.m 68913 2005-10-03 19:36:19Z kc $");

@implementation OADataSourceTableColumn

- (id)dataCellForRow:(int)row;
{
    // Can't cache whether the data source implementes the extra data source method since table columns don't get notified of data source changes.  Instead, just assume that the data source implements it (otherwise, how would we get one of these?).

    // Doesn't default to [self dataCell] since otherwise the data source can't easily kill cells.
    // The dataSource can just return [tableColumn dataCell] if it wants.
    NSTableView *tableView = [self tableView];

    return [[tableView dataSource] tableView:tableView column:self dataCellForRow:row];
}

@end
