// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIToolbarTitleButton.h>

RCS_ID("$Id$");

@implementation OUIToolbarTitleButton

#pragma mark -
#pragma mark UIButton subclass

- (CGRect)titleRectForContentRect:(CGRect)contentRect;
{
    CGRect originalTitleRect = [super titleRectForContentRect:contentRect];
    CGRect titleRect = originalTitleRect;
    titleRect.origin.x = CGRectGetMinX(contentRect);
    return titleRect;
}

- (CGRect)imageRectForContentRect:(CGRect)contentRect;
{
    CGRect originalImageRect = [super imageRectForContentRect:contentRect];
    CGRect imageRect = originalImageRect;
    imageRect.origin.x = CGRectGetMaxX(contentRect) - imageRect.size.width;
    return imageRect;
}

@end
