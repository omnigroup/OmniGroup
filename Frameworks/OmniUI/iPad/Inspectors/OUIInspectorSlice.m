// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorDetailSlice.h>

RCS_ID("$Id$");

@implementation OUIInspectorSlice

+ (NSString *)nibName;
{
    return NSStringFromClass(self);
}

- init;
{
    return [super initWithNibName:[[self class] nibName] bundle:[NSBundle mainBundle]];
}

- (void)dealloc;
{
    [_detailSlice release];
    [super dealloc];
}

@synthesize inspector = _nonretained_inspector;
- (void)setInspector:(OUIInspector *)inspector;
{
    _nonretained_inspector = inspector;
}

@synthesize detailSlice = _detailSlice;
- (void)setDetailSlice:(OUIInspectorDetailSlice *)detailSlice;
{
    // Just expect this to get called when loading xib. If we want to swap out details, we'll need to only do it when the detail isn't on screen.
    OBPRECONDITION(!_detailSlice);
    
    [_detailSlice autorelease];
    _detailSlice = [detailSlice retain];
    
    // propagate the inspector if we already got it set.
    _detailSlice.slice = self;
}

- (IBAction)showDetails:(id)sender;
{
    OBPRECONDITION(_detailSlice);
    OBPRECONDITION(_nonretained_inspector);
    if (!_detailSlice)
        return;
    
    [_nonretained_inspector pushDetailSlice:_detailSlice];
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
    NSMutableSet *objects = nil;
    
    for (id object in _nonretained_inspector.inspectedObjects) {
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
    [_detailSlice updateInterfaceFromInspectedObjects];
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
    
    // We edit with a black background so we can see stuff in IB, but need to turn that off here to look right in the popover.
    view.opaque = NO;
    view.backgroundColor = nil;
}

@end
