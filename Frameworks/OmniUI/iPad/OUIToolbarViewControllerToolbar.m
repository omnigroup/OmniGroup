// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIToolbarViewControllerToolbar.h"

#import "OUIToolbarViewController-Internal.h"

RCS_ID("$Id$");

@implementation OUIToolbarViewControllerToolbar

// Allow items on the main toolbar to find the inner toolbar controller. UIKit's notion of responder chain starts with the receiving control, NOT the containing window's first responder. Our embedding of one UIViewController inside another means that the inner view controller couldn't easily get toolbar actions. This avoids having to write patches from AppController subclasses.
- (UIResponder *)nextResponder;
{
    UIView *backgroundView = (UIView *)[super nextResponder];
    OUIToolbarViewController *controller = (OUIToolbarViewController *)[backgroundView nextResponder];
    
    OBASSERT([controller isKindOfClass:[OUIToolbarViewController class]]);
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
    
    return backgroundView; // normal next responder
}

@end


