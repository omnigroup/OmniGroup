// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUEFTextRange.h>

#import <OmniUI/OUIInspector.h>

@class OUIEditableFrame;

// Represents a text span for the inspector system. This does not conform to OUIColorInspection since we want to be able to set multiple color attributes (foreground/background).
@interface OUEFTextSpan : OUEFTextRange <OUIColorInspection, OUIFontInspection, OUIParagraphInspection>
{
@private
    OUIEditableFrame *frame;
}

- initWithRange:(NSRange)characterRange generation:(NSUInteger)g editor:(OUIEditableFrame *)ed; // D.I.

@property(readonly,nonatomic) OUIEditableFrame *frame;

@end

