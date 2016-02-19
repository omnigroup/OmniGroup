// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@interface OUIUndoIndicator : UIViewController

- initWithParentView:(UIView *)view;

@property(nonatomic,assign) NSUInteger groupingLevel;
@property(nonatomic,assign) BOOL hasUnsavedChanges;
@property(nonatomic,assign) BOOL undoIsEnabled;
@property(nonatomic,assign) CGFloat frameYOffset;   // for apps that have a toolbar

@end
