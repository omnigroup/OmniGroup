// Copyright 2002-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OASwitcherBarMatrix.h 68913 2005-10-03 19:36:19Z kc $

#import <AppKit/NSMatrix.h>

@interface OASwitcherBarMatrix : NSMatrix
{
    struct {
        unsigned int registeredForKeyNotifications: 1;
    } switcherBarFlags;
}

// Implements a control like the view switcher toolbar item or the "Import/Oraganize/Edit/etc." bar in iPhoto. Looks best if you keep it to a single row.

@end
