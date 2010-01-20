// Copyright 2009-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUTextField.h"

#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OSUTextField

// API
- (BOOL)textView:(NSTextView *)aTextView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex;
{
    id dele = [self delegate];
    if (dele && [dele respondsToSelector:@selector(textView:clickedOnLink:atIndex:)])
        return [dele textView:aTextView clickedOnLink:link atIndex:charIndex];
    else
        return NO;
}

@end

