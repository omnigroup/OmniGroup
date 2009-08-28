// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAToolbarWindowController.h"

#import <AppKit/AppKit.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

#import "OAAquaButton.h"
#import "OAScriptToolbarHelper.h"
#import "OAToolbar.h"
#import "OAToolbarItem.h"
#import "NSImage-OAExtensions.h"

RCS_ID("$Id$")

@interface OAToolbarWindowController (Private)
+ (void)_loadToolbarNamed:(NSString *)toolbarName;
@end

@implementation OAToolbarWindowController

static NSMutableDictionary *ToolbarItemInfo = nil;
static NSMutableDictionary *allowedToolbarItems = nil;
static NSMutableDictionary *defaultToolbarItems = nil;
static NSMutableDictionary *toolbarStringsTables = nil;
static NSMutableDictionary *helpersByExtension = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    ToolbarItemInfo = [[NSMutableDictionary alloc] init];
    allowedToolbarItems = [[NSMutableDictionary alloc] init];
    defaultToolbarItems = [[NSMutableDictionary alloc] init];
    toolbarStringsTables = [[NSMutableDictionary alloc] init];
    helpersByExtension = [[NSMutableDictionary alloc] init];
    
    [self registerToolbarHelper:[[OAScriptToolbarHelper alloc] init]];
}

+ (void)registerToolbarHelper:(NSObject <OAToolbarHelper> *)helperObject;
{
    [helpersByExtension setObject:helperObject forKey:[helperObject itemIdentifierExtension]];
}

+ (NSBundle *)toolbarBundle;
{
    // +bundleForClass: can get fooled, particularly by DYLD_INSERT_LIBRARIES used by OOM.  Subclass this if you want to look in a different bundle (and don't use +bundleForClass:, obviously, use +bundleWithIdentifier:).
    return [NSBundle mainBundle];
}

+ (Class)toolbarClass;
{
    return [OAToolbar class];
}

+ (Class)toolbarItemClass;
{
    return [OAToolbarItem class];
}

// Init and dealloc

- (void)dealloc;
{
    [toolbar setDelegate:nil];
    [toolbar release];
    [super dealloc];
}


// NSWindowController subclass

- (void)windowDidLoad; // Setup the toolbar and handle its delegate messages
{
    [super windowDidLoad]; // DOX: These are called immediately before and after the controller loads its nib file.  You can subclass these but should not call them directly.  Always call super from your override.
    [self createToolbar];
}

- (OAToolbar *)toolbar;
{
    return toolbar;
}

- (void)createToolbar;
{
    OBPRECONDITION(_isCreatingToolbar == NO);
    
    _isCreatingToolbar = YES;
    @try {
	if (toolbar) {
	    [toolbar setDelegate:nil];
	    [toolbar release];
	}
	
	// The subclass may change its response to all the subclass methods and then call this (see OmniOutliner's document-specific toolbar support)
	[isa _loadToolbarNamed:[self toolbarConfigurationName]];
	
	Class toolbarClass = [isa toolbarClass];
	OBASSERT(OBClassIsSubclassOfClass(toolbarClass, [OAToolbar class]));
	
	toolbar = [[toolbarClass alloc] initWithIdentifier:[self toolbarIdentifier]];
	[toolbar setAllowsUserCustomization:[self shouldAllowUserToolbarCustomization]];
	
	NSDictionary *config = nil;
	if ([self shouldAutosaveToolbarConfiguration])
	    [toolbar setAutosavesConfiguration:YES];
	else {
	    [toolbar setAutosavesConfiguration:NO];
	    config = [self toolbarConfigurationDictionary];
	}
	[toolbar setDelegate:self];
	[[self window] setToolbar:toolbar];
	
	// Have to set this after adding the toolbar to the window.  Otherwise, the toolbar will keep the size/mode, but will use the default identifiers.
	if (config)
	    [toolbar setConfigurationFromDictionary:config];
    } @finally {
	_isCreatingToolbar = NO;
    }
}

// This can be useful if you listen for toolbar item add/remove notifications and don't want to tell whether that's because we are creating a toolbar or whether the user is editing it.  We can't use -customizationPaletteIsRunning since that doesn't account for the user command-dragging items off the toolbar.
- (BOOL)isCreatingToolbar;
{
    return _isCreatingToolbar;
}

- (NSDictionary *)toolbarInfoForItem:(NSString *)identifier;
{
    NSDictionary *toolbarItemInfo = [ToolbarItemInfo objectForKey:[self toolbarConfigurationName]];
    OBASSERT(toolbarItemInfo);
    NSDictionary *itemInfo = [toolbarItemInfo objectForKey:identifier];
    OBPOSTCONDITION(itemInfo);
    return itemInfo;
}

// Implement in subclasses

- (NSString *)toolbarConfigurationName;
{
    // TODO: This should really default to something useful (like the name of the class)
    return @"Toolbar";
}

- (NSString *)toolbarIdentifier;
{
    return [self toolbarConfigurationName];
}

