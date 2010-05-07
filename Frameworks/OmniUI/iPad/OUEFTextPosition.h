// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITextInput.h>

// Trivial UITextPosition / UITextRange implementations. We can do better than this?
@interface OUEFTextPosition : UITextPosition <NSCopying>
{
    NSUInteger index;
    NSUInteger generation;
}

- initWithIndex:(NSUInteger)ix;
- (NSComparisonResult)compare:other;
@property (readonly) NSUInteger index;
@property (readwrite) NSUInteger generation;

@end

