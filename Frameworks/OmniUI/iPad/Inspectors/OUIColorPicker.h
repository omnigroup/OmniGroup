// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@class OUIInspectorSelectionValue;

typedef enum {
    OUIColorPickerFidelityZero, // can't represent the color at all
    OUIColorPickerFidelityApproximate, // can convert the color to something representable
    OUIColorPickerFidelityExact, // can represent the color exactly
} OUIColorPickerFidelity;

@interface OUIColorPicker : UIViewController
{
@private
    CGFloat _originalHeight;
    OUIInspectorSelectionValue *_selectionValue;
}

@property(readonly) CGFloat height;
@property(retain,nonatomic) OUIInspectorSelectionValue *selectionValue;

- (OUIColorPickerFidelity)fidelityForSelectionValue:(OUIInspectorSelectionValue *)selectionValue;

@end
