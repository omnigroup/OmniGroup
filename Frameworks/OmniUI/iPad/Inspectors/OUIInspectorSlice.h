// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIViewController.h>
#import <OmniUI/OUIInspectorUpdateReason.h>
#import <UIKit/UINibDeclarations.h>

@class OUIInspector, OUIInspectorPane, OUIStackedSlicesInspectorPane;

@interface OUIInspectorSlice : OUIViewController
{
@private
    OUIInspectorPane *_detailPane;
}

+ (instancetype)slice;

@property(readonly,nonatomic) OUIStackedSlicesInspectorPane *containingPane; // Set by the containing inspector pane
@property(readonly,nonatomic) OUIInspector *inspector;

+ (void)configureTableViewBackground:(UITableView *)tableView;
- (void)configureTableViewBackground:(UITableView *)tableView;

// Methods used in OUIStackSlicesInspector layout to determine how to space slices
- (CGFloat)paddingToInspectorTop; // For the top slice
- (CGFloat)paddingToInspectorBottom; // For the bottom slice
- (CGFloat)paddingToPreviousSlice:(OUIInspectorSlice *)previousSlice remainingHeight:(CGFloat)remainingHeight;
- (CGFloat)paddingToInspectorSides; // Left/right
- (CGFloat)minimumHeightForWidth:(CGFloat)width; // The minimum height the slice can have. Defaults to kOUIInspectorWellHeight for height-sizeable views, or the view's current height for non-sizeable views.

- (void)sizeChanged;

@property(retain,nonatomic) IBOutlet OUIInspectorPane *detailPane;
- (IBAction)showDetails:(id)sender;

- (BOOL)isAppropriateForInspectedObjects:(NSArray *)objects; // shouldn't be subclassed
@property(readonly) NSArray *appropriateObjectsForInspection; // filtered version of the inspector's inspectedObjects
#ifdef NS_BLOCKS_AVAILABLE
- (void)eachAppropriateObjectForInspection:(void (^)(id obj))action;
#endif

- (BOOL)isAppropriateForInspectedObject:(id)object; // must be subclassed
- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason; // should be subclassed

- (void)inspectorWillShow:(OUIInspector *)inspector;
- (void)containingPaneDidLayout; // For subclasses.

- (NSNumber *)singleSelectedValueForCGFloatSelector:(SEL)sel;
- (NSNumber *)singleSelectedValueForIntegerSelector:(SEL)sel;
- (NSValue *)singleSelectedValueForCGPointSelector:(SEL)sel;

@end
