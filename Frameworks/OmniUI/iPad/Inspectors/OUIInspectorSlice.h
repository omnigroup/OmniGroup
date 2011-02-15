// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIParentViewController.h>
#import <UIKit/UINibDeclarations.h>

@class OUIInspector, OUIInspectorPane;

@interface OUIInspectorSlice : OUIParentViewController
{
@private
    OUIInspectorPane *_nonretained_containingPane;
    OUIInspectorPane *_detailPane;
}

@property(assign,nonatomic) OUIInspectorPane *containingPane; // Set by the containing inspector pane
@property(readonly,nonatomic) OUIInspector *inspector;

// Methods used in OUIStackSlicesInspector layout to determine how to space slices
- (CGFloat)paddingToInspectorTop; // For the top slice
- (CGFloat)paddingToInspectorBottom; // For the bottom slice
- (CGFloat)paddingToPreviousSlice:(OUIInspectorSlice *)previousSlice;
- (CGFloat)paddingToInspectorSides; // Left/right

@property(retain,nonatomic) IBOutlet OUIInspectorPane *detailPane;
- (IBAction)showDetails:(id)sender;

- (BOOL)isAppropriateForInspectedObjects:(NSSet *)objects; // shouldn't be subclassed
@property(readonly) NSSet *appropriateObjectsForInspection; // filtered version of the inspector's inspectedObjects

- (BOOL)isAppropriateForInspectedObject:(id)object; // must be subclassed
- (void)updateInterfaceFromInspectedObjects; // should be subclassed

- (NSNumber *)singleSelectedValueForCGFloatSelector:(SEL)sel;
- (NSNumber *)singleSelectedValueForIntegerSelector:(SEL)sel;
- (NSValue *)singleSelectedValueForCGPointSelector:(SEL)sel;

@end
