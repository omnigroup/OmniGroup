//
//  OUIUndoButton.h
//  OmniGraffle-iPad
//
//  Created by Ryan Patrick on 5/24/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//
// $Id$

#import <Foundation/Foundation.h>

@class OUIUndoButtonController;
@interface OUIUndoButton : UIButton {
    OUIUndoButtonController *_buttonController;
}

+ (CGRect)appropriateBounds;
@end
