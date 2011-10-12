// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDirectTapGestureRecognizer.h>

#import <UIKit/UIGestureRecognizerSubclass.h>

RCS_ID("$Id$");

static BOOL _failOnIndirectTouch(UIGestureRecognizer *self, NSSet *touches, UIEvent *event)
{
    UIView *directView = self.view;
    UIWindow *directWindow = directView.window;
    
    for (UITouch *touch in touches) {
        CGPoint windowPoint = [touch locationInView:directWindow];
        UIView *hitView = [directWindow hitTest:windowPoint withEvent:event];
        if (hitView != directView) {
            self.state = UIGestureRecognizerStateFailed;
            return YES;
        }
    }
    
    return NO;
}

@implementation OUIDirectTapGestureRecognizer

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    if ([self state] == UIGestureRecognizerStatePossible && CGPointEqualToPoint(_firstTapLocation, CGPointZero))
        _firstTapLocation = [[touches anyObject] locationInView:self.view];
 
    if (_failOnIndirectTouch(self, touches, event))
        return;
    [super touchesBegan:touches withEvent:event];
}

- (void)reset;
{
    _firstTapLocation = CGPointZero;
    
    [super reset];
}

@synthesize firstTapLocation = _firstTapLocation;
@end

@implementation OUIDirectLongPressGestureRecognizer

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    if (_failOnIndirectTouch(self, touches, event))
        return;
    [super touchesBegan:touches withEvent:event];
}

@end
