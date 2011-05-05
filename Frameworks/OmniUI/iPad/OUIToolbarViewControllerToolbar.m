// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIToolbarViewControllerToolbar.h"

#import "OUIToolbarViewController-Internal.h"
#import "OUICustomSubclass.h"

RCS_ID("$Id$");

@implementation OUIToolbarViewControllerToolbar

+ (id)allocWithZone:(NSZone *)zone;
{
    OUIAllocateCustomClass; // Used by OmniOutliner's custom toolbar background, though maybe that should move up into OmniUI.
}

// Allow items on the main toolbar to find the inner toolbar controller. UIKit's notion of responder chain starts with the receiving control, NOT the containing window's first responder. Our embedding of one UIViewController inside another means that the inner view controller couldn't easily get toolbar actions. This avoids having to write patches from AppController subclasses.
- (UIResponder *)nextResponder;
{
    UIView *backgroundView = (UIView *)[super nextResponder];
    UIResponder *backgroundViewNextResponder = [backgroundView nextResponder];
    
    // This could be the OUIToolbarViewController's top toolbar or a bottom toolbar embedded inside the inner toolbar already.
    if ([backgroundViewNextResponder isKindOfClass:[OUIToolbarViewController class]]) {
        OUIToolbarViewController *controller = (OUIToolbarViewController *)backgroundViewNextResponder;
    
        OBASSERT(controller.view == backgroundView);
        
        // If we have an inner view controller (and we aren't animating away from it), go to it and skip the background view and the OUIToolbarViewController. They'll get hit after the view of the inner view controller.
        if (!controller.animatingAwayFromCurrentInnerViewController) {
            UIViewController *innerViewController = controller.innerViewController;
            if (innerViewController) {
                OBASSERT([innerViewController nextResponder] == [innerViewController.view superview]);
                OBASSERT([[innerViewController nextResponder] nextResponder] == backgroundView);
                return innerViewController;
            }
        }
    }
    
    return backgroundView; // normal next responder
}

@end


