// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIStackedSlicesInspectorPane.h>

#import <OmniUI/OUIInspectorSliceView.h>

#import <OmniUI/OUIEmptyPaddingInspectorSlice.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorSliceView.h>
#import <OmniUI/OUIMinimalScrollNotifierImplementation.h>
#import <OmniUI/UIViewController-OUIExtensions.h>

#import "OUIParameters.h"

#import "OUIInspectorBackgroundView.h"
#import "OUIInspectorSlice-Internal.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG_curt) && defined(DEBUG)
    #define DEBUG_ANIM(format, ...) NSLog(@"ANIM: " format, ## __VA_ARGS__)
#else
    #define DEBUG_ANIM(format, ...)
#endif


static CGFloat _setSliceSizes(UIView *self, NSArray *_slices, NSSet *slicesToPostponeFrameSetting)
{
    CGFloat yOffset = 0.0;
    CGRect bounds = self.bounds;

    if (!self || [_slices count] == 0)
        return yOffset;
    
    // Spacing between the header of the popover and the first slice (our slice nibs have their content jammed to the top, typically).
    yOffset += [[_slices objectAtIndex:0] paddingToInspectorTop];

    // 1) add up the total height requirements of all paddings and slices that aren't UIViewAutoresizingFlexibleHeight
    OUIInspectorSlice *previousSlice = nil;
    CGFloat totalHeight = yOffset, totalFlexibleSliceMinimumHeight = 0;
    NSMutableSet *resizableSlices = [NSMutableSet set];
    for (OUIInspectorSlice *slice in _slices) {
        // Don't fiddle with slices that have been stolen by embedding inspectors (OmniGraffle).
        UIView *sliceView = slice.view;
        if (sliceView.superview != self)
            continue;
        
        UIView *sliceBackgroundView = slice.sliceBackgroundView;
        OBASSERT_IF(sliceBackgroundView != nil, sliceBackgroundView.superview == self);
        if ((sliceBackgroundView != nil) && [sliceBackgroundView respondsToSelector:@selector(setInspectorSliceGroupPosition:)]) {
            [(id)sliceBackgroundView setInspectorSliceGroupPosition:slice.groupPosition];
        }

        if (previousSlice)
            totalHeight += [slice paddingToPreviousSlice:previousSlice remainingHeight:bounds.size.height - totalHeight];

        CGFloat sliceWidth = CGRectGetWidth(bounds) - [slice paddingToInspectorLeft] - [slice paddingToInspectorRight];
        CGFloat minimumContentHeight = [slice minimumHeightForWidth:sliceWidth];
        CGFloat minimumSliceHeight = minimumContentHeight;
        if (sliceBackgroundView != nil) {
            minimumSliceHeight += slice.topInsetFromSliceBackgroundView + slice.bottomInsetFromSliceBackgroundView;
            minimumSliceHeight = MAX(kOUIInspectorWellHeight, minimumSliceHeight);
        }
        
        if (sliceView.autoresizingMask & UIViewAutoresizingFlexibleHeight) {
            [resizableSlices addObject:slice];
            totalFlexibleSliceMinimumHeight += minimumSliceHeight;
        } else {
            // Otherwise the slice should be a fixed height and we should use it.
            totalHeight += minimumSliceHeight;
            
            // Only height-resizable slices will have their height adjusted below (based on how much space is left). This slice might not be stretchable, but just have a computed height based on contents that changes as its width (for example, OUIInstructionTextInspectorSlice).
            CGRect sliceFrame = sliceView.frame;
            if (sliceFrame.size.height != minimumContentHeight) {
                sliceFrame.size.height = minimumContentHeight;
                sliceView.frame = sliceFrame;
            }
            if (sliceBackgroundView != nil) {
                CGRect sliceBackgroundFrame = slice.sliceBackgroundView.frame;
                if (sliceBackgroundFrame.size.height != minimumSliceHeight) {
                    sliceBackgroundFrame.size.height = minimumSliceHeight;
                    sliceBackgroundView.frame = sliceBackgroundFrame;
                }
            }
        }
        previousSlice = slice;
    }
    totalHeight += [[_slices lastObject] paddingToInspectorBottom];
    
    // 2) set the height of all UIViewAutoresizingFlexibleHeight slice views and set the yOffset of each slice
    CGFloat remainingHeight = bounds.size.height - totalHeight;
    NSUInteger resizableSliceCount = resizableSlices.count;

    // Make sure we have enough to hand out to the slices that want it.
    remainingHeight = MAX(remainingHeight, totalFlexibleSliceMinimumHeight);
    
    CGFloat extraFlexibleHeight = remainingHeight - totalFlexibleSliceMinimumHeight;
    
    previousSlice = nil;
    for (OUIInspectorSlice *slice in _slices) {
        UIView *sliceView = slice.view;
        if (sliceView.superview != self)
            continue;
        
        UIView *sliceBackgroundView = slice.sliceBackgroundView;
        
        CGFloat sliceWidth = CGRectGetWidth(bounds) - [slice paddingToInspectorLeft] - [slice paddingToInspectorRight];
        CGFloat sliceContentHeight = CGRectGetHeight(sliceView.frame);
        CGFloat sliceTotalHeight = sliceContentHeight;
        if (sliceBackgroundView != nil) {
            sliceTotalHeight = CGRectGetHeight(sliceBackgroundView.frame);
            OBASSERT(sliceTotalHeight >= sliceContentHeight);
        }
        if ([resizableSlices member:slice]) {
            // Rather than sharing the extra height evenly on the resizable slices, we might want to come up with some kind of API to offer them space and let them set min/max constraints and workout how to share amongst themselves.
            sliceContentHeight = [slice minimumHeightForWidth:sliceWidth] + floor(extraFlexibleHeight / resizableSliceCount);
            if (sliceContentHeight > sliceTotalHeight) {
                sliceTotalHeight = sliceContentHeight;
            }
            remainingHeight -= sliceTotalHeight;
        } 
        
        if (previousSlice && sliceTotalHeight > 0) // OUIEmptyPaddingInspectorSlice can shrink to zero -- don't give it padding.
            yOffset += [slice paddingToPreviousSlice:previousSlice remainingHeight:bounds.size.height - yOffset];
                
        if (!slicesToPostponeFrameSetting || [slicesToPostponeFrameSetting member:slice] == nil) {
            CGFloat topContentOffset = slice.topInsetFromSliceBackgroundView;
            CGFloat bottomContentOffset = slice.bottomInsetFromSliceBackgroundView;
            CGFloat sliceVerticalPadding = sliceTotalHeight - topContentOffset - bottomContentOffset - sliceContentHeight;
            CGFloat sliceViewOffset = topContentOffset + floor(sliceVerticalPadding / 2.0f);
            
            sliceView.frame = CGRectMake(CGRectGetMinX(bounds) + [slice paddingToInspectorLeft], yOffset + sliceViewOffset, sliceWidth, sliceContentHeight);
            if (sliceBackgroundView != nil) {
                sliceBackgroundView.frame = CGRectMake(CGRectGetMinX(bounds), yOffset, CGRectGetWidth(bounds), sliceTotalHeight);
            }
        }

        yOffset += sliceTotalHeight;
        
        if (sliceTotalHeight > 0)
            previousSlice = slice;
    }

    yOffset += [[_slices lastObject] paddingToInspectorBottom];
    
    return yOffset;
}

