// Copyright 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@class UIBarButtonItem;
@class OUIMenuOption, OUIMenuController;

@protocol OUIMenuControllerDelegate <NSObject>
- (NSArray *)menuControllerOptions:(OUIMenuController *)menu;
@end

@interface OUIMenuController : UIViewController

+ (OUIMenuOption *)menuOptionWithFirstResponderSelector:(SEL)selector title:(NSString *)title image:(UIImage *)image;

- initWithDelegate:(id <OUIMenuControllerDelegate>)delegate;
- initWithOptions:(NSArray *)options;

- (void)showMenuFromBarItem:(UIBarButtonItem *)barItem;

@end