- (BOOL)shouldAllowUserToolbarCustomization;
{
    return YES;
}

- (BOOL)shouldAutosaveToolbarConfiguration;
{
    return YES;
}

- (NSDictionary *)toolbarConfigurationDictionary;
{
    // This is called if -shouldAutosaveConfiguration is NO (i.e., the configuration isn't in user defaults, so it has to come from somewhere)
    OBRequestConcreteImplementation(isa, _cmd);
    return nil;
}

// NSObject (NSToolbarDelegate) subclass 

/*
 Toolbar item names should be localized in "<toolbarName>.strings" in the same bundle as the .toolbar file.  Each display aspect of the item has its own key (currently 'label', 'paletteLabel', etc).  The search order for the localized name is:
 
 1: strings file "<toolbarName>" with key "<identifier>.<displayKey>"
 2: strings file "<toolbarName>" with key "<identifier>"
 3: item dictionary with key "<identifier>"; this is only for backwards compatibility and will hit an assertion
 
 */
static NSString *_displayName(NSBundle *bundle, NSString *stringsFileName, NSString *identifier, NSString *displayKey, NSDictionary *itemInfo, BOOL preferNilToFallback)
{
    NSString *key, *value;
    NSString *novalue = @" -NO VALUE- ";  // Hopefully no one will actually want to localize something to this value.
    
    key = [NSString stringWithFormat:@"%@.%@", identifier, displayKey];
    value = [bundle localizedStringForKey:key value:novalue table:stringsFileName];
    if (OFNOTEQUAL(novalue, value))
        return value;

    if (preferNilToFallback)
        return nil;

    key = identifier;
    value = [bundle localizedStringForKey:key value:novalue table:stringsFileName];
    if (OFNOTEQUAL(novalue, value))
        return value;
    
    key = displayKey;
    value = [itemInfo objectForKey:key]; // Grab the unlocalized display name out of the item dictionary
    OBASSERT(value == nil); // This assertion succeeds when a display key doesn't exist at all; it fails when its name is unlocalized
    return value;
}