@interface OUIStackedSlicesInspectorPaneContentView : UIScrollView
{
@private
    OUIInspectorBackgroundView *_backgroundView;
    NSArray *_slices;
}
- (UIColor *)inspectorBackgroundViewColor;
@property(nonatomic,copy) NSArray *slices;
@end

@implementation OUIStackedSlicesInspectorPaneContentView

static id _commonInit(OUIStackedSlicesInspectorPaneContentView *self)
{
    self->_backgroundView = [[OUIInspectorBackgroundView alloc] initWithFrame:self.bounds];
    [self addSubview:self->_backgroundView];
    self.alwaysBounceVertical = YES;
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (UIColor *)inspectorBackgroundViewColor;
{
    return [_backgroundView inspectorBackgroundViewColor];
}

@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices;
{
    if (OFISEQUAL(_slices, slices))
        return;
    
    _slices = [slices copy];
    
    [self setNeedsLayout];
}

- (void)layoutSubviews;
{
    [super layoutSubviews]; // Scroller

    NSUInteger sliceCount = [_slices count];
    if (sliceCount == 0) {
        // Should only get zero slices if the inspector is closed.
        OBASSERT(self.window == nil);
        return;
    }
    
    const CGRect bounds = self.bounds;
    
    CGFloat yOffset = _setSliceSizes(self, _slices, nil);
    
    self.contentSize = CGSizeMake(bounds.size.width, yOffset + 44);

    // Have to do this after the previous adjustments or the background view can get stuck scrolled part way down when we become unscrollable.
    _backgroundView.frame = self.bounds;
    
    // Terrible, but none of the other callbacks are timed so that the slices can alter the scroll position (since the content size isn't updated yet).
    for (OUIInspectorSlice *slice in _slices)
        [slice containingPaneDidLayout];
}

@end

@interface OUIStackedSlicesInspectorPane ()

@property(nonatomic,copy) NSArray *slices;

- (void)_stackedSlicesInspectorPane_keyboardWillShow:(NSNotification *)notification;
- (void)_stackedSlicesInspectorPane_keyboardDidShow:(NSNotification *)notification;

- (void)_stackedSlicesInspectorPane_textFieldTextDidBeginEditing:(NSNotification *)notification;
- (void)_stackedSlicesInspectorPane_textViewTextDidBeginEditing:(NSNotification *)notification;
- (void)_stackedSlicesInspectorPane_textViewDidBeginEditing:(NSNotification *)notification;

- (void)_scrollFirstResponderIntoView;
- (UIView *)_findFirstResponderStartingAtView:(UIView *)view;

@end

@implementation OUIStackedSlicesInspectorPane
{
    NSArray *_slices;
    id <OUIScrollNotifier> _scrollNotifier;
    BOOL _isAnimating;
    BOOL _keyboardIsAppearing;
}

+ (instancetype)stackedSlicesPaneWithAvailableSlices:(OUIInspectorSlice *)slice, ...;
{
    OBPRECONDITION(slice);
    
    NSMutableArray *slices = [[NSMutableArray alloc] initWithObjects:slice, nil];
    if (slice) {
        OUIInspectorSlice *nextSlice;
        
        va_list argList;
        va_start(argList, slice);
        while ((nextSlice = va_arg(argList, OUIInspectorSlice *)) != nil) {
            OBASSERT([nextSlice isKindOfClass:[OUIInspectorSlice class]]);
            [slices addObject:nextSlice];
        }
        va_end(argList);
    }

    OUIStackedSlicesInspectorPane *result = [[self alloc] init];
    
    NSArray *availableSlices = [slices copy];
    result.availableSlices = availableSlices;

    
    return result;
}

- (void)dealloc;
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [nc removeObserver:self name:UIKeyboardDidShowNotification object:nil];
    [nc removeObserver:self name:UITextFieldTextDidBeginEditingNotification object:nil];
    [nc removeObserver:self name:UITextViewTextDidBeginEditingNotification object:nil];
    [nc removeObserver:self name:UITextViewTextDidBeginEditingNotification object:nil];
}

