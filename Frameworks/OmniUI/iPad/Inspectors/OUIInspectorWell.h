// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreGraphics/CGContext.h>
#import <Foundation/NSObject.h>

extern void OUIInspectorWellAddPath(CGContextRef ctx, CGRect frame, BOOL rounded);
extern void OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect frame, BOOL rounded);
extern void OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect frame, BOOL rounded);
extern CGRect OUIInspectorWellInnerRect(CGRect frame);
extern CGColorRef OUIInspectorWellBorderColor(void);
extern void OUIInspectorWellStrokePathWithBorderColor(CGContextRef ctx);
