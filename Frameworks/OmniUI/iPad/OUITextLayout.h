// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <CoreText/CTFramesetter.h>
#import <CoreText/CTFont.h>

@interface OUITextLayout : OFObject
{
@private
    CTFrameRef _frame;
    CGSize _layoutSize;
    CGRect _usedSize;
}

- initWithAttributedString:(CFAttributedStringRef)attributedString constraints:(CGSize)constraints;

@property(readonly) CGSize usedSize;

- (void)drawInContext:(CGContextRef)ctx;

@end

//extern CGSize OUITextLayoutMeasureSize(CTFrameRef frame);
CGRect OUITextLayoutMeasureFrame(CTFrameRef frame, BOOL includeTrailingWhitespace);
//extern CGPoint OUITextLayoutFrameOrigin(CTFrameRef frame);
//extern void OUITextLayoutDrawFrame(CGContextRef ctx, CTFrameRef frame);
extern void OUITextLayoutFixupParagraphStyles(NSMutableAttributedString *content);

extern CTFontRef OUIGlobalDefaultFont(void);
// extern CTParagraphStyleRef OUIGlobalDefaultParagraphStyle(void);

