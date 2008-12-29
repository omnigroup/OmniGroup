// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSNumberFormatter.h>

@class NSTableColumn;

@interface OAResizingByteFormatter : NSNumberFormatter
{
    NSTableColumn *nonretainedTableColumn;
}

- initWithNonretainedTableColumn:(NSTableColumn *)tableColumn;

@end
