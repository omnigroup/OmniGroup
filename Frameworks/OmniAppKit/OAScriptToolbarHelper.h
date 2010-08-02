// Copyright 2002-2005, 2007-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import "OAToolbarWindowController.h"

@class NSMutableDictionary;
@class OAToolbarItem;

@interface OAScriptToolbarHelper : NSObject <OAToolbarHelper> 
{
    NSMutableDictionary *_pathForItemDictionary;
}

@end

@protocol OAScriptToolbarHelperDelegate
@optional
- (BOOL)scriptToolbarItemShouldExecute:(OAToolbarItem *)item;
- (void)scriptToolbarItemFinishedExecuting:(OAToolbarItem *)item; // might be success, might be failure.
- (NSAppleEventDescriptor *)scriptToolbarItemArguments:(OAToolbarItem *)item; // returns a list of arguments to be passed to the invoked script (by default, a single-item list containing the receiver's window)
@end

@interface OAToolbarWindowController (OAScriptToolbarHelperExtensions) <OAScriptToolbarHelperDelegate>
@end