- (void)setSliceAlignmentInsets:(UIEdgeInsets)newValue;
{
    if (UIEdgeInsetsEqualToEdgeInsets(_sliceAlignmentInsets, newValue)) {
        return;
    }
    
    _sliceAlignmentInsets = newValue;
    
    for (OUIInspectorSlice *slice in self.slices) {
        slice.alignmentInsets = _sliceAlignmentInsets;
    }
}

- (void)setSliceSeparatorColor:(UIColor *)newValue;
{
    if (OFISEQUAL(_sliceSeparatorColor,newValue)) {
        return;
    }
    
    _sliceSeparatorColor = newValue;
    
    for (OUIInspectorSlice *slice in self.slices) {
        slice.separatorColor = _sliceSeparatorColor;
    }
}

- (NSArray *)makeAvailableSlices;
{
    return nil; // For subclasses
}

- (void)setAvailableSlices:(NSArray *)availableSlices;
{
    if (OFISEQUAL(_availableSlices, availableSlices))
        return;
    
    _availableSlices = [availableSlices copy];
    
    if (self.visibility != OUIViewControllerVisibilityHidden) {
        // If we are currently on screen, a subclass might be changing the available slices somehow (like the tabbed document contents inspector in OO/iPad).
        // This will both update the filtered slices and their interface for the current inspection set.
        [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
    }
}

- (NSArray *)appropriateSlices:(NSArray *)availableSlices forInspectedObjects:(NSArray *)inspectedObjects;
{
    NSMutableArray *appropriateSlices = [NSMutableArray array];
    OUIInspectorSlice *previousSlice = nil;
    for (OUIInspectorSlice *slice in _availableSlices) {
        // Don't put a spacer at the beginning, or two spacers back-to-back
        if ([slice isKindOfClass:[OUIEmptyPaddingInspectorSlice class]]) {
            if ((previousSlice == nil) || previousSlice.includesInspectorSliceGroupSpacerOnBottom) {
                continue;
            }
        }
        
        if (![slice isAppropriateForInspectorPane:self]) {
            continue;
        }
        
        if ([slice isAppropriateForInspectedObjects:inspectedObjects]) {
            // If this slice includes a top group spacer and the previous slice was a spacer, remove that previous slice as it's not needed
            if (slice.includesInspectorSliceGroupSpacerOnTop && (previousSlice != nil) && [previousSlice isKindOfClass:[OUIEmptyPaddingInspectorSlice class]]) {
                OBASSERT([[appropriateSlices lastObject] isKindOfClass:[OUIEmptyPaddingInspectorSlice class]]);
                [appropriateSlices removeLastObject];
            }
            
            [appropriateSlices addObject:slice];
            previousSlice = slice;
        }
    }
    // Don't have a spacer at the end, either
    if ([appropriateSlices.lastObject isKindOfClass:[OUIEmptyPaddingInspectorSlice class]]) {
        [appropriateSlices removeLastObject];
    }
    
    return appropriateSlices;
}

- (NSArray *)appropriateSlicesForInspectedObjects;
{
    // Only fill the _availableSlices once. This allows the delegate/subclass to return an autoreleased array that isn't stored in a static (meaning that they can go away on a low memory warning). If we fill this multiple times, then we'll get confused and replace the slices constantly (since we do pointer equality in -setSlices:.
    if (!_availableSlices) {
        _availableSlices = [[self.inspector makeAvailableSlicesForStackedSlicesPane:self] copy];
    }
    
    // TODO: Add support for this style of use in the superclass? There already is in the delegate-based path.
    if (!_availableSlices) {
        _availableSlices = [[self makeAvailableSlices] copy];
        OBASSERT([_availableSlices count] > 0); // Didn't get slices from the delegate or a subclass!
    }
    
    // can be empty if the inspector is being closed
    NSArray *inspectedObjects = self.inspectedObjects;
    
    return [self appropriateSlices:_availableSlices forInspectedObjects:inspectedObjects];
}

static void _removeSlice(OUIStackedSlicesInspectorPane *self, OUIStackedSlicesInspectorPaneContentView *view, OUIInspectorSlice *slice)
{
    [slice willMoveToParentViewController:nil];
    if ([slice isViewLoaded] && slice.view.superview == view) {
        [slice.view removeFromSuperview]; // Only remove it if it is loaded and wasn't stolen by an embedding inspector (OmniGraffle).
    }
    [slice removeFromParentViewController];
}

+ (OUIInspectorSliceGroupPosition)_sliceGroupPositionForSlice:(OUIInspectorSlice *)slice precededBySlice:(OUIInspectorSlice *)precedingSlice followedBySlice:(OUIInspectorSlice *)followingSlice;
{
    BOOL isBeginningOfGroup = ((precedingSlice == nil) || precedingSlice.includesInspectorSliceGroupSpacerOnTop);
    BOOL isEndOfGroup = ((followingSlice == nil) || followingSlice.includesInspectorSliceGroupSpacerOnBottom);
    if (isBeginningOfGroup) {
        if (isEndOfGroup) {
            return OUIInspectorSliceGroupPositionAlone;
        } else {
            return OUIInspectorSliceGroupPositionFirst;
        }
    } else if (isEndOfGroup) {
        return OUIInspectorSliceGroupPositionLast;
    } else {
        return OUIInspectorSliceGroupPositionCenter;
    }
}

@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices maintainViewHierarchy:(BOOL)maintainHierachy;
{
    DEBUG_ANIM(@"In setSlices on thread %@", [NSThread currentThread]);
    // TODO: Might want an 'animate' variant later. 
    if (OFISEQUAL(_slices, slices))
        return;
    
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
    
    // Terrible hack to delay change until previous animation completes
    if (_isAnimating) {
        // This can happen when doing a sync in OmniPlan's Project:Sync inspector, where we add a slice to display status when the sync starts, then remove the slice when the sync completes (which can easily happen before the animation completes).
        [self performSelector:@selector(setSlices:) withObject:slices afterDelay:0];
        return;
    }
    
    // Establish view and view controller containment
    NSSet *oldSlices = [NSSet setWithArray:_slices];
    NSSet *newSlices = [NSSet setWithArray:slices];
    NSMutableSet *toBeOrphanedSlices = [NSMutableSet setWithSet:oldSlices];
    [toBeOrphanedSlices minusSet:newSlices];
    NSMutableSet *toBeAdoptedSlices = [NSMutableSet setWithSet:newSlices];
    [toBeAdoptedSlices minusSet:oldSlices];

    _slices = [[NSArray alloc] initWithArray:slices];
    
    // Tell the slices what position they are in - this impacts how they draw
    OUIInspectorSlice *previousSlice = nil;
    OUIInspectorSlice *currentSlice = nil;
    for (OUIInspectorSlice *nextSlice in _slices) {
        if (currentSlice != nil) {
            currentSlice.groupPosition = [OUIStackedSlicesInspectorPane _sliceGroupPositionForSlice:currentSlice precededBySlice:previousSlice followedBySlice:nextSlice];
        }
        previousSlice = currentSlice;
        currentSlice = nextSlice;
    }
    currentSlice.groupPosition = [OUIStackedSlicesInspectorPane _sliceGroupPositionForSlice:currentSlice precededBySlice:previousSlice followedBySlice:nil]; // The loop above doesn't process the last slice, just leaves us in a position to process it.

    if (maintainHierachy) {
        for (OUIInspectorSlice *slice in toBeOrphanedSlices) {
            [slice willMoveToParentViewController:nil];
        }
    }

    // Don't completely zero the alphas, or some slices will expect to be skipped when setting slice sizes.
    CGFloat newSliceInitialAlpha = [oldSlices count] > 0 ? 0.01 : 1.0; // Don't fade in on first display.
    for (OUIInspectorSlice *slice in toBeAdoptedSlices) {
        if (maintainHierachy) {
            [self addChildViewController:slice];
            // Add this once up front, but only if an embedding inspector hasn't stolen it from us (OmniGraffle). Not pretty, but that's how it is right now.
            UIView *sliceView = slice.view;
            if (sliceView.superview == nil) {
                sliceView.alpha = newSliceInitialAlpha;
                [view addSubview:sliceView];
                UIView *sliceBackgroundView = slice.sliceBackgroundView;
                OBASSERT(sliceBackgroundView.superview == nil); // If a slice has a background view, the background view needs to be added to and removed from our view at the same time as the slice's content view.
                if (sliceBackgroundView != nil) {
                    [view insertSubview:sliceBackgroundView belowSubview:sliceView];
                }
            }
        }
    }
    
    _setSliceSizes(view, _slices, oldSlices); // any slices that are sticking around keep their old frames, so we can animate them to their new positions
    
    // Telling the view about the slices triggers [view setNeedsLayout]. The view's layoutSubviews loops over the slices in order and sets their frames.
    view.slices = _slices;
        
    void (^animationHandler)(void) = ^{
        DEBUG_ANIM(@"enqueuing began");
        _isAnimating = YES;

        // animate position of slices that were already showing (whose frames were left unchanged above)
        _setSliceSizes(view, _slices, nil);

        for (OUIInspectorSlice *slice in toBeOrphanedSlices) {
            if ([slice isViewLoaded] && slice.view.superview == view)
                slice.view.alpha = 0.0;
        }
        for (OUIInspectorSlice *slice in toBeAdoptedSlices) {
            slice.view.alpha = 1.0;
        }
    };
    
    void (^completionHandler)(BOOL finished) = ^(BOOL finished){
        for (OUIInspectorSlice *slice in toBeOrphanedSlices) {
            if ([slice isViewLoaded] && slice.view.superview == view) {
                [slice.view removeFromSuperview]; // Only remove it if it is loaded and wasn't stolen by an embedding inspector (OmniGraffle).
                UIView *sliceBackgroundView = slice.sliceBackgroundView;
                if (sliceBackgroundView != nil) {
                    [sliceBackgroundView removeFromSuperview];
                }
            }
            [slice removeFromParentViewController];
        }
        
        if (maintainHierachy) {
            for (OUIInspectorSlice *slice in toBeAdoptedSlices) {
                [slice didMoveToParentViewController:self];
            }
        }
        
        _isAnimating = NO;
        DEBUG_ANIM(@"Animation completed");
    };
    
    BOOL shouldAnimate = [UIView areAnimationsEnabled] && [_slices count] > 0;
    
    if (shouldAnimate) {
        UIViewAnimationOptions options = UIViewAnimationOptionTransitionNone |UIViewAnimationOptionAllowAnimatedContent;
        [UIView animateWithDuration:OUICrossFadeDuration delay:0 options:options animations:animationHandler completion:completionHandler];
    } else {
        animationHandler();
        completionHandler(NO);
    }
}

- (void)setSlices:(NSArray *)slices;
{
    [self setSlices:slices maintainViewHierarchy:YES];
}

- (void)sliceSizeChanged:(OUIInspectorSlice *)slice;
{
    // TODO: It seems like we should be able to animate the resizing to avoid jumpy transitions.
    [self.contentView setNeedsLayout];
}

- (void)updateSlices;
{
    self.slices = [self appropriateSlicesForInspectedObjects];
    
#ifdef OMNI_ASSERTIONS_ON
    if ([_slices count] == 0) {
        // Inspected objects is nil if the inspector gets closed. Othrwise, if there really would be no applicable slices, the control to get here should have been disabled!    
        OBASSERT(self.inspectedObjects == nil);
        OBASSERT(self.visibility == OUIViewControllerVisibilityHidden);
    }
#endif
}

- (BOOL)inspectorPaneOfClassHasAlreadyBeenPresented:(Class)paneClass;
{
    OUIStackedSlicesInspectorPane *pane = self;
    while (pane != nil) {
        if ([pane class] == paneClass) {
            return YES;
        }
        if ([pane isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
            pane = pane.parentSlice.containingPane;
        }
    }
    
    return NO;
}

- (BOOL)inspectorSliceOfClassHasAlreadyBeenPresented:(Class)sliceClass;
{
    OUIStackedSlicesInspectorPane *earlierPane = self.parentSlice.containingPane;
    while (earlierPane != nil) {
        OBASSERT([earlierPane isKindOfClass:[OUIStackedSlicesInspectorPane class]]);
        NSArray *parentPaneSlices = earlierPane.slices;
        for (OUIInspectorSlice *iteratedSlice in parentPaneSlices) {
            if ([iteratedSlice class] == sliceClass) {
                return YES;
            }
        }
        
        earlierPane = earlierPane.parentSlice.containingPane;
    }
    return NO;
}

#pragma mark OUIInspectorPane subclass

- (void)inspectorWillShow:(OUIInspector *)inspector;
{
    [super inspectorWillShow:inspector];
    
    // This gets called earlier than -updateInterfaceFromInspectedObjects:. Might want to switch to just calling -updateInterfaceFromInspectedObjects: here instead of in -viewWillAppear:
    [self updateSlices];
    
    for (OUIInspectorSlice *slice in _slices) {
        @autoreleasepool {
            [slice inspectorWillShow:inspector];
        }
    }
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    [self updateSlices];
    
    for (OUIInspectorSlice *slice in _slices) {
        @autoreleasepool {
            [slice updateInterfaceFromInspectedObjects:reason];
        }
    }
}

#pragma mark -
#pragma mark UIViewController

- (void)didReceiveMemoryWarning;
{
    // Make sure to do this only when the whole inspector is hidden. We don't want to kill off a pane that pushed a detail pane.
    if (self.visibility == OUIViewControllerVisibilityHidden && ![self.inspector isVisible]) {
        // Remove our slices now to avoid getting assertion failures about their views not being subviews of ours when we remove them.
        
        // Ditch our current slices too. When we get reloaded, we'll rebuild and re add them.
        OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
        for (OUIInspectorSlice *slice in _slices)
            _removeSlice(self, view, slice);
        
        _slices = nil;
        
        // Make sure this doesn't hold onto these for its next -layoutSubviews
        view.slices = nil;
        
        // Tell all our available slices about this tradegy now that they aren't children view controllers.
        [_availableSlices makeObjectsPerformSelector:@selector(fakeDidReceiveMemoryWarning)];
        
        _scrollNotifier = nil;
        view.delegate = nil;
    }
    
    [super didReceiveMemoryWarning];
}

- (UIView *)contentView;
{
    return self.view;
}

- (void)loadView;
{
    OUIStackedSlicesInspectorPaneContentView *view = [[OUIStackedSlicesInspectorPaneContentView alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 16)];
    
    if (!_scrollNotifier)
        _scrollNotifier = [[OUIMinimalScrollNotifierImplementation alloc] init];
    view.delegate = _scrollNotifier;
    
    // If we are getting our view reloaded after a memory warning, we might already have slices. They should be mostly set up, but their superview needs fixing.
    for (OUIInspectorSlice *slice in _slices) {
        OBASSERT(slice.containingPane == self);
        OBASSERT([self isChildViewController:slice]);
        UIView *sliceView = slice.view;
        [view addSubview:sliceView];
        UIView *sliceBackgroundView = slice.sliceBackgroundView;
        if (sliceBackgroundView != nil) {
            [view insertSubview:sliceBackgroundView belowSubview:sliceView];
        }
    }
    view.slices = _slices;
    
    self.view = view;

    // It would be nice if we could just observe first responder changes, but there is no API for that.
    // We could probably swizzling UIResponder, and send out notifications ourselves. For now, just do it the duplicative way for the three common cases.
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_stackedSlicesInspectorPane_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(_stackedSlicesInspectorPane_keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [nc addObserver:self selector:@selector(_stackedSlicesInspectorPane_textFieldTextDidBeginEditing:) name:UITextFieldTextDidBeginEditingNotification object:nil];
    [nc addObserver:self selector:@selector(_stackedSlicesInspectorPane_textViewTextDidBeginEditing:) name:UITextViewTextDidBeginEditingNotification object:nil];
    [nc addObserver:self selector:@selector(_stackedSlicesInspectorPane_textViewDidBeginEditing:) name:UITextViewTextDidBeginEditingNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated;
{
    // Sadly, UINavigationController calls -navigationController:willShowViewController:animated: (which we use to provoke -inspectorWillShow:) BEFORE -viewWillAppear: when pushing but AFTER when popping. So, we have to update our list of child view controllers here too to avoid assertions in our life cycle checking. We don't want to send slices -viewWillAppear: and then drop them w/o ever sending -viewDidAppear: and the will/did disappear.
    [self updateSlices];

    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    
    OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
    [view flashScrollIndicators];
}

#pragma mark -
#pragma mark Keyboard Interaction

- (void)_stackedSlicesInspectorPane_keyboardWillShow:(NSNotification *)notification;
{
    _keyboardIsAppearing = YES;
}

- (void)_stackedSlicesInspectorPane_keyboardDidShow:(NSNotification *)notification;
{
    _keyboardIsAppearing = NO;
    [self _scrollFirstResponderIntoView];
}

- (void)_stackedSlicesInspectorPane_textFieldTextDidBeginEditing:(NSNotification *)notification;
{
    if (!_keyboardIsAppearing)
        [self _scrollFirstResponderIntoView];
}

- (void)_stackedSlicesInspectorPane_textViewTextDidBeginEditing:(NSNotification *)notification;
{
    if (!_keyboardIsAppearing)
        [self _scrollFirstResponderIntoView];
}

- (void)_stackedSlicesInspectorPane_textViewDidBeginEditing:(NSNotification *)notification;
{
    if (!_keyboardIsAppearing)
        [self _scrollFirstResponderIntoView];
}

- (void)_scrollFirstResponderIntoView;
{
    if (![self isViewLoaded] || !self.contentView.window)
        return;
    
    UIView *firstResponder = [self _findFirstResponderStartingAtView:self.contentView];
    if (firstResponder) {
        const CGFloat MARGIN_SLOP = 20;
        OUIStackedSlicesInspectorPaneContentView *view = (OUIStackedSlicesInspectorPaneContentView *)self.contentView;
        CGRect rect = CGRectInset([view convertRect:firstResponder.bounds fromView:firstResponder], -MARGIN_SLOP, -MARGIN_SLOP);
        [view scrollRectToVisible:rect animated:YES];
    }
}

- (UIView *)_findFirstResponderStartingAtView:(UIView *)view;
{
    if ([view isFirstResponder])
        return view;

    for (UIView *subview in view.subviews) {
        UIView *firstResponder = [self _findFirstResponderStartingAtView:subview];
        if (firstResponder)
            return firstResponder;
    }
    
    return nil;
}

@end
