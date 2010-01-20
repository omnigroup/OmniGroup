// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
//  OABoxSeparator.h
//  OmniAppKit
//
// Copyright 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


#import <AppKit/NSBox.h>

// This subclass allows you to choose a color other than black for the separator line.  The default color here is 70% gray (which tends to look a lot better than black).

@interface OABoxSeparator : NSBox
{
    NSColor *lineColor;
}

@property (retain) NSColor *lineColor;

@end
