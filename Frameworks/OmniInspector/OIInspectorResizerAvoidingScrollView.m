// Copyright 2003-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorResizerAvoidingScrollView.h"
#import "OIInspectorResizer.h"

#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>


RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OIInspectorResizerAvoidingScrollView.m 93428 2007-10-25 16:36:11Z kc $");

@implementation OIInspectorResizerAvoidingScrollView

// NSScrollView subclass

- (void)tile;
{
    [super tile];

    NSScroller *verticalScroller = [self verticalScroller];
    NSRect verticalSliderFrame = [verticalScroller frame];

    NSRect newVerticalSliderFrame, portionOfFrameObscuredByResizer;
    NSDivideRect(verticalSliderFrame, &portionOfFrameObscuredByResizer, &newVerticalSliderFrame, OIInspectorResizerWidth, NSMaxYEdge);

    [verticalScroller setFrame:newVerticalSliderFrame];
}

@end
