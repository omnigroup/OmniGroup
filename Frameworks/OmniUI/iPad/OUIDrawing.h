// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreGraphics/CoreGraphics.h>

@class UIImage, UILabel;

extern UIImage *OUIImageByFlippingHorizontally(UIImage *image);

#ifdef DEBUG
extern void OUILogAncestorViews(UIView *view);
#endif

// For segmented contorls, stepper buttons, etc.
extern void OUIBeginShadowing(CGContextRef ctx);
extern void OUIBeginControlImageShadow(CGContextRef ctx);
extern void OUIEndControlImageShadow(CGContextRef ctx);
extern UIImage *OUIMakeShadowedImage(UIImage *image);

extern void OUISetShadowOnLabel(UILabel *label);
