// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATabViewController.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

#import <OmniAppKit/OATabbedWindowController.h>

RCS_ID("$Id$")


@interface OATabViewController (Private)
@end

@implementation OATabViewController

//
// API
//

- (NSString *)label;
{
    return NSStringFromClass([self class]);
}

- (NSDocument *)document;
{
    return [windowController document];
}

- (void)refreshUserInterface;
{
}

//
// NSNibAwaking informal protocol
//

- (void)awakeFromNib;
{
    if (flags.alreadyAwoke)
        return;
    flags.alreadyAwoke = YES;
}

//
// NSMenuValidation informal protocol
//

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    return YES;
}

//
// OATabViewItemController informal protocol
//

- (void)willSelectInTabView:(NSTabView *)tabView;
{
    [self refreshUserInterface];
}

@end

@implementation OATabViewController (FriendClassesOnly)

- (NSWindow *)scratchWindow;
{
    return scratchWindow;
}

@end

@implementation OATabViewController (Private)
@end
