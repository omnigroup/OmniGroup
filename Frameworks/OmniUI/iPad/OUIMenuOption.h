// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

typedef void (^OUIMenuOptionAction)(void);

@interface OUIMenuOption : NSObject

- initWithTitle:(NSString *)title image:(UIImage *)image action:(OUIMenuOptionAction)action;

@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) UIImage *image;
@property(nonatomic, readonly) OUIMenuOptionAction action;

@end
