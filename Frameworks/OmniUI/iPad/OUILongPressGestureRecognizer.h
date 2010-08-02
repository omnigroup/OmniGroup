//
//  OUILongPressGestureRecognizer.h
//  GesturePlayground
//
//  Created by Robin Stewart on 7/26/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIGestureRecognizerSubclass.h>


@interface OUILongPressGestureRecognizer : UILongPressGestureRecognizer
{
    CGFloat hysteresisDistance;
    BOOL overcameHysteresis;
    
    CGPoint firstTouchPoint;
    CGPoint lastTouchPoint;
}

@property (nonatomic) CGFloat hysteresisDistance;
@property (readonly, nonatomic) BOOL overcameHysteresis;

- (void)resetHysteresis;

@end
