// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorValue.h>

@class OUIInspectorSelectionValue, OUIColorInspectorPane;

@protocol OUIColorPickerTarget <NSObject>

- (void)beginChangingColor;
- (void)changeColor:(id <OUIColorValue>)colorValue;
- (void)endChangingColor;

@end

typedef enum {
    OUIColorPickerFidelityZero, // can't represent the color at all
    OUIColorPickerFidelityApproximate, // can convert the color to something representable
    OUIColorPickerFidelityExact, // can represent the color exactly
} OUIColorPickerFidelity;

@interface OUIColorPicker : UIViewController

@property(weak,nonatomic) IBOutlet id <OUIColorPickerTarget> target;

@property(strong,nonatomic) OUIInspectorSelectionValue *selectionValue;

@property(nonatomic,readonly) NSString *identifier;

- (OUIColorPickerFidelity)fidelityForSelectionValue:(OUIInspectorSelectionValue *)selectionValue;

- (void)wasDeselectedInColorInspectorPane:(OUIColorInspectorPane *)pane; // called when the user taps away from this picker to another
- (void)wasSelectedInColorInspectorPane:(OUIColorInspectorPane *)pane; // .. and then this called on the new picker
- (void)scrollToSelectionValueAnimated:(BOOL)animated;

@end