static void copyProperty(NSToolbarItem *anItem,
                         NSString *propertyName,
                         NSBundle *bundle,
                         NSString *stringsFileName,
                         NSString *itemIdentifier,
                         NSDictionary *itemInfo,
                         NSString *specificItemDisplayName,
                         BOOL preferNilToFallback)
{
    NSString *value = _displayName(bundle, stringsFileName, itemIdentifier, propertyName, itemInfo, preferNilToFallback);
    
    if (!value)
        return;
    
    if (specificItemDisplayName != nil)
        value = [NSString stringWithFormat:value, specificItemDisplayName];
    
    [anItem setValue:value forKey:propertyName];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)willInsert;
{
    OAToolbarItem *newItem;
    NSDictionary *itemInfo;
    NSArray *sizes;
    NSObject <OAToolbarHelper> *helper = nil;
    NSString *extension, *value;
    NSImage *itemImage = nil;
    NSString *effectiveItemIdentifier;
    NSString *nameWithoutExtension;
    
    // Always use OAToolbarItem since we can't know up front whether we'll need a delegate or not.
    newItem = [[[[isa toolbarItemClass] alloc] initWithItemIdentifier:itemIdentifier] autorelease];
    
    NSBundle *bundle = [[self class] toolbarBundle];
    NSString *stringsFileName;
    
    stringsFileName = [toolbarStringsTables objectForKey:[self toolbarConfigurationName]];
    if (!stringsFileName)
        stringsFileName = [NSString stringWithFormat:@"%@Toolbar", [self toolbarConfigurationName]];
    
    if ((extension = [itemIdentifier pathExtension])) 
        helper = [helpersByExtension objectForKey:extension];

    if (helper) {
        effectiveItemIdentifier = [helper templateItemIdentifier];
        nameWithoutExtension = [[itemIdentifier lastPathComponent] stringByDeletingPathExtension];
    } else {
        effectiveItemIdentifier = itemIdentifier;
        nameWithoutExtension = nil;
    }
    
    itemInfo = [self toolbarInfoForItem:effectiveItemIdentifier];

    copyProperty(newItem, @"label",             bundle, stringsFileName, effectiveItemIdentifier, itemInfo, nameWithoutExtension, NO);
    copyProperty(newItem, @"toolTip",           bundle, stringsFileName, effectiveItemIdentifier, itemInfo, nameWithoutExtension, YES);
    copyProperty(newItem, @"optionKeyLabel",    bundle, stringsFileName, effectiveItemIdentifier, itemInfo, nameWithoutExtension, YES);
    copyProperty(newItem, @"optionKeyToolTip",  bundle, stringsFileName, effectiveItemIdentifier, itemInfo, nameWithoutExtension, YES);
    copyProperty(newItem, @"paletteLabel",      bundle, stringsFileName, effectiveItemIdentifier, itemInfo, nameWithoutExtension, NO);
    
    if (helper) {
        // let custom item have custom image
        NSString *customImageName = itemIdentifier;
        if ([customImageName containsString:@"/"])
            customImageName = [[customImageName pathComponents] componentsJoinedByString:@":"];
        
        itemImage = [NSImage tintedImageNamed:customImageName inBundle:bundle];
    }
    
    if ((value = [itemInfo objectForKey:@"customView"])) {
        // customView should map to a method or ivar on a subclass
        NSView *customView = [self valueForKey:value];
        OBASSERT(customView);
        
        [newItem setView:customView];
        
        // We have to provide validation for items with custom views.
        [newItem setDelegate:self];
        
        // Default to having the min size be the current size of the view and the max size unbounded.
        if (customView)
            [newItem setMinSize:customView.frame.size];
    }
    
    if ((value = [itemInfo objectForKey:@"target"])) {
        if ([value isEqualToString:@"firstResponder"])
            [newItem setTarget:nil];
        else 
            [newItem setTarget:[self valueForKeyPath:value]];
    } else
        [newItem setTarget:self];

    if ((value = [itemInfo objectForKey:@"action"]))
        [newItem setAction:NSSelectorFromString(value)];
    if ((value = [itemInfo objectForKey:@"optionKeyAction"]))
        [newItem setOptionKeyAction:NSSelectorFromString(value)];

    sizes = [itemInfo objectForKey:@"minSize"];
    if (sizes)
        [newItem setMinSize:NSMakeSize([[sizes objectAtIndex:0] cgFloatValue], [[sizes objectAtIndex:1] cgFloatValue])];
    sizes = [itemInfo objectForKey:@"maxSize"];
    if (sizes)
        [newItem setMaxSize:NSMakeSize([[sizes objectAtIndex:0] cgFloatValue], [[sizes objectAtIndex:1] cgFloatValue])];
    
    if (itemImage)
        [newItem setImage:itemImage];
    else {
        // Note: The way this is written means that an item can't have a custom image (from above) *and* an option image. Change this if that turns out to be desirable.
        NSString *itemImageName = [itemInfo objectForKey:@"imageName"];
        NSString *itemOptionImageName = [itemInfo objectForKey:@"optionKeyImageName"];
        if (itemImageName)
            [newItem setUsesTintedImage:itemImageName optionKeyImage:itemOptionImageName inBundle:bundle];
    }
        
    if (helper)
        [helper finishSetupForItem:newItem];
        
    return newItem;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
{
    NSEnumerator *enumerator;
    NSObject <OAToolbarHelper> *helper;
    NSMutableArray *results;
    
    results = [NSMutableArray arrayWithArray:[allowedToolbarItems objectForKey:[self toolbarConfigurationName]]];
    enumerator = [helpersByExtension objectEnumerator];
    while ((helper = [enumerator nextObject])) {
        NSUInteger itemIndex = [results indexOfObject:[helper templateItemIdentifier]];
        if (itemIndex == NSNotFound)
            continue;
        [results replaceObjectsInRange:NSMakeRange(itemIndex, 1) withObjectsFromArray:[helper allowedItems]];
    }
    return results;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
{
    return [defaultToolbarItems objectForKey:[self toolbarConfigurationName]];
}

// NSObject (NSToolbarItemValidation)

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem;
{
    return YES;
}

@end


@implementation OAToolbarWindowController (Private)

+ (void)_loadToolbarNamed:(NSString *)toolbarName;
{
    NSDictionary *toolbarPropertyList;

    if ([allowedToolbarItems objectForKey:toolbarName] != nil)
        return;

    NSBundle *bundle = [self toolbarBundle];
    
    NSString *toolbarPath = [bundle pathForResource:toolbarName ofType:@"toolbar"];
    if (!toolbarPath) {
	NSLog(@"Unable to locate %@.toolbar from %@", toolbarName, bundle);
	OBASSERT_NOT_REACHED("Unable to locate toolbar file");
	return;
    }
    
    toolbarPropertyList = [NSDictionary dictionaryWithContentsOfFile:toolbarPath];
    if (!toolbarPropertyList) {
	NSLog(@"Unable to load %@.toolbar from %@", toolbarName, toolbarPath);
	OBASSERT_NOT_REACHED("Unable to load toolbar file");
	return;
    }

    [ToolbarItemInfo setObject:[toolbarPropertyList objectForKey:@"itemInfoByIdentifier"] forKey:toolbarName];
    [allowedToolbarItems setObject:[toolbarPropertyList objectForKey:@"allowedItemIdentifiers"] forKey:toolbarName];
    [defaultToolbarItems setObject:[toolbarPropertyList objectForKey:@"defaultItemIdentifiers"] forKey:toolbarName];
    if ([toolbarPropertyList objectForKey:@"stringTable"])
        [toolbarStringsTables setObject:[toolbarPropertyList objectForKey:@"stringTable"] forKey:toolbarName];
}

@end
