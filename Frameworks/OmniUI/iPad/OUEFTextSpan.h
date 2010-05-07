// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OUEFTextRange.h"
#import <OmniUI/OUIInspector.h>

@class OUIEditableFrame;

@interface OUEFTextSpan : OUEFTextRange <OUIColorInspection, OUIFontInspection, OUIParagraphInspection>
{
    OUIEditableFrame *frame;
}

- initWithRange:(NSRange)characterRange generation:(NSUInteger)g editor:(OUIEditableFrame *)ed; // D.I.

@end

