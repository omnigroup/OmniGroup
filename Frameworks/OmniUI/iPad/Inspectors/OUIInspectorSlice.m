// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorPane.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUIInspectorSlice

+ (void)initialize;
{
    OBINITIALIZE;
    
    // We add -init below for caller's convenience, but subclasses should not subclass that; they should subclass the designated initializer.
    OBASSERT(OBClassImplementingMethod(self, @selector(init)) == [OUIInspectorSlice class]);
}

+ (NSString *)nibName;
{
    return NSStringFromClass(self);
}

- init;
{
    return [self initWithNibName:[[self class] nibName] bundle:[NSBundle mainBundle]];
}

- (void)dealloc;
{
    [_detailPane release];
    [super dealloc];
}

@synthesize containingPane = _nonretained_containingPane;
- (void)setContainingPane:(OUIInspectorPane *)pane;
{
    _nonretained_containingPane = pane;
}

- (OUIInspector *)inspector;
{
    OUIInspector *inspector = _nonretained_containingPane.inspector;
    OBASSERT(inspector);
    return inspector;
}

// Uses -[UIView(OUIExtensions) borderEdgeInsets] to find out what adjustment to make to the nominal spacing to make things *look* like they are spaced that way.
static CGFloat _borderOffsetFromEdge(UIView *view, CGRectEdge fromEdge)
{
    UIEdgeInsets insets = view.borderEdgeInsets;
    
    if (UIEdgeInsetsEqualToEdgeInsets(insets, OUINoBorderEdgeInsets))
        return 0;
    
    switch (fromEdge) {

        case CGRectMinXEdge:
            return insets.left;
        case CGRectMinYEdge:
            return insets.top;
        case CGRectMaxXEdge:
            return insets.right;
        case CGRectMaxYEdge:
            return insets.bottom;
        default:
            OBASSERT_NOT_REACHED("Bad edge enum");
            return 0;
    }
}

- (CGFloat)paddingToInspectorTop;
{
    return 10 - _borderOffsetFromEdge(self.view, CGRectMinYEdge); // More than the bottom due to the inner shadow on the popover controller.
}

- (CGFloat)paddingToInspectorBottom;
{
    return 8 - _borderOffsetFromEdge(self.view, CGRectMaxYEdge);
}

- (CGFloat)paddingToPreviousSlice:(OUIInspectorSlice *)previousSlice;
{
    return 14 - _borderOffsetFromEdge(self.view, CGRectMinYEdge) - _borderOffsetFromEdge(previousSlice.view, CGRectMaxYEdge);
}

- (CGFloat)paddingToInspectorSides;
{
    // The goal is to match the inset of grouped table view cells (for cases where we have controls next to one), though individual inspectors may need to adjust this.
    return 9 - _borderOffsetFromEdge(self.view, CGRectMinXEdge); // Assumes the left/right border offsets are the same, which they usually are with shadows being done vertically.
}

@synthesize detailPane = _detailPane;
- (void)setDetailPane:(OUIInspectorPane *)detailPane;
{
    // Just expect this to get called when loading xib. If we want to swap out details, we'll need to only do it when the detail isn't on screen.
    OBPRECONDITION(!_detailPane);
    
    [_detailPane autorelease];
    _detailPane = [detailPane retain];
    
    // propagate the inspector if we already got it set.
    _detailPane.parentSlice = self;
}

- (IBAction)showDetails:(id)sender;
{
    OBPRECONDITION(_detailPane);
    if (!_detailPane)
        return;
    
    [self.inspector pushPane:_detailPane];
}

- (BOOL)isAppropriateForInspectedObjects:(NSSet *)objects;
{
    for (id object in objects)
        if ([self isAppropriateForInspectedObject:object])
            return YES;
    return NO;
}

- (NSSet *)appropriateObjectsForInspection;
{
    OBPRECONDITION(_nonretained_containingPane);
    
    NSMutableSet *objects = nil;
    
    for (id object in _nonretained_containingPane.inspectedObjects) {
        if ([self isAppropriateForInspectedObject:object]) {
            if (!objects)
                objects = [NSMutableSet set];
            [objects addObject:object];
        }
    }
    
    return objects;
}

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}

- (void)updateInterfaceFromInspectedObjects;
{
    // For subclasses
}

- (NSNumber *)singleSelectedValueForCGFloatSelector:(SEL)sel;
{
    CGFloat value = 0;
    BOOL hasValue = NO;
    
    for (id object in self.appropriateObjectsForInspection) {
        CGFloat (*getter)(id obj, SEL _cmd) = (typeof(getter))[object methodForSelector:sel];
        OBASSERT(getter);
        if (!getter)
            continue;
        
        CGFloat objectValue = getter(object, sel);
        if (!hasValue) {
            value = objectValue;
            hasValue = YES;
        } else if (value != objectValue)
            return nil;
    }
    
    if (hasValue)
        return [NSNumber numberWithFloat:value];
    return nil;
}

- (NSNumber *)singleSelectedValueForIntegerSelector:(SEL)sel;
{
    NSInteger value = 0;
    BOOL hasValue = NO;
    
    for (id object in self.appropriateObjectsForInspection) {
        NSInteger (*getter)(id obj, SEL _cmd) = (typeof(getter))[object methodForSelector:sel];
        OBASSERT(getter);
        if (!getter)
            continue;
        
        NSInteger objectValue = getter(object, sel);
        if (!hasValue) {
            value = objectValue;
            hasValue = YES;
        } else if (value != objectValue)
            return nil;
    }
    
    if (hasValue)
        return [NSNumber numberWithInteger:value];
    return nil;
}

- (NSValue *)singleSelectedValueForCGPointSelector:(SEL)sel;
{
    CGPoint value = CGPointZero;
    BOOL hasValue = NO;
    
    for (id object in self.appropriateObjectsForInspection) {
        CGPoint (*getter)(id obj, SEL _cmd) = (typeof(getter))[object methodForSelector:sel];
        OBASSERT(getter);
        if (!getter)
            continue;
        
        CGPoint objectValue = getter(object, sel);
        if (!hasValue) {
            value = objectValue;
            hasValue = YES;
        } else if (!CGPointEqualToPoint(value, objectValue))
            return nil;
    }
    
    if (hasValue)
        return [NSValue valueWithCGPoint:value];
    return nil;
}

#pragma mark -
#pragma mark UIViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
        
    UIView *view = self.view;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin; // Unclear whether "bottom" means visual bottom or max y...
}

@end
