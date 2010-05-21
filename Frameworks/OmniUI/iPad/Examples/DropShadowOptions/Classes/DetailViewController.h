//
//  DetailViewController.h
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 4/2/10.
//  Copyright The Omni Group 2010. All rights reserved.
//

#import <UIKit/UIKit.h>

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
