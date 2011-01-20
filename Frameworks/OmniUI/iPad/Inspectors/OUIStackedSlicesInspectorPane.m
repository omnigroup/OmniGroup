// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorBackgroundView.h>

RCS_ID("$Id$");

@interface OUIStackedSlicesInspectorPaneContentView : OUIInspectorBackgroundView
{
@private
    CGFloat _topEdgePadding;
    NSArray *_slices;
}
@property(nonatomic,assign) CGFloat topEdgePadding;
@property(nonatomic,copy) NSArray *slices;
@property(nonatomic,readonly) CGFloat contentHeightForViewInPopover;
@end

@implementation OUIStackedSlicesInspectorPaneContentView

- (void)dealloc;
{
    [_slices release];
    [super dealloc];
}

@synthesize topEdgePadding = _topEdgePadding;
- (void)setTopEdgePadding:(CGFloat)topEdgePadding;
{
    if (_topEdgePadding == topEdgePadding)
        return;
    _topEdgePadding = topEdgePadding;
    
    [self setNeedsLayout];
}

@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices;
{
    if (OFISEQUAL(_slices, slices))
        return;
    
    [_slices release];
    _slices = [slices copy];
    
    [self setNeedsLayout];
}

static const CGFloat kSliceSpacing = 5; // minimum space; each slice may have more space built into its xib based on its layout.

- (CGFloat)contentHeightForViewInPopover;
{
    // Must mirror -layoutSubviews;
    CGFloat totalHeight = _topEdgePadding;
    
    BOOL firstSlice = YES;
    for (OUIInspectorSlice *slice in _slices) {
        // Don't fiddle with slices that have been stolen by embedding inspectors (OmniGraffle).
        UIView *sliceView = slice.view;
        if (sliceView.superview != self)
            continue;
        
        if (!firstSlice)
            totalHeight += kSliceSpacing;
        else
            firstSlice = NO;
        
        totalHeight += CGRectGetHeight(sliceView.frame);
    }
    
    return totalHeight;
}

- (void)layoutSubviews;
{
    // OUIInspectorBackgroundView adjusts its gradient here.
    [super layoutSubviews];
    
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat yOffset = CGRectGetMinY(bounds);
    
    BOOL firstSlice = YES;
    
    // Spacing between the header of the popover and the first slice (our slice nibs have their content jammed to the top, typically).
    yOffset += _topEdgePadding;
    
    for (OUIInspectorSlice *slice in _slices) {
        // Don't fiddle with slices that have been stolen by embedding inspectors (OmniGraffle).
        UIView *sliceView = slice.view;
        if (sliceView.superview != self)
            continue;
        
        if (!firstSlice)
            yOffset += kSliceSpacing;
        else
            firstSlice = NO;
        
        CGFloat sliceHeight = CGRectGetHeight(sliceView.frame);
        sliceView.frame = CGRectMake(CGRectGetMinX(bounds), yOffset, width, sliceHeight);
        yOffset += sliceHeight;
    }
    
    if (CGRectGetHeight(bounds) >= yOffset) {
        // Have been resized by UIPopoverController yet
        for (OUIInspectorSlice *slice in _slices) {
            // Don't fiddle with slices that have been stolen by embedding inspectors (OmniGraffle).
            UIView *sliceView = slice.view;
            if (sliceView.superview != self)
                continue;
        }
    }
}

@end

@implementation OUIStackedSlicesInspectorPane

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    // Spacing between the header of the popover and the first slice (our slice nibs have their content jammed to the top, typically).
    _topEdgePadding += 2*kSliceSpacing;
    
    return self;
}

- (void)dealloc;
{
    [_slices release];
    [super dealloc];
}

@synthesize topEdgePadding = _topEdgePadding;
- (void)setTopEdgePadding:(CGFloat)topEdgePadding;
{
    if (_topEdgePadding == topEdgePadding)
        return;
    _topEdgePadding = topEdgePadding;
    
    if ([self isViewLoaded]) {
        OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;
        view.topEdgePadding = _topEdgePadding;
    }
}

@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices;
{
    if (OFISEQUAL(_slices, slices))
        return;
    
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;

    // TODO: Might want an 'animate' variant later.
    for (OUIInspectorSlice *slice in _slices) {
        if ([slice isViewLoaded] && slice.view.superview == view) {
            [slice.view removeFromSuperview]; // Only remove it if it is loaded and wasn't stolen by an embedding inspector (OmniGraffle).
        }
        slice.containingPane = nil;
    }

    [_slices release];
    _slices = [[NSArray alloc] initWithArray:slices];

    for (OUIInspectorSlice *slice in _slices) {
        slice.containingPane = self;
        
        // Add this once up front, but only if an embedding inspector hasn't stolen it from us (OmniGraffle). Not pretty, but that's how it is right now.
        if (slice.view.superview == nil)
            [view addSubview:slice.view];
    }
    
    view.slices = slices;
    
    [self inspectorSizeChanged];
}

- (void)inspectorSizeChanged;
{
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.view;
    self.contentSizeForViewInPopover = CGSizeMake(view.bounds.size.width, view.contentHeightForViewInPopover);
}

#pragma mark -
#pragma mark OUIInspectorPane subclass

- (void)updateInterfaceFromInspectedObjects;
{
    [super updateInterfaceFromInspectedObjects];
    
    [_slices makeObjectsPerformSelector:_cmd];
}

#pragma mark -
#pragma mark UIViewController

- (void)loadView;
{
    OUIStackedSlicesInspectorPaneContentView *view = [[OUIStackedSlicesInspectorPaneContentView alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 16)];
    
    view.topEdgePadding = _topEdgePadding;
    
    self.view = view;
    [view release];
}

@end
