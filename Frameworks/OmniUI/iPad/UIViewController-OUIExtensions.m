// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIViewController-OUIExtensions.h>

RCS_ID("$Id$");

@implementation UIViewController (OUIExtensions)

- (BOOL)isDescendant:(OUIViewControllerDescendantType)descendantType ofViewController:(UIViewController *)otherVC;
{
    if ([self isEqual:otherVC])
        return YES;
    
    if (descendantType & OUIViewControllerDescendantTypeChild) {
        if ([self.parentViewController isDescendant:descendantType ofViewController:otherVC])
            return YES;
    }
    
    if (descendantType & OUIViewControllerDescendantTypePresented) {
        if ([self.presentingViewController isDescendant:descendantType ofViewController:otherVC])
            return YES;
    }
    
    return NO;
}

@end
