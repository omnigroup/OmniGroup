// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

#import <UIKit/UIPopoverController.h>
#import <UIKit/UISplitViewController.h>

@class ShadowDemo;

typedef enum {
    ResizeAnimationType,
    SlideAnimationType,
    AnimationTypeCount,
} AnimationType;

@interface DetailViewController : UIViewController <UIPopoverControllerDelegate, UISplitViewControllerDelegate> {
    
    UIPopoverController *popoverController;
    UIToolbar *toolbar;
    
    ShadowDemo *demo;
    AnimationType animationType;
    BOOL useTimer;
    
    NSTimer *_timer;
    NSTimeInterval _startInterval;
    CGRect _startFrame, _endFrame;
}

@property(nonatomic, retain) IBOutlet UIToolbar *toolbar;

@property(nonatomic,retain) ShadowDemo *demo;
@property(nonatomic,assign) AnimationType animationType;
@property(nonatomic,assign) BOOL useTimer;

@end
