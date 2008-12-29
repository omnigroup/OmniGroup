// Copyright 2005-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSEvent.h>

@interface NSEvent (OAExtensions)

- (NSString *)charactersWithModifiers:(unsigned int)modifierFlags;
// This returns what the current key event's key code would have returned if the passed in modifiers had been pressed.
// This does not correctly handle dead key processing from previous events however the returned value may be empty if this would be a dead key itself.
@end
