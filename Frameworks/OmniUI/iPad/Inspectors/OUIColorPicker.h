// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@class OUIInspectorSelectionValue;

@interface OUIColorPicker : UIViewController
{
@private
    CGFloat _originalHeight;
    OUIInspectorSelectionValue *_selectionValue;
}

@property(readonly) CGFloat height;
@property(retain,nonatomic) OUIInspectorSelectionValue *selectionValue;

- (void)becameCurrentColorPicker;

@end
