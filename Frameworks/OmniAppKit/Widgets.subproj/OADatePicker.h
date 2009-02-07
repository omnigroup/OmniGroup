// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSDatePicker.h>

@class /* Foundation */ NSDate;

@interface OADatePicker : NSDatePicker
{
    BOOL _clicked;
    BOOL sentAction;
    NSDate *_lastDate;
    BOOL ignoreNextDateRequest; // <bug://bugs/38625> (Selecting date selects current date first when switching between months, disappears (with some filters) before proper date can be selected)
}

- (void)setClicked:(BOOL)clicked;
- (BOOL)clicked;


- (void)reset;

@end
