// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSProgressIndicator.h>

// This class provides the standard Mac "chasing arrows" control, but with a few twists. You can optionally set a target and action, so that something will happen when the control is clicked. Since this is a non-standard behavior, the control will draw a static image when not animating if a target/action is set. If you don't like this, set OAStandardChasingArrowsBehavior to YES in NSUserDefaults. Also, this class is designed to allow for subclasses which provide diferent animations; users can leverage this to easily create "throbber" animations for an app (such as the logo animations in several web browsers). Subclasses wishing to take advantage of this ability should override +preferredSize and +staticImage in addition to -drawRect:. 

@interface OAChasingArrowsProgressIndicator : NSProgressIndicator
{
    BOOL animating;
    unsigned int counter;
    
    id nonretainedTarget;
    SEL action;
}

// API
+ (NSSize)minSize;
+ (NSSize)maxSize;
+ (NSSize)preferredSize;
    // 16 pixels square, but this could be changed by a subclass.
+ (NSImage *)staticImage;
    // called when somebody wants to display a static image of what this class of progressIndicator might look like while animating. Useful for progressIndicators that disappear when nothing's happening.
- (void)setTarget:(id)aTarget;
- (void)setAction:(SEL)newAction;

@end
