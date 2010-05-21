//
//  DetailViewController.m
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 4/2/10.
//  Copyright The Omni Group 2010. All rights reserved.
//

#import "DetailViewController.h"
#import "RootViewController.h"

#import "ShadowDemo.h"

#import <OmniBase/assertions.h>
#import <QuartzCore/CATransaction.h>

@interface DetailViewController ()
@property (nonatomic, retain) UIPopoverController *popoverController;
- (void)_startAnimation;
@end


@implementation DetailViewController

- (void)dealloc;
{
    [popoverController release];
    [toolbar release];
    
    [demo release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Properties

@synthesize toolbar, popoverController;

@synthesize demo;
- (void)setDemo:(ShadowDemo *)newDemo;
{
    if (demo == newDemo)
        return;

    [demo removeFromSuperview];
    [demo release];
    
    demo = [newDemo retain];
    [self.view addSubview:demo];
    
    [self _startAnimation];

    [popoverController dismissPopoverAnimated:YES];
}

@synthesize animationType;
- (void)setAnimationType:(AnimationType)newType;
{
    if (animationType == newType)
        return;
    
    animationType = newType;
    //[self _startAnimation]; // Let the current animation finish out first

    [popoverController dismissPopoverAnimated:YES];
}

@synthesize useTimer;
- (void)setUseTimer:(BOOL)flag;
{
    if (useTimer == flag)
        return;
    
    useTimer = flag;
    //[self _startAnimation]; // Let the current animation finish out first
    
    [popoverController dismissPopoverAnimated:YES];
}

#pragma mark -
#pragma mark UISplitViewControllerDelegate

- (void)splitViewController: (UISplitViewController*)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem*)barButtonItem forPopoverController: (UIPopoverController*)pc;
{
    barButtonItem.title = @"Settings";
    NSMutableArray *items = [[toolbar items] mutableCopy];
    [items insertObject:barButtonItem atIndex:0];
    [toolbar setItems:items animated:YES];
    [items release];
    self.popoverController = pc;
}


// Called when the view is shown again in the split view, invalidating the button and popover controller.
- (void)splitViewController: (UISplitViewController*)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem;
{
    NSMutableArray *items = [[toolbar items] mutableCopy];
    [items removeObjectAtIndex:0];
    [toolbar setItems:items animated:YES];
    [items release];
    self.popoverController = nil;
}


#pragma mark -
#pragma mark UIViewController subclass

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    return YES;
}

- (void)viewDidUnload;
{
    [super viewDidUnload];
    
    self.popoverController = nil;
}


#pragma mark -
#pragma mark Private

static const NSTimeInterval AnimationDuration = 1;

- (void)_startAnimation;
{
    // Avoid the toolbar
    CGFloat toolbarMaxY = CGRectGetMaxY(toolbar.frame);
    CGRect bounds = self.view.bounds;
    CGRect demoFrame = CGRectMake(CGRectGetMinX(bounds), toolbarMaxY, CGRectGetWidth(bounds), CGRectGetMaxY(bounds) - toolbarMaxY);
    
    CGRect startFrame, endFrame;
    
    if (animationType == ResizeAnimationType) {
        startFrame = CGRectInset(demoFrame, 20, 20);
        endFrame = CGRectInset(demoFrame, 0.25 * CGRectGetWidth(demoFrame), 0.25 * CGRectGetHeight(demoFrame));
    } else {
        CGRect slideFrame = CGRectInset(demoFrame, 20, 20);
        CGRectDivide(slideFrame, &startFrame, &endFrame, floor(CGRectGetHeight(slideFrame) / 2), CGRectMinYEdge);
        
        // Make sure we aren't doing a subtle resize too if we get an odd height...
        endFrame.size = startFrame.size;
    }
    
    demo.frame = startFrame;
    [demo layoutIfNeeded];
    
    [_timer invalidate];
    [_timer release];
    _timer = nil;
    
    if (useTimer) {
        // The use of timer here isn't intended to suggest that an animation should use a timer for animating. Rather, it simulates user-driven animation due to touch drag events modifying a live interface.
        _timer = [[NSTimer scheduledTimerWithTimeInterval:0/*fast as possible*/ target:self selector:@selector(_timerFired:) userInfo:nil repeats:YES] retain];
        _startFrame = startFrame;
        _endFrame = endFrame;
        _startInterval = [NSDate timeIntervalSinceReferenceDate];
    } else {
        // Not using a repeating animation here so that when we change the type it'll finish up and start the new type w/o mixing the two types.
        [UIView beginAnimations:@"resize up and down" context:NULL];
        [UIView setAnimationDuration:AnimationDuration];
        [UIView setAnimationRepeatAutoreverses:YES];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDidStopSelector:@selector(_demoAnimationDidStop:finished:context:)];
        {
            demo.frame = endFrame;
            
            // Make sure that any subview layout is part of the same animation
            [demo layoutIfNeeded];
        }
        [UIView commitAnimations];
    }
}

- (void)_demoAnimationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    if ([finished boolValue])
        [self _startAnimation];
}

static CGFloat interp(CGFloat a, CGFloat b, CGFloat t)
{
    OBPRECONDITION(t >= 0 && t <= 1);
    return t * a + (1-t) * b;
}

- (void)_timerFired:(NSTimer *)timer;
{
    NSTimeInterval sinceStart = [NSDate timeIntervalSinceReferenceDate] - _startInterval;
    NSTimeInterval t = 0.5 * (cos(AnimationDuration/2*sinceStart * 2*M_PI) + 1);
    
    CGRect frame;
    frame.origin.x = floor(interp(_startFrame.origin.x, _endFrame.origin.x, t));
    frame.origin.y = floor(interp(_startFrame.origin.y, _endFrame.origin.y, t));
    
    if (CGSizeEqualToSize(_startFrame.size, _endFrame.size))
        frame.size = _startFrame.size; // make sure there is no crazy round off
    else {
        frame.size.width = floor(interp(_startFrame.size.width, _endFrame.size.width, t));
        frame.size.height = floor(interp(_startFrame.size.height, _endFrame.size.height, t));
    }
    
    demo.frame = frame;
    [demo layoutIfNeeded];
    
    if (sinceStart > 2 * AnimationDuration) {
        // Restart the animation like our UIView path would, so we can pick up changed parameters
        [self _startAnimation];
    }
}

@end
