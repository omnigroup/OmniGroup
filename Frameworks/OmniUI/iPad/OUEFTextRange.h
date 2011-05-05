// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITextInput.h>

@class OUEFTextPosition;

@interface OUEFTextRange : UITextRange <NSCopying>
{
@protected
    // We could simply store a pair of indices here, but we'll have to alloc+init those text positions someday, so might as well do it up-front
    OUEFTextPosition *start, *end;
}

- initWithStart:(OUEFTextPosition *)st end:(OUEFTextPosition *)en; // D.I.
- initWithRange:(NSRange)characterRange generation:(NSUInteger)g;
- (NSRange)range;
- (OUEFTextRange *)rangeIncludingPosition:(OUEFTextPosition *)p;
- (BOOL)includesPosition:(OUEFTextPosition *)p;

- (BOOL)isEqualToRange:(OUEFTextRange *)otherRange;

@end
