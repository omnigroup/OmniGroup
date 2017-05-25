// Copyright 2005-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspector.h>

#import <AppKit/AppKit.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSTextField-OAExtensions.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFEnumNameTable-OFFlagMask.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniInspector/OIInspectableControllerProtocol.h>
#import <OmniInspector/OIInspectorController.h>
#import <OmniInspector/OIInspectorHeaderView.h>
#import <OmniInspector/OIInspectionSet.h>
#import <OmniInspector/OIInspectorRegistry.h>
#import <OmniInspector/OITabbedInspector.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

static OFEnumNameTable *ModifierMaskNameTable = nil;
static OFEnumNameTable *OIVisibilityStateNameTable = nil;

@interface OIInspector ()
@property(nonatomic,readwrite) CGFloat inspectorMinimumHeight;
@end

@implementation OIInspector

+ (void)initialize;
{
    OBINITIALIZE;
    
    ModifierMaskNameTable = [[OFEnumNameTable alloc] initWithDefaultEnumValue:0];
    [ModifierMaskNameTable setName:@"none" forEnumValue:0];
    [ModifierMaskNameTable setName:@"alpha-lock" forEnumValue:NSAlphaShiftKeyMask];
    [ModifierMaskNameTable setName:@"shift" forEnumValue:NSShiftKeyMask];
    [ModifierMaskNameTable setName:@"control" forEnumValue:NSControlKeyMask];
    [ModifierMaskNameTable setName:@"option" forEnumValue:NSAlternateKeyMask];
    [ModifierMaskNameTable setName:@"command" forEnumValue:NSCommandKeyMask];
    [ModifierMaskNameTable setName:@"num-lock" forEnumValue:NSNumericPadKeyMask];
    [ModifierMaskNameTable setName:@"function" forEnumValue:NSFunctionKeyMask];

    OIVisibilityStateNameTable = [[OFEnumNameTable alloc] initWithDefaultEnumValue:OIVisibleVisibilityState];
    [OIVisibilityStateNameTable setName:@"hidden" forEnumValue:OIHiddenVisibilityState];
    [OIVisibilityStateNameTable setName:@"visible" forEnumValue:OIVisibleVisibilityState];
    [OIVisibilityStateNameTable setName:@"pinned" forEnumValue:OIPinnedVisibilityState];
}

+ (OFEnumNameTable *)visibilityStateNameTable;
{
    return OIVisibilityStateNameTable;
}

+ (nullable __kindof OIInspector <OIConcreteInspector> *)inspectorWithDictionary:(NSDictionary *)dict inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(nullable NSBundle *)sourceBundle;
{
    // Do the OS version check before allocating an instance
    NSString *minimumOSVersionString = [dict objectForKey:@"minimumOSVersion"];
    if (![NSString isEmptyString:minimumOSVersionString]) {
        OFVersionNumber *minimumOSVersion = [[OFVersionNumber alloc] initWithVersionString:minimumOSVersionString];
        OFVersionNumber *currentOSVersion = [OFVersionNumber userVisibleOperatingSystemVersionNumber];
        
        BOOL yummy = ([currentOSVersion compareToVersionNumber:minimumOSVersion] != NSOrderedAscending);
        if (!yummy)
            return nil;
    }
    
    NSString *className = [dict objectForKey:@"class"];
    if (!className)
        [NSException raise:NSInvalidArgumentException format:@"Required key 'class' not found in inspector dictionary %@", dict];
    
    // Particularly for OITabbedInspectors which will always have [self bundle] of OmniInspector, the OIInspectors entry in the main bundle's Info.plist needs to allow the developer to specify where to find resources.
    NSBundle *inspectorResourceBundle;
    NSString *resourceBundleIdentifier = [dict objectForKey:@"bundle"];
    if (resourceBundleIdentifier) {
        if ([resourceBundleIdentifier isEqualToString:@"mainBundle"])
            inspectorResourceBundle = [NSBundle mainBundle];
        else
            inspectorResourceBundle = [NSBundle bundleWithIdentifier:resourceBundleIdentifier];
	if (!inspectorResourceBundle)
	    NSLog(@"%s: Unable to find bundle with identifier %@", __PRETTY_FUNCTION__, resourceBundleIdentifier);
    } else
        inspectorResourceBundle = sourceBundle;
    
    Class cls = NSClassFromString(className);
    if (!cls)
        [NSException raise:NSInvalidArgumentException format:@"Inspector dictionary specified class that doesn't exist: %@", dict];

    OIInspector *inspector = [[cls alloc] initWithDictionary:dict inspectorRegistry:inspectorRegistry bundle:inspectorResourceBundle];

    // The init method asserts this is the case
    return (OIInspector <OIConcreteInspector> *)inspector;
}

