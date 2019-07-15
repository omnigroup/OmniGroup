// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>

@class OUIInspectorTextWell, OUIInspectorStepperButton;

@interface DocumentContentsZoomInspectorSlice : OUIInspectorSlice

@property(nonatomic,retain) IBOutlet OUIInspectorStepperButton *zoomDecreaseStepperButton;
@property(nonatomic,retain) IBOutlet OUIInspectorStepperButton *zoomIncreaseStepperButton;
@property(nonatomic,retain) IBOutlet OUIInspectorTextWell *zoomTextWell;

- (IBAction)zoomDecrease:(id)sender;
- (IBAction)zoomIncrease:(id)sender;

@end
