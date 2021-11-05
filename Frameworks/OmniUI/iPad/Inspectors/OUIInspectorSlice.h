// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIViewController.h>

#import <OmniUI/OUIInspectorUpdateReason.h>
#import <UIKit/UINibDeclarations.h>

@class UITableView;
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
+ (NSDirectionalEdgeInsets)sliceDirectionalLayoutMargins;
+ (UIColor *)sliceSeparatorColor; // Default color for slice separators
+ (CGFloat)paddingBetweenSliceGroups; // The space to leave between groups of inspector slices.

@property(nonatomic, strong) IBOutlet UIView *contentView;

@property(nonatomic, weak) OUIStackedSlicesInspectorPane *containingPane; // Set by the containing inspector pane
@property(readonly,nonatomic) OUIInspector *inspector;
@property(nonatomic,assign) UIEdgeInsets alignmentInsets;
@property(nonatomic,assign) OUIInspectorSliceGroupPosition groupPosition;
@property(nonatomic,copy) UIColor *separatorColor;
@property(nonatomic,readonly) BOOL includesInspectorSliceGroupSpacerOnTop;
@property(nonatomic,readonly) BOOL includesInspectorSliceGroupSpacerOnBottom;
@property(nonatomic,assign) BOOL suppressesTrailingImplicitSeparator;

+ (UIColor *)sliceBackgroundColor;
- (UIColor *)sliceBackgroundColor; // Default color for the slice background

+ (void)configureTableViewBackground:(UITableView *)tableView;
- (void)configureTableViewBackground:(UITableView *)tableView;

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

@property (nonatomic, weak) NSLayoutConstraint *rightMarginLayoutConstraint;
@end

static const CGFloat InspectorFontSize = 17;