// Make sure inspector subclasses are calling [super initWithDictionary:bundle:]
- (id)init;
{
    OBRejectUnusedImplementation([self class], _cmd);
    return nil;
}

- (nullable id)initWithDictionary:(NSDictionary *)dict inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(nullable NSBundle *)sourceBundle;
{
    OBPRECONDITION(dict);
    OBPRECONDITION([self conformsToProtocol:@protocol(OIConcreteInspector)]);

    if (!(self = [super initWithNibName:nil bundle:sourceBundle]))
        return nil;

    {
        // Ensure that deprecated methods from the old OIGroupedInspector protocol aren't around
        OBASSERT_NOT_IMPLEMENTED(self, inspectorName);
        OBASSERT_NOT_IMPLEMENTED(self, defaultDisplayGroupNumber);
        OBASSERT_NOT_IMPLEMENTED(self, defaultDisplayOrderInGroup);
        OBASSERT_NOT_IMPLEMENTED(self, defaultGroupVisibility);
        OBASSERT_NOT_IMPLEMENTED(self, keyEquivalent);
        OBASSERT_NOT_IMPLEMENTED(self, keyEquivalentModifierMask);
        OBASSERT_NOT_IMPLEMENTED(self, imageName);
        
        // ... or deprecated methods from the OITabbedInspector protocol
        OBASSERT_NOT_IMPLEMENTED(self, tabGroupName);
        OBASSERT_NOT_IMPLEMENTED(self, tabGroupImage);
        OBASSERT_NOT_IMPLEMENTED(self, tabImageName);
        
        // ... or deprecated optional methods from OIConcreteInspector
        OBASSERT_NOT_IMPLEMENTED(self, inspectorWillResizeToSize:); // Now called -inspectorWillResizeToHeight:
        OBASSERT_NOT_IMPLEMENTED(self, inspectorMinimumSize); // Now called -inspectorMinimumHeight
        OBASSERT_NOT_IMPLEMENTED(self, inspectorDesiredWidth); // Totally deprecated
        
        // Or other vanished methods
        OBASSERT_NOT_IMPLEMENTED(self, initWithDictionary:); // Now called -initWithDictionary:bundle:
    }
    
    _resourceBundle = sourceBundle;
    if (!_resourceBundle)
        _resourceBundle = [[self class] bundle]; // need something non-nil, but this likely won't work very well.
    
    _allowImagesFromApplication = [dict boolForKey:@"allowImagesFromApplication" defaultValue:NO];
    
    _inspectorIdentifier = [[dict objectForKey:@"identifier"] copy];
    if (!_inspectorIdentifier) {
        _inspectorIdentifier = [NSString stringWithStrings:[_resourceBundle bundleIdentifier], @".", NSStringFromClass([self class]), nil];
    }
    OBASSERT(_inspectorIdentifier != nil);
    
    _displayName = [_resourceBundle localizedStringForKey:_inspectorIdentifier value:nil table:@"OIInspectors"];
    if ([_displayName isEqualToString:_inspectorIdentifier])
        // _inspectorIdentifier is expected to be com.foo... so the two should never be equal if you've added the entry to the right OIInspectors.strings file
        NSLog(@"Inspector with identifier %@ has no display name registered in OIInspectors.strings in %@", _inspectorIdentifier, _resourceBundle);
    
    NSString *visibilityString = [dict objectForKey:@"visibilityState"];
    if (visibilityString != nil) {
        OBASSERT([visibilityString isKindOfClass:[NSString class]]);
        _defaultVisibilityState = (OIVisibilityState)[OIVisibilityStateNameTable enumForName:[visibilityString lowercaseString]];
    } else {    // Backward-compatibility with before the Pinned state was introduced
        _defaultVisibilityState = [dict boolForKey:@"visible" defaultValue:NO] ? OIVisibleVisibilityState : OIHiddenVisibilityState;
    }
    
    NSDictionary *inspectorKeyboardShortcut = [dict objectForKey:@"shortcut"];
    if (inspectorKeyboardShortcut) {
        _shortcutKey = [[inspectorKeyboardShortcut objectForKey:@"key"] copy];
        _shortcutModifierFlags = [ModifierMaskNameTable maskForString:[inspectorKeyboardShortcut objectForKey:@"flags"] withSeparator:'|'];
    } else {
        _shortcutKey = nil;
        _shortcutModifierFlags = 0;
    }
    
    _inspectorImageName = [[dict objectForKey:@"image"] copy];
    if (_inspectorImageName) {
        _image = [self imageNamed:_inspectorImageName]; // cache up front so we don't need a 'cached' flag (very likely to get used ASAP)
	if (!_image)
	    NSLog(@"Unable to find image '%@' for %@ in bundle %@", _inspectorImageName, self, _resourceBundle);
    }
    
    _inspectorTabImageName = [[dict objectForKey:@"tabImage"] copy];
    
    if ([dict objectForKey:@"order"])
        _defaultOrderingWithinGroup = [dict unsignedIntForKey:@"order"];
    else
        _defaultOrderingWithinGroup = NSNotFound;
    
    if ([dict objectForKey:@"preferredInterfaceType"]) {
        _preferredInterfaceType = [dict unsignedIntForKey:@"preferredInterfaceType"];
    } else {
        // Apps that haven't concerned themselves with recent changes to OmniInspector won't specify a preferredInterfaceType. These apps universally expect OI to provide a floating interface. Oblige them.
        _preferredInterfaceType = OIInspectorInterfaceTypeFloating;
    }
    
    _wantsHeader =  YES;
    if ([dict objectForKey:@"wantsHeader"])
        _wantsHeader = [dict boolForKey:@"wantsHeader"];
    _isCollapsible = YES;
    if ([dict objectForKey:@"isCollapsible"])
        _isCollapsible = [dict boolForKey:@"isCollapsible"];
    if ([dict objectForKey:@"pinningDisabled"]) {
        _pinningDisabled = [dict boolForKey:@"pinningDisabled"];
    }

    return self;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.inspectorMinimumHeight = NSHeight([self.view frame]);
}

