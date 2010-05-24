//
//  ShadowDemo.h
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 4/2/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//

#import <UIKit/UIKit.h>


@interface ShadowDemo : UIView
{
    BOOL _usingTimer;
}

- (NSString *)name;

@property(nonatomic,assign) BOOL usingTimer;

@end
