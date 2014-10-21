// Copyright 2010-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorUpdateReason.h>
#import <UIKit/UINibDeclarations.h>

@class OUIInspector, OUIInspectorPane, OUIStackedSlicesInspectorPane;


typedef NS_ENUM(NSInteger, OUIInspectorSliceGroupPosition) {
    OUIInspectorSliceGroupPositionNone = 0,
    OUIInspectorSliceGroupPositionFirst = 1,
    OUIInspectorSliceGroupPositionCenter = 2,
    OUIInspectorSliceGroupPositionLast = 3,
    OUIInspectorSliceGroupPositionAlone = 4,
};


@interface OUIInspectorSlice : UIViewController

+ (instancetype)slice;

+ (UIEdgeInsets)sliceAlignmentInsets; // Default alignment insets for a slice
+ (UIColor *)sliceBackgroundColor; // Default color for the slice background
+ (UIColor *)sliceSeparatorColor; // Default color for slice separators
+ (CGFloat)paddingBetweenSliceGroups; // The space to leave between groups of inspector slices.

@property(readonly,nonatomic) OUIStackedSlicesInspectorPane *containingPane; // Set by the containing inspector pane
@property(readonly,nonatomic) OUIInspector *inspector;
@property(nonatomic,assign) UIEdgeInsets alignmentInsets;
@property(nonatomic,assign) OUIInspectorSliceGroupPosition groupPosition;
@property(nonatomic,copy) UIColor *separatorColor;
@property(nonatomic,readonly) BOOL includesInspectorSliceGroupSpacerOnTop;
@property(nonatomic,readonly) BOOL includesInspectorSliceGroupSpacerOnBottom;
@property(nonatomic,readonly) UIView *sliceBackgroundView;
- (UIView *)makeSliceBackgroundView; // You should not call this directly, but subclasses can override it if they want a custom slice background view or if they don't want/need one at all.

+ (void)configureTableViewBackground:(UITableView *)tableView;
- (void)configureTableViewBackground:(UITableView *)tableView;

// Methods used in OUIStackSlicesInspector layout to determine how to space slices
- (CGFloat)paddingToInspectorTop; // For the top slice
- (CGFloat)paddingToInspectorBottom; // For the bottom slice
- (CGFloat)paddingToPreviousSlice:(OUIInspectorSlice *)previousSlice remainingHeight:(CGFloat)remainingHeight;
- (CGFloat)paddingToInspectorLeft;
- (CGFloat)paddingToInspectorRight;
- (CGFloat)topInsetFromSliceBackgroundView; // Subclass if you need to add padding between the top of the content view and the top of the background view, or if you need to prevent the top border of the background view from being exposed above the content view.
- (CGFloat)bottomInsetFromSliceBackgroundView; // Subclass if you need to add padding between the top of the content view and the top of the background view, or if you need to prevent the top border of the background view from being exposed above the content view.
- (CGFloat)minimumHeightForWidth:(CGFloat)width; // The minimum height the slice can have. Defaults to kOUIInspectorWellHeight for height-sizeable views, or the view's current height for non-sizeable views.

- (void)sizeChanged;

@property(strong,nonatomic) IBOutlet OUIInspectorPane *detailPane;
- (IBAction)showDetails:(id)sender;

- (BOOL)isAppropriateForInspectorPane:(OUIStackedSlicesInspectorPane *)containingPane; // Override if you don't want to appear in certain panes
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