@dynamic identifier; // Marked NS_UNAVAILABLE in our header to avoid conflicting with the one NSViewController has due to NSUserInterfaceItemIdentification.

- (nullable NSImage *)imageNamed:(NSString *)imageName;
{
    NSImage *image = nil;
    BOOL checkAppWrapperFirst = (_allowImagesFromApplication && (_resourceBundle != [NSBundle mainBundle])); // NO if the resourceBundle is the mainBundle, to avoid checking the app wrapper twice
    if (checkAppWrapperFirst) {
        image = [NSImage imageNamed:imageName];
    }
    if (image == nil) {
        image = [NSImage imageNamed:imageName inBundle:_resourceBundle];
    }
    return image;
}

- (nullable NSImage *)tabImage;
{
    NSImage *image = [self imageNamed:_inspectorTabImageName];
    if (_inspectorTabImageName && !image)
        NSLog(@"Unable to find image '%@' for %@ in bundle %@", _inspectorTabImageName, self, _resourceBundle);
    return image;
}

@synthesize defaultOrderingWithinGroup = _defaultOrderingWithinGroup;
- (NSUInteger)defaultOrderingWithinGroup;
{
    return ( _defaultOrderingWithinGroup != NSNotFound )? _defaultOrderingWithinGroup : 0;
}

- (void)setDefaultOrderingWithinGroup:(NSUInteger)defaultOrderingWithinGroup;
{
    if (_defaultOrderingWithinGroup != NSNotFound)
        _defaultOrderingWithinGroup = defaultOrderingWithinGroup;
}

// TODO: Get rid of this
- (unsigned int)deprecatedDefaultDisplayGroupNumber;
{
    return 0;
}

- (CGFloat)defaultHeaderHeight;
{
    return OIInspectorStartingHeaderButtonHeight;
}

- (CGFloat)additionalHeaderHeight;
{
    return 0.0f;
}

- (NSMenuItem *)menuItemForTarget:(nullable id)target action:(SEL)action;
{
    OBPRECONDITION(!target || [target respondsToSelector:action]);

    NSString *keyEquivalent = [self shortcutKey];
    if (keyEquivalent == nil)
	keyEquivalent = @"";
    
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[self displayName] action:action keyEquivalent:keyEquivalent];
    [menuItem setTarget:target];
    [menuItem setRepresentedObject:self];
    
    NSImage *image = [self image];
    if (image) {
        [menuItem setImage:image];
    }
    if ([keyEquivalent length])
        [menuItem setKeyEquivalentModifierMask:[self shortcutModifierFlags]];
    return menuItem;
}

- (NSArray *)menuItemsForTarget:(nullable id)target action:(SEL)action;
{
    NSMenuItem *singleItem = [self menuItemForTarget:target action:action];
    return singleItem ? [NSArray arrayWithObject:singleItem] : nil;
}

