// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorPane.h>

#import <OmniUI/OUICustomSubclass.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspector.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

// OUIInspectorPane
OBDEPRECATED_METHOD(-updateInterfaceFromInspectedObjects); // -> -updateInterfaceFromInspectedObjects:

@implementation OUIInspectorPane
{
    __weak OUIInspector *_weak_inspector; // the main inspector
    __weak OUIInspectorSlice *_weak_parentSlice; // our parent slice if any
    NSArray *_inspectedObjects;
}

+ (NSString *)nibName;
{
    // OUIAllocateViewController means we might get 'MyCustomFooInspectorSlice' for 'OUIFooInspectorSlice'. View controller's should be created so often that this would be too slow. One question is whether UINib is uniqued, though, since otherwise we perform extra I/O.
    return OUICustomClassOriginalClassName(self);
}

+ (NSBundle *)nibBundle;
{
    // OUIAllocateViewController means we might get 'MyCustomFooInspectorSlice' for 'OUIFooInspectorSlice'. View controller's should be created so often that this would be too slow. One question is whether UINib is uniqued, though, since otherwise we perform extra I/O.
    Class cls = NSClassFromString(OUICustomClassOriginalClassName(self));
    assert(cls);
    return [NSBundle bundleForClass:cls];
}

+ (id)allocWithZone:(NSZone *)zone;
{
    OUIAllocateCustomClass;
}

- init;
{
    return [self initWithNibName:[[self class] nibName] bundle:[[self class] nibBundle]];
}

- (BOOL)inInspector;
{
    return _weak_inspector != nil;
}

- (UIEdgeInsets)additionalSafeAreaInsets
{
    UIEdgeInsets edgeInsets = UIEdgeInsetsZero;
    if (self.navigationController) {
        edgeInsets.top = [self.navigationController heightOfAccessoryBar];
    }
    return edgeInsets;
}

@synthesize inspector = _weak_inspector;
- (OUIInspector *)inspector;
{
    OBPRECONDITION(_weak_inspector);
    return _weak_inspector;
}

@synthesize parentSlice = _weak_parentSlice;

@synthesize inspectedObjects = _inspectedObjects;

- (void)inspectorWillShow:(OUIInspector *)inspector;
{
    // For subclasses
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    // For subclasses
}

- (void)setInspectedObjects:(NSArray *)inspectedObjects {
    if ([_inspectedObjects isEqualToArray:inspectedObjects]) {
        return;
    }
    
    _inspectedObjects = inspectedObjects;
    
    if (self.viewLoaded) {
        OUIInspectorUpdateReason reason = (_inspectedObjects == nil) ? OUIInspectorUpdateReasonDefault : OUIInspectorUpdateReasonNeedsReload;
        [self updateInterfaceFromInspectedObjects:reason];
    }
}

#pragma mark -
#pragma mark UIViewController

- (void)viewWillAppear:(BOOL)animated;
{
    OBPRECONDITION(_weak_inspector); // should have been set by now
    
    [super viewWillAppear:animated];
    [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[self view] endEditing:YES];
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

@end