// Useful utility method in -inspectObjects:.  Not currently called automatically anywhere, just intended for subclasses at the moment.
- (void)setControlsEnabled:(BOOL)enabled;
{
    [self setControlsEnabled:enabled inView:self.view];
}

- (void)setControlsEnabled:(BOOL)enabled inView:(NSView *)view;
{
    for (id subview in [view subviews]) {
        // This messes up scrollers; <bug://bugs/28355>
        if ([subview isKindOfClass:[NSScrollView class]])
            continue;
	
        if (([subview infoForBinding:NSEnabledBinding] == nil) && [subview respondsToSelector:@selector(target)] && [subview target]) {
            if ([subview respondsToSelector:@selector(setEnabled:)])
                [subview setEnabled:enabled];
            continue;
        }
        if (([subview infoForBinding:NSTextColorBinding] == nil) && [subview respondsToSelector:@selector(changeColorAsIfEnabledStateWas:)]) {
            [subview changeColorAsIfEnabledStateWas:enabled];
            continue;
        }
        [self setControlsEnabled:enabled inView:subview];
    }
}

- (BOOL)shouldBeUsedForObject:(id)object;
{
    if (![[(id <OIConcreteInspector>)self inspectedObjectsPredicate] evaluateWithObject:object])
        return NO;
        
    // Optional finer grain predicate.
    NSPredicate *predicate = [self shouldBeUsedForObjectPredicate];
    if (predicate != nil && ![predicate evaluateWithObject:object])
        return NO;

    return YES;
}

- (nullable NSPredicate *)shouldBeUsedForObjectPredicate;
{
    return nil;
}

- (void)inspectorDidResize:(OIInspector *)resizedInspector;
{
    OBASSERT_NOT_REACHED("This should only be called on inspectors which are ancestors of the resized inspector.");
}

- (void)enqueueResizeToFittingSizeBeforeAnyWindowDisplayWithInspectorController:(OIInspectorController *)inspectorController;
{
    __weak OIInspectorController *weakInspectorController = inspectorController;
    __weak OIInspector *weakSelf = self;
    
    [NSWindow beforeAnyDisplayIfNeededPerformBlock:^{
        OIInspector *strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf.inspectorMinimumHeight = [strongSelf.view fittingSize].height;
            OIInspectorController *strongInspectorController = weakInspectorController;
            [strongInspectorController inspectorDidResize:strongSelf];
        }
    }];
}

#pragma mark - Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:_inspectorIdentifier forKey:@"identifier"];
    [dict setObject:_displayName forKey:@"displayName"];
    [dict setObject:[NSNumber numberWithInt:_defaultVisibilityState] forKey:@"defaultVisibilityState"];
    if (_shortcutKey)
        [dict setObject:_shortcutKey forKey:@"shortcutKey"];
    if (_shortcutModifierFlags) {
        OBASSERT(_shortcutModifierFlags < UINT32_MAX); // Need to make OFEnumNameTable do NSInteger instead of int?
        [dict setObject:[ModifierMaskNameTable copyStringForMask:(uint32_t)_shortcutModifierFlags withSeparator:'|'] forKey:@"shortcutModifierFlags"];
    }
    if (_inspectorImageName) {
        [dict setObject:_inspectorImageName forKey:@"imageName"];
        if (_image)
            [dict setObject:_image forKey:@"image"];
    }
    
    return dict;
}

@end

@implementation OIInspector (OISelectionRelativeNames)

- (nullable NSString *)selectionRelativeNameForObject:(id)object amongObjects:(NSArray *)inspectedObjects;
{
    // TODO: This is gross -- better would be to have the inspection set passed down to all the inspectors and have that call -inspectObjects:.
    OIInspectionSet *inspectionSet = self.inspectorController.inspectorRegistry.inspectionSet;
    OBASSERT_NOTNULL(inspectionSet);

    for (id <OIInspectableController> controller in inspectionSet.inspectableControllers) {
        if ([controller conformsToProtocol:@protocol(OIInspectedObjectSelectionRelativeNames)]) {
            id <OIInspectedObjectSelectionRelativeNames> selectionRelativeNames = (typeof(selectionRelativeNames))controller;
            NSString *name = [selectionRelativeNames inspector:self selectionRelativeNameForObject:object amongObjects:inspectedObjects inspectionSet:inspectionSet];
            if (name)
                return name;
        }
    }

    return nil;
}

@end

NS_ASSUME_NONNULL_END
