// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPreferenceController.h>

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h> // For AESend
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OAApplication.h"
#import "NSBundle-OAExtensions.h"
#import "NSImage-OAExtensions.h"
#import "NSToolbar-OAExtensions.h"
#import "NSView-OAExtensions.h"
#import "OAPreferenceClient.h"
#import "OAPreferenceClientRecord.h"
#import "OAPreferencesIconView.h"
#import "OAPreferencesToolbar.h"
#import "OAPreferencesWindow.h"

RCS_ID("$Id$") 

static OAPreferenceClientRecord *_ClientRecordWithValueForKey(NSArray *records, NSString *key, NSString *value)
{
    OBPRECONDITION(value != nil);
    unsigned int clientRecordIndex = [records count];
    while (clientRecordIndex--) {
	OAPreferenceClientRecord *clientRecord = [records objectAtIndex:clientRecordIndex];
	if ([[clientRecord valueForKey:key] isEqualToString:value])
	    return clientRecord;
    }
    return nil;											\
}

@interface OAPreferenceController (Private)
- (void)_loadInterface;
- (void)_createShowAllItemsView;
- (void)_setupMultipleToolbar;
#if !defined(MAC_OS_X_VERSION_10_6) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6)
- (void)_setupCustomizableToolbar;
#endif
- (void)_resetWindowTitle;
- (OAPreferenceClient *)_clientForRecord:(OAPreferenceClientRecord *)record;
- (void)_showAllIcons:(id)sender;
- (void)_defaultsDidChange:(NSNotification *)notification;
//
- (NSArray *)_categoryNames;
- (NSArray *)_sortedClientRecords;
+ (void)_registerCategoryName:(NSString *)categoryName localizedName:(NSString *)localizedCategoryName priorityNumber:(NSNumber *)priorityNumber;
+ (NSString *)_localizedCategoryNameForCategoryName:(NSString *)categoryName;
+ (float)_priorityForCategoryName:(NSString *)categoryName;
//
+ (void)_registerClassName:(NSString *)className inCategoryNamed:(NSString *)categoryName description:(NSDictionary *)description;
@end

@interface NSToolbar (KnownPrivateMethods)
- (NSView *)_toolbarView;
- (void)setSelectedItemIdentifier:(NSString *)itemIdentifier; // Panther only
@end

@implementation OAPreferenceController

static NSMutableArray *AllClientRecords = nil;
static NSMutableDictionary *LocalizedCategoryNames = nil;
static NSMutableDictionary *CategoryPriorities = nil;
static NSString *windowFrameSaveName = @"Preferences";

+ (void)initialize;
{
    OBINITIALIZE;
    
    AllClientRecords = [[NSMutableArray alloc] init];
    LocalizedCategoryNames = [[NSMutableDictionary alloc] init];
    CategoryPriorities = [[NSMutableDictionary alloc] init];
    
#ifdef DEBUG
    // Debugging aid; if we have this preference, show the pane.  Not doing the whole OF controller thing to get this done; just a simple hack to let the preference panes get registered.
    NSString *paneID = [[NSUserDefaults standardUserDefaults] stringForKey:@"OAPreferenceClientToShowOnLaunch"];
    if (![NSString isEmptyString:paneID])
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_showPane:) userInfo:paneID repeats:NO];
#endif
}

#ifdef DEBUG
+ (void)_showPane:(NSTimer *)timer;
{
    OAPreferenceController *controller = [OAPreferenceController sharedPreferenceController];

    NSString *identifier = [timer userInfo];
    OAPreferenceClientRecord *record = [controller clientRecordWithIdentifier:identifier];
    if (!record) {
        NSLog(@"No pane '%@'", identifier);
        return;
    }
    
    [controller setCurrentClientRecord:record];
    [controller showPreferencesPanel:nil];
}
#endif

// OFBundleRegistryTarget informal protocol

+ (NSString *)overrideNameForCategoryName:(NSString *)categoryName;
{
    return categoryName;
}

+ (NSString *)overrideLocalizedNameForCategoryName:(NSString *)categoryName bundle:(NSBundle *)bundle;
{
    return [bundle localizedStringForKey:categoryName value:@"" table:@"Preferences"];
}

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    OBPRECONDITION(AllClientRecords != nil); // +initialize
    
    [OFBundledClass createBundledClassWithName:itemName bundle:bundle description:description];

    NSString *categoryName;
    if ((categoryName = [description objectForKey:@"category"]) == nil)
        categoryName = @"UNKNOWN";
        
    categoryName = [self overrideNameForCategoryName:categoryName];
    NSString *localizedCategoryName = [self overrideLocalizedNameForCategoryName:categoryName bundle:bundle];
        
    [self _registerCategoryName:categoryName localizedName:localizedCategoryName priorityNumber:[description objectForKey:@"categoryPriority"]];
    [self _registerClassName:itemName inCategoryNamed:categoryName description:description];
}

+ (OAPreferenceController *)sharedPreferenceController;
{
    static OAPreferenceController *sharedPreferenceController = nil;
    if (sharedPreferenceController == nil)
        sharedPreferenceController = [[self alloc] init];
    
    return sharedPreferenceController;
}

+ (NSArray *)allClientRecords;
{
    return AllClientRecords;
}

+ (OAPreferenceClientRecord *)clientRecordWithShortTitle:(NSString *)shortTitle;
{
    return _ClientRecordWithValueForKey(AllClientRecords, @"shortTitle", shortTitle);
}

+ (OAPreferenceClientRecord *)clientRecordWithIdentifier:(NSString *)identifier;
{
    return _ClientRecordWithValueForKey(AllClientRecords, @"identifier", identifier);
}

// Init and dealloc

- init;
{
    return [self initWithClientRecords:AllClientRecords defaultKeySuffix:nil];
}

- initWithClientRecords:(NSArray *)clientRecords defaultKeySuffix:(NSString *)defaultKeySuffix;
{
    OBPRECONDITION([clientRecords count]);
    
    if (!(self = [super init]))
	return nil;
    
    categoryNamesToClientRecordsArrays = [[NSMutableDictionary alloc] init];
    _clientRecords = [[NSArray alloc] initWithArray:clientRecords];
    _clientByRecordIdentifier = [[NSMutableDictionary alloc] init];
    _defaultKeySuffix = [defaultKeySuffix copy];
    preferencesIconViews = [[NSMutableArray alloc] init];
    
    unsigned int recordIndex, recordCount = [_clientRecords count];
    for (recordIndex = 0; recordIndex < recordCount; recordIndex++) {
	OAPreferenceClientRecord *record = [_clientRecords objectAtIndex:recordIndex];
	NSString *categoryName = [record categoryName];
	
	NSMutableArray *categoryClientRecords = [categoryNamesToClientRecordsArrays objectForKey:categoryName];
	if (categoryClientRecords == nil) {
	    categoryClientRecords = [NSMutableArray array];
	    [categoryNamesToClientRecordsArrays setObject:categoryClientRecords forKey:categoryName];
	}
	[categoryClientRecords insertObject:record inArraySortedUsingSelector:@selector(compareOrdering:)];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_defaultsDidChange:) name:NSUserDefaultsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_modifierFlagsChanged:) name:OAFlagsChangedNotification object:nil];
    return self;
}

- (void)dealloc;
{
    [window release];
    // preferenceBox contained in window
    [globalControlsView release]; // top level nib object
    // helpButton contained in globalControlsView
    // returnToOriginalValuesButton contained in globalControlsView
    
    [showAllIconsView release];
    [multipleIconView release];
    [preferencesIconViews release];
    [categoryNamesToClientRecordsArrays release];
    [_clientRecords release];
    [_clientByRecordIdentifier release];
    [_defaultKeySuffix release];
    [toolbar release];
    [defaultToolbarItems release];
    [allowedToolbarItems release];
    
    [super dealloc];
}


// API

- (void)close;
{
    if ([window isVisible])
        [window performClose:nil];
}

- (NSWindow *)window;  // in case you want to do something nefarious to it like change its level, as OmniGraffle does
{
    [self _loadInterface];
    return window;
}

- (NSWindow *)windowIfLoaded; // doesn't for load the window
{
    return window;
}

- (void)setTitle:(NSString *)title;
{
    [window setTitle:title];
}

// Setting the current preference client

- (void)setCurrentClientByClassName:(NSString *)name;
{
    unsigned int clientRecordIndex;
    
    clientRecordIndex = [_clientRecords count];
    while (clientRecordIndex--) {
        OAPreferenceClientRecord *clientRecord;

        clientRecord = [_clientRecords objectAtIndex:clientRecordIndex];
        if ([[clientRecord className] isEqualToString:name]) {
            [self setCurrentClientRecord:clientRecord];
            return;
        }
    }
}

- (void)setCurrentClientRecord:(OAPreferenceClientRecord *)clientRecord
{
    NSView *contentView, *controlBox;
    unsigned int newWindowHeight;
    NSRect controlBoxFrame, windowFrame, newWindowFrame;
    NSView *oldView;
    
    if (nonretained_currentClientRecord == clientRecord)
        return;
    
    // Save changes in any editing text fields
    [window setInitialFirstResponder:nil];
    [window makeFirstResponder:nil];
    
    // Only do this when we are on screen to avoid sending become/resign twice.  If we are off screen, the client got resigned when it went off and the new one will get a become when it goes on screen.
    if ([window isVisible])
        [nonretained_currentClient resignCurrentPreferenceClient];
    
    nonretained_currentClientRecord = clientRecord;
    nonretained_currentClient = [self _clientForRecord:clientRecord];
    
    [self _resetWindowTitle];
    
    // Remove old client box
    contentView = [preferenceBox contentView];
    oldView = [[contentView subviews] lastObject];
    [oldView removeFromSuperview];
    
    // Only do this when we are on screen to avoid sending become/resign twice.  If we are off screen, the client got resigned when it went off and the new one will get a become when it goes on screen.

    // As above, don't do this unless we are onscreen to avoid double become/resigns.
    if ([window isVisible])
        [nonretained_currentClient willBecomeCurrentPreferenceClient];

    // Resize window for the new client box, after letting the client know that it's about to become current
    controlBox = [nonretained_currentClient controlBox];
    // It's an error for controlBox to be nil, but it's pretty unfriendly to resize our window to be infinitely high when that happens.
    controlBoxFrame = controlBox != nil ? [controlBox frame] : NSZeroRect;
    
    // Resize the window
    // We don't just tell the window to resize, because that tends to move the upper left corner (which will confuse the user)
    windowFrame = [NSWindow contentRectForFrameRect:[window frame] styleMask:[window styleMask]];
    newWindowHeight = NSHeight(controlBoxFrame) + NSHeight([globalControlsView frame]);    
    if ([toolbar isVisible])
        newWindowHeight += NSHeight([[toolbar _toolbarView] frame]); 
    
    newWindowFrame = [NSWindow frameRectForContentRect:NSMakeRect(NSMinX(windowFrame), NSMaxY(windowFrame) - newWindowHeight, MAX(idealWidth, NSWidth(controlBoxFrame)), newWindowHeight) styleMask:[window styleMask]];
    [window setFrame:newWindowFrame display:YES animate:[window isVisible]];
    
    // Do this before putting the view in the view hierarchy to avoid flashiness in the controls.
    if ([window isVisible])
        [self validateRestoreDefaultsButton];

    [nonretained_currentClient updateUI];
    
    // set up the global controls view
    if (helpButton)
        [helpButton setEnabled:([nonretained_currentClientRecord helpURL] != nil)];        
    [contentView addSubview:globalControlsView];
    
    // Add the new client box to the view hierarchy
    [controlBox setFrameOrigin:NSMakePoint(floor((NSWidth([contentView frame]) - NSWidth(controlBoxFrame)) / 2.0), NSHeight([globalControlsView frame]))];
    [contentView addSubview:controlBox];
    
    // Highlight the initial first responder, and also tell the window what it should be because I think there is some voodoo with nextKeyView not working unless the window has an initial first responder.
    [window setInitialFirstResponder:[nonretained_currentClient initialFirstResponder]];
    NSView *initialKeyView = [nonretained_currentClient initialFirstResponder];
    if (initialKeyView != nil && ![initialKeyView canBecomeKeyView])
        initialKeyView = [initialKeyView nextValidKeyView];
    [window makeFirstResponder:initialKeyView];
    
    // Hook up the pane's keyView loop to ours.  returnToOriginalValuesButton is always present, but the help button might get removed if there is no help URL for this pane.
    [[nonretained_currentClient lastKeyView] setNextKeyView:returnToOriginalValuesButton];
    if (helpButton) {
	OBASSERT([returnToOriginalValuesButton nextKeyView] == helpButton); // set in nib
	[helpButton setNextKeyView:[nonretained_currentClient initialFirstResponder]];
    }
    
    // As above, don't do this unless we are onscreen to avoid double become/resigns.
    if ([window isVisible]) {
        [nonretained_currentClient didBecomeCurrentPreferenceClient];
    }
}

- (NSArray *)clientRecords;
{
    return _clientRecords;
}

- (NSString *)defaultKeySuffix;
{
    return _defaultKeySuffix;
}

- (OAPreferenceClientRecord *)clientRecordWithShortTitle:(NSString *)shortTitle;
{
    return _ClientRecordWithValueForKey(_clientRecords, @"shortTitle", shortTitle);
}

- (OAPreferenceClientRecord *)clientRecordWithIdentifier:(NSString *)identifier;
{
    return _ClientRecordWithValueForKey(_clientRecords, @"identifier", identifier);
}

- (OAPreferenceClient *)clientWithShortTitle:(NSString *)shortTitle;
{
    return [self _clientForRecord:[self clientRecordWithShortTitle: shortTitle]];
}

- (OAPreferenceClient *)clientWithIdentifier:(NSString *)identifier;
{
    return [self _clientForRecord:[self clientRecordWithIdentifier: identifier]];
}

- (OAPreferenceClient *)currentClient;
{
    return nonretained_currentClient;
}

- (void)iconView:(OAPreferencesIconView *)iconView buttonHitAtIndex:(unsigned int)index;
{
    [self setCurrentClientRecord:[[iconView preferenceClientRecords] objectAtIndex:index]];
}

- (void)validateRestoreDefaultsButton;
{
    [returnToOriginalValuesButton setEnabled:[nonretained_currentClient haveAnyDefaultsChanged]];
}

// Actions

- (IBAction)showPreferencesPanel:(id)sender;
{
    OBPRECONDITION([_clientRecords count] > 0); // did you forget to register your clients?

    // We'll avoid sending -will/-didBecomeCurrentPreferenceClient when the current client already has become the current client and hasn't received a -resignCurrentPreferenceClient.  We'll still update the UI on the client since we used to do that before this fix was made and it might be useful in some cases where external changes can be made to preferences.
    BOOL wasVisible = [window isVisible];

    if (!wasVisible) {
	[self _loadInterface];
	[self _resetWindowTitle];
	
	// Let the current client know that it is about to be displayed.
	[nonretained_currentClient willBecomeCurrentPreferenceClient];
    }
    
    [self validateRestoreDefaultsButton];
    [nonretained_currentClient updateUI];
    [window makeKeyAndOrderFront:sender];
    
    if (!wasVisible) {
	[nonretained_currentClient didBecomeCurrentPreferenceClient];
    }
}

- (IBAction)restoreDefaults:(id)sender;
{
    if (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) && ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask)) {
        // warn & wipe the entire defaults domain
        NSString *mainPrompt, *secondaryPrompt, *defaultButton, *otherButton;
        NSBundle *bundle;

        bundle = [OAPreferenceClient bundle];
        mainPrompt = NSLocalizedStringFromTableInBundle(@"Reset all preferences and other settings to their original values?", @"OmniAppKit", bundle, "message text for reset-to-defaults alert");
        secondaryPrompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choosing Reset will restore all settings (including options not in this Preferences window, such as window sizes and toolbars) to the state they were in when %@ was first installed.", @"OmniAppKit", bundle, "informative text for reset-to-defaults alert"), [[NSProcessInfo processInfo] processName]];
        defaultButton = NSLocalizedStringFromTableInBundle(@"Reset", @"OmniAppKit", bundle, "alert panel button");
        otherButton = NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", bundle, "alert panel button");
        NSBeginAlertSheet(mainPrompt, defaultButton, otherButton, nil, window, self, NULL, @selector(_restoreDefaultsSheetDidEnd:returnCode:contextInfo:), @"RestoreEverything", secondaryPrompt);
    } else if ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) {
        // warn & wipe all prefs shown in the panel
        NSString *mainPrompt, *secondaryPrompt, *defaultButton, *otherButton;
        NSBundle *bundle;

        bundle = [OAPreferenceClient bundle];
        mainPrompt = NSLocalizedStringFromTableInBundle(@"Reset all preferences to their original values?", @"OmniAppKit", bundle, "message text for reset-to-defaults alert");
        secondaryPrompt = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choosing Reset will restore all settings in all preference panes to the state they were in when %@ was first installed.", @"OmniAppKit", bundle, "informative text for reset-to-defaults alert"), [[NSProcessInfo processInfo] processName]];
        defaultButton = NSLocalizedStringFromTableInBundle(@"Reset", @"OmniAppKit", bundle, "alert panel button");
        otherButton = NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", bundle, "alert panel button");
        NSBeginAlertSheet(mainPrompt, defaultButton, otherButton, nil, window, self, NULL, @selector(_restoreDefaultsSheetDidEnd:returnCode:contextInfo:), NULL, secondaryPrompt);
    } else {
        // OAPreferenceClient will handle warning & reverting
        [nonretained_currentClient restoreDefaults:sender];
    }
}

- (IBAction)showNextClient:(id)sender;
{
    NSArray *sortedClientRecords = [self _sortedClientRecords];
    
    NSUInteger currentIndex = [sortedClientRecords indexOfObject:nonretained_currentClientRecord];
    if (currentIndex != NSNotFound && currentIndex+1 < [sortedClientRecords count])
        [self setCurrentClientRecord:[sortedClientRecords objectAtIndex:currentIndex+1]];
    else
        [self setCurrentClientRecord:[sortedClientRecords objectAtIndex:0]];
}

- (IBAction)showPreviousClient:(id)sender;
{
    NSArray *sortedClientRecords = [self _sortedClientRecords];

    NSUInteger currentIndex = [sortedClientRecords indexOfObject:nonretained_currentClientRecord];
    if (currentIndex != NSNotFound && currentIndex > 0)
        [self setCurrentClientRecord:[sortedClientRecords objectAtIndex:currentIndex-1]];
    else
        [self setCurrentClientRecord:[sortedClientRecords lastObject]];
}

- (IBAction)setCurrentClientFromToolbarItem:(id)sender;
{
    [self setCurrentClientRecord:[self clientRecordWithIdentifier:[sender itemIdentifier]]];
}

- (IBAction)showHelpForClient:(id)sender;
{
    NSString *helpURL = [nonretained_currentClientRecord helpURL];
    
    if (helpURL)
        [NSApp showHelpURL:helpURL];
}

// NSWindow delegate

- (void)windowWillClose:(NSNotification *)notification;
{
    [[notification object] makeFirstResponder:nil];
    [nonretained_currentClient resignCurrentPreferenceClient];

    // Save settings immediately when closing the window
    [[OFPreferenceWrapper sharedPreferenceWrapper] synchronize];
}

- (void)windowDidResignKey:(NSNotification *)notification;
{
    [[notification object] makeFirstResponder:nil];
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client;
{
    if ([nonretained_currentClient respondsToSelector:_cmd])
	return [nonretained_currentClient performSelector:_cmd withObject:sender withObject:client];
    return nil;
}

// NSToolbar delegate (We use an NSToolbar in OAPreferencesViewCustomizable)

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag;
{
    NSToolbarItem *newItem;

    newItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
    [newItem setTarget:self];
    if ([itemIdentifier isEqualToString:@"OAPreferencesShowAll"]) {
        [newItem setAction:@selector(_showAllIcons:)];
        [newItem setLabel:NSLocalizedStringFromTableInBundle(@"Show All", @"OmniAppKit", [OAPreferenceController bundle], "preferences panel button")];
        [newItem setImage:[NSImage imageNamed:@"NSApplicationIcon"]];
    } else if ([itemIdentifier isEqualToString:@"OAPreferencesNext"]) {
        [newItem setAction:@selector(showNextClient:)];
        [newItem setLabel:NSLocalizedStringFromTableInBundle(@"Next", @"OmniAppKit", [OAPreferenceController bundle], "preferences panel button")];
        [newItem setImage:[NSImage imageNamed:@"OAPreferencesNextButton" inBundleForClass:[OAPreferenceController class]]];
        [newItem setEnabled:NO]; // the first time these get added, we'll be coming up in "show all" mode, so they'll immediately diable anyway...
    } else if ([itemIdentifier isEqualToString:@"OAPreferencesPrevious"]) {
        [newItem setAction:@selector(showPreviousClient:)];
        [newItem setLabel:NSLocalizedStringFromTableInBundle(@"Previous", @"OmniAppKit", [OAPreferenceController bundle], "preferences panel button")];
        [newItem setImage:[NSImage imageNamed:@"OAPreferencesPreviousButton" inBundleForClass:[OAPreferenceController class]]];
        [newItem setEnabled:NO]; // ... so we disable them now to prevent visible flickering.
    } else { // it's for a preference client
        if ([self clientRecordWithIdentifier:itemIdentifier] == nil)
            return nil;
        
        [newItem setAction:@selector(setCurrentClientFromToolbarItem:)];
        [newItem setLabel:[[self clientRecordWithIdentifier:itemIdentifier] shortTitle]];
        [newItem setImage:[[self clientRecordWithIdentifier:itemIdentifier] iconImage]];
    }
    return newItem;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
{
    return defaultToolbarItems;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
{
    return allowedToolbarItems;
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar;
{
    return allowedToolbarItems;
}

// NSToolbar validation
- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem;
{
    NSString *itemIdentifier;
    
    itemIdentifier = [theItem itemIdentifier];
    if ([itemIdentifier isEqualToString:@"OAPreferencesPrevious"] || [itemIdentifier isEqualToString:@"OAPreferencesNext"])
        return (nonretained_currentClientRecord != nil);
    
    return YES;
}

// NSMenuItemValidation informal protocol

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    SEL action;
    
    action = [item action];
    if (action == @selector(runToolbarCustomizationPalette:))
        return NO;
        
    return YES;
}

@end


@implementation OAPreferenceController (Private)

- (void)_loadInterface;
{
    if (window != nil)
        return;    

    [[OAPreferenceController bundle] loadNibNamed:@"OAPreferences.nib" owner:self];

    // These don't seem to get set by the nib.  We want autosizing on so that clients can resize the window by a delta (though it'd be nicer for us to have API for that).
    [preferenceBox setAutoresizesSubviews:YES];
    [[preferenceBox contentView] setAutoresizingMask:[preferenceBox autoresizingMask]];
    [[preferenceBox contentView] setAutoresizesSubviews:YES];
    
    // TJW: Is this really necessary -- it's a top level nib object.
    [globalControlsView retain];
    idealWidth = NSWidth([globalControlsView frame]);
    [window center];
    [window setFrameAutosaveName:windowFrameSaveName];
    [window setFrameUsingName:windowFrameSaveName force:YES];
    
    if (![[_clientRecords objectAtIndex:0] helpURL]) {
        [helpButton removeFromSuperview];
        helpButton = nil;
    }
    
    if ([_clientRecords count] == 1) {
        viewStyle = OAPreferencesViewSingle;
        [toolbar setVisible:NO];
    } else if ([_clientRecords count] > 10 || [[self _categoryNames] count] > 1) {
        viewStyle = OAPreferencesViewCustomizable;
    } else {
        viewStyle = OAPreferencesViewMultiple;
    }

    // The previous call to -setCurrentClientRecord: won't have set up the UI since the UI wasn't loaded.  Also, since the UI wasn't loaded before, the client won't have received a -becomeCurrentPreferenceClient, so we don't need to worry about calling -resignCurrentPreferenceClient before setting this to nil to avoid a duplicate -becomeCurrentPreferenceClient.
    OAPreferenceClientRecord *initialClientRecord = nonretained_currentClientRecord;
    nonretained_currentClientRecord = nil;

    switch (viewStyle) {
        case OAPreferencesViewSingle:
	    if (!initialClientRecord)
		initialClientRecord = [_clientRecords lastObject];
            break;
#if !defined(MAC_OS_X_VERSION_10_6) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6)
        case OAPreferencesViewCustomizable:
            [self _createShowAllItemsView];
            [self _setupCustomizableToolbar];
            [self _showAllIcons:nil];
            break;
#endif
	default:
        case OAPreferencesViewMultiple:
	    [_clientRecords autorelease];
	    _clientRecords = [[_clientRecords sortedArrayUsingSelector:@selector(compareOrdering:)] retain];
            [self _setupMultipleToolbar];
	    if (!initialClientRecord)
		initialClientRecord = [_clientRecords objectAtIndex:0];
            break;
    }

    [self setCurrentClientRecord:initialClientRecord];
}

- (void)_createShowAllItemsView;
{
    const unsigned int verticalSpaceBelowTextField = 4, verticalSpaceAboveTextField = 7, sideMargin = 12;
    unsigned int boxHeight = 12;
    NSArray *categoryNames;
    unsigned int categoryIndex;

    showAllIconsView = [[NSView alloc] initWithFrame:NSZeroRect];

    // This is lame.  We should really think up some way to specify the ordering of preferences in the plists.  But this is difficult since preferences can come from many places.
    categoryNames = [self _categoryNames];
    categoryIndex = [categoryNames count];
    while (categoryIndex--) {
        NSString *categoryName;
        NSArray *categoryClientRecords;
        OAPreferencesIconView *preferencesIconView;
        NSTextField *categoryHeaderTextField;

        categoryName = [categoryNames objectAtIndex:categoryIndex];
        categoryClientRecords = [categoryNamesToClientRecordsArrays objectForKey:categoryName];

        // category preferences view
        preferencesIconView = [[OAPreferencesIconView alloc] initWithFrame:[preferenceBox bounds]];
        [preferencesIconView setPreferenceController:self];
        [preferencesIconView setPreferenceClientRecords:categoryClientRecords];

        [showAllIconsView addSubview:preferencesIconView];
        [preferencesIconView setFrameOrigin:NSMakePoint(0, boxHeight)];
        [preferencesIconViews addObject:preferencesIconView];

        boxHeight += NSHeight([preferencesIconView frame]);
        [preferencesIconView release];

        // category header
        categoryHeaderTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        [categoryHeaderTextField setDrawsBackground:NO];
        [categoryHeaderTextField setBordered:NO];
        [categoryHeaderTextField setEditable:NO];
        [categoryHeaderTextField setSelectable:NO];
        [categoryHeaderTextField setTextColor:[NSColor controlTextColor]];
        [categoryHeaderTextField setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
        [categoryHeaderTextField setAlignment:NSLeftTextAlignment];
        [categoryHeaderTextField setStringValue:[isa _localizedCategoryNameForCategoryName:categoryName]];
        [categoryHeaderTextField sizeToFit];
        [showAllIconsView addSubview:categoryHeaderTextField];
        [categoryHeaderTextField setFrame:NSMakeRect(sideMargin, boxHeight + verticalSpaceBelowTextField, NSWidth([preferenceBox bounds]) - sideMargin, NSHeight([categoryHeaderTextField frame]))];

        boxHeight += NSHeight([categoryHeaderTextField frame]) + verticalSpaceAboveTextField;
        [categoryHeaderTextField release];

        if (categoryIndex != 0) {
            NSBox *separator;
            const unsigned int separatorMargin = 15;

            separator = [[NSBox alloc] initWithFrame:NSMakeRect(separatorMargin, boxHeight + verticalSpaceBelowTextField, NSWidth([preferenceBox bounds]) - separatorMargin - separatorMargin, 1)];
            [separator setBoxType:NSBoxSeparator];
            [showAllIconsView addSubview:separator];
            [separator release];
            
            boxHeight += verticalSpaceAboveTextField + verticalSpaceBelowTextField;
        }
        boxHeight += verticalSpaceBelowTextField + 1;
    }

    [showAllIconsView setFrameSize:NSMakeSize(NSWidth([preferenceBox bounds]), boxHeight)];
}

// See <bug://50034> Stop using private API in OAPreferenceController on behalf of OmniWeb's preference panel
- (void)_setupMultipleToolbar;
{
    NSMutableArray *allClients;

    allClients = [[_clientRecords valueForKey:@"identifier"] copy];
    allowedToolbarItems = [allClients retain];
    defaultToolbarItems = [allClients retain];
    [allClients release];
    
    toolbar = [[OAPreferencesToolbar alloc] initWithIdentifier:@"OAPreferences"];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO]; // Don't store the configured items or new items won't show up!
    [toolbar setDelegate:self];
#if !defined(MAC_OS_X_VERSION_10_6) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6)
    [toolbar setShowsContextMenu:NO];
#endif
    [window setToolbar:toolbar];
}

#if !defined(MAC_OS_X_VERSION_10_6) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6)
- (void)_setupCustomizableToolbar;
{
    NSArray *constantToolbarItems, *defaultClients, *allClients;

    constantToolbarItems = [NSArray arrayWithObjects:
        @"OAPreferencesShowAll", @"OAPreferencesPrevious", @"OAPreferencesNext", NSToolbarSeparatorItemIdentifier,
        nil];

    defaultClients = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FavoritePreferenceIdentifiers"];

    allClients = [_clientRecords valueForKey:@"identifier"];

    defaultToolbarItems = [[constantToolbarItems arrayByAddingObjectsFromArray:defaultClients] retain];
    allowedToolbarItems = [[constantToolbarItems arrayByAddingObjectsFromArray:allClients] retain];

    toolbar = [[OAPreferencesToolbar alloc] initWithIdentifier:@"OAPreferenceIdentifiers"];
    [toolbar setAllowsUserCustomization:YES];
    [toolbar setAutosavesConfiguration:YES];
    [toolbar setDelegate:self];
    [toolbar setAlwaysCustomizableByDrag:YES];
    [toolbar setShowsContextMenu:NO];
    [window setToolbar:toolbar];
    [toolbar setIndexOfFirstMovableItem:4]; // first four items are always ShowAll, Previous, Next, and Separator
}
#endif

- (void)_resetWindowTitle;
{
    NSString *name = nil;
    
    if (viewStyle != OAPreferencesViewSingle) {
        name = [nonretained_currentClientRecord title];
        if ([toolbar respondsToSelector:@selector(setSelectedItemIdentifier:)]) {
            if (nonretained_currentClientRecord != nil)
                [toolbar setSelectedItemIdentifier:[nonretained_currentClientRecord identifier]];
            else
                [toolbar setSelectedItemIdentifier:@"OAPreferencesShowAll"];
        }
    }
    if (name == nil || [name isEqualToString:@""])
        name = [[NSProcessInfo processInfo] processName];
    [window setTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ Preferences", @"OmniAppKit", [OAPreferenceController bundle], "preferences panel title format"), name]];
}

- (OAPreferenceClient *)_clientForRecord:(OAPreferenceClientRecord *)record;
{
    OBPRECONDITION(record);
    if (!record)
	return nil;
    
    NSString *identifier = [record identifier];
    OAPreferenceClient *client = [_clientByRecordIdentifier objectForKey:identifier];
    if (!client) {
	client = [record newClientInstanceInController:self];
	[_clientByRecordIdentifier setObject:client forKey:identifier];
	[client release];
    }
    return client;
}

- (void)_showAllIcons:(id)sender;
{
    NSRect windowFrame, newWindowFrame;
    unsigned int newWindowHeight;

    // Are we already showing?
    if ([[[preferenceBox contentView] subviews] lastObject] == showAllIconsView)
        return;

    // Save changes in any editing text fields
    [window setInitialFirstResponder:nil];
    [window makeFirstResponder:nil];

    // Clear out current preference and reset window title
    nonretained_currentClientRecord = nil;
    nonretained_currentClient = nil;
    [[[preferenceBox contentView] subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self _resetWindowTitle];
        
    // Resize window
    windowFrame = [NSWindow contentRectForFrameRect:[window frame] styleMask:[window styleMask]];
    newWindowHeight = NSHeight([showAllIconsView frame]);
    if ([toolbar isVisible])
        newWindowHeight += NSHeight([[toolbar _toolbarView] frame]);
    newWindowFrame = [NSWindow frameRectForContentRect:NSMakeRect(NSMinX(windowFrame), NSMaxY(windowFrame) - newWindowHeight, idealWidth, newWindowHeight) styleMask:[window styleMask]];
    [window setFrame:newWindowFrame display:YES animate:[window isVisible]];

    // Add new icons view
    [preferenceBox addSubview:showAllIconsView];
}

- (void)_defaultsDidChange:(NSNotification *)notification;
{
    if ([window isVisible]) {
        // Do this later since this gets called inside a lock that we need
        [self queueSelector:@selector(validateRestoreDefaultsButton)];
    }
}

- (void)_modifierFlagsChanged:(NSNotification *)note;
{
    BOOL optionDown = ([[note object] modifierFlags] & NSAlternateKeyMask) ? YES : NO;

    if (optionDown) {
        [returnToOriginalValuesButton setEnabled:YES];
        [returnToOriginalValuesButton setTitle:NSLocalizedStringFromTableInBundle(@"Reset All", @"OmniAppKit", [OAPreferenceController bundle], "reset-to-defaults button title")];
        [returnToOriginalValuesButton setToolTip:NSLocalizedStringFromTableInBundle(@"Return all settings to default values", @"OmniAppKit", [OAPreferenceController bundle], "reset-to-defaults button tooltip")];
    } else {
        [returnToOriginalValuesButton setEnabled:[nonretained_currentClient haveAnyDefaultsChanged]];
        [returnToOriginalValuesButton setTitle:NSLocalizedStringFromTableInBundle(@"Reset", @"OmniAppKit", [OAPreferenceController bundle], "reset-to-defaults button title")];
        [returnToOriginalValuesButton setToolTip:NSLocalizedStringFromTableInBundle(@"Return settings in this pane to default values", @"OmniAppKit", [OAPreferenceController bundle], "reset-to-defaults button tooltip")];
    }
}

- (void)_restoreDefaultsSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode != NSAlertDefaultReturn)
        return;

    if (contextInfo != NULL) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSEnumerator *clientEnumerator;
        OAPreferenceClientRecord *aClientRecord;
        
        clientEnumerator = [[self clientRecords] objectEnumerator];
        while ((aClientRecord = [clientEnumerator nextObject])) {
            NSArray *preferenceKeys;
            NSEnumerator *keyEnumerator;
            NSString *aKey;

            preferenceKeys = [[NSArray array] arrayByAddingObjectsFromArray:[[aClientRecord defaultsDictionary] allKeys]];
            preferenceKeys = [preferenceKeys arrayByAddingObjectsFromArray:[aClientRecord defaultsArray]];
            keyEnumerator = [preferenceKeys objectEnumerator];
            while ((aKey = [keyEnumerator nextObject])) 
                [[OFPreference preferenceForKey:aKey] restoreDefaultValue];
        }
    }
    [nonretained_currentClient valuesHaveChanged];
}

// 

static NSComparisonResult OAPreferenceControllerCompareCategoryNames(id name1, id name2, void *context)
{
    Class cls = context;
    
    float priority1 = [cls _priorityForCategoryName:name1];
    float priority2 = [cls _priorityForCategoryName:name2];
    if (priority1 == priority2)
        return [[cls _localizedCategoryNameForCategoryName:name1] caseInsensitiveCompare:[cls _localizedCategoryNameForCategoryName:name2]];
    else if (priority1 > priority2)
        return NSOrderedAscending;
    else // priority1 < priority2
        return NSOrderedDescending;
}

- (NSArray *)_categoryNames;
{
    return [[categoryNamesToClientRecordsArrays allKeys] sortedArrayUsingFunction:OAPreferenceControllerCompareCategoryNames context:isa];
}

- (NSArray *)_sortedClientRecords;
{
    NSMutableArray *sortedClientRecords = [NSMutableArray array];
    for(NSString *categoryName in [self _categoryNames])
        [sortedClientRecords addObjectsFromArray:[categoryNamesToClientRecordsArrays objectForKey:categoryName]];
    return sortedClientRecords;
}

+ (void)_registerCategoryName:(NSString *)categoryName localizedName:(NSString *)localizedCategoryName priorityNumber:(NSNumber *)priorityNumber;
{
    if (localizedCategoryName != nil && ![localizedCategoryName isEqualToString:categoryName])
        [LocalizedCategoryNames setObject:localizedCategoryName forKey:categoryName];
    if (priorityNumber != nil)
        [CategoryPriorities setObject:priorityNumber forKey:categoryName];
}

+ (NSString *)_localizedCategoryNameForCategoryName:(NSString *)categoryName;
{
    return [LocalizedCategoryNames objectForKey:categoryName defaultObject:categoryName];
}

+ (float)_priorityForCategoryName:(NSString *)categoryName;
{
    NSNumber *priority;

    priority = [CategoryPriorities objectForKey:categoryName];
    if (priority != nil)
        return [priority floatValue];
    else
        return 0.0;
}

+ (void)_registerClassName:(NSString *)className inCategoryNamed:(NSString *)categoryName description:(NSDictionary *)description;
{
    OAPreferenceClientRecord *newRecord;
    NSDictionary *defaultsDictionary;
    NSString *titleEnglish, *title, *iconName, *nibName, *identifier, *shortTitleEnglish, *shortTitle;
    NSBundle *classBundle = [OFBundledClass bundleForClassNamed:className];

    defaultsDictionary = [description objectForKey:@"defaultsDictionary"];
    if (defaultsDictionary)
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsDictionary];
    else
        defaultsDictionary = [NSDictionary dictionary]; // placeholder
    
    NSString *minimumOSVersionString = [description objectForKey:@"minimumOSVersion"];
    if (![NSString isEmptyString:minimumOSVersionString]) {
	OFVersionNumber *minimumOSVersion = [[OFVersionNumber alloc] initWithVersionString:minimumOSVersionString];
	OFVersionNumber *currentOSVersion = [OFVersionNumber userVisibleOperatingSystemVersionNumber];
	
	BOOL yummy = ([currentOSVersion compareToVersionNumber:minimumOSVersion] != NSOrderedAscending);
	
	[minimumOSVersion release];
	if (!yummy)
	    return;
    }
    
    titleEnglish = [description objectForKey:@"title"];
    if (titleEnglish == nil)
        titleEnglish = [NSString stringWithFormat:@"Localized Title for Preference Class %@", className];
    title = [classBundle localizedStringForKey:titleEnglish value:@"" table:@"Preferences"];

    if (!(className && title))
        return;

    iconName = [description objectForKey:@"icon"];
    if (iconName == nil || [iconName isEqualToString:@""])
        iconName = className;
    nibName = [description objectForKey:@"nib"];
    if (nibName == nil || [nibName isEqualToString:@""])
        nibName = className;

    shortTitleEnglish = [description objectForKey:@"shortTitle"];
    if (shortTitleEnglish == nil) {
        shortTitleEnglish = [NSString stringWithFormat:@"Localized Short Title for Preference Class %@", className];
        shortTitle = [classBundle localizedStringForKey:shortTitleEnglish value:@"" table:@"Preferences"];
        if ([shortTitle isEqualToString:shortTitleEnglish])
            shortTitle = nil; // there's no localization for the short title specifically, so we'll let it client class default the short title to the localized version of the @"title" key's value
    } else
        shortTitle = [classBundle localizedStringForKey:shortTitleEnglish value:@"" table:@"Preferences"];
    
    identifier = [description objectForKey:@"identifier"];
    if (identifier == nil) {
        // Before we introduced a separate notion of identifiers, we simply used the short title (which defaulted to the title)
        identifier = [description objectForKey:@"shortTitle" defaultObject:titleEnglish];
    }

    // All our preference pane identifiers should really be in reverse DNS style now.
    OBASSERT([identifier containsString:@"."] || [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.omnigroup.OmniWeb6"]);
    
    // Allow client records to hidden by default.  This is useful for developer preferences or other preference panes that aren't fit for human consumption yet.
    if ([description boolForKey:@"hidden" defaultValue:NO]) {
        // If it defaults to hidden, check if there is a user default to make it specifically visible.
        if (![[NSUserDefaults standardUserDefaults] boolForKey:[identifier stringByAppendingString:@".visible"]])
            return;
    }
    
    newRecord = [[OAPreferenceClientRecord alloc] initWithCategoryName:categoryName];
    [newRecord setIdentifier:identifier];
    [newRecord setClassName:className];
    [newRecord setTitle:title];
    [newRecord setShortTitle:shortTitle];
    [newRecord setIconName:iconName];
    [newRecord setNibName:nibName];
    [newRecord setHelpURL:[description objectForKey:@"helpURL"]];
    [newRecord setOrdering:[description objectForKey:@"ordering"]];
    [newRecord setDefaultsDictionary:defaultsDictionary];
    [newRecord setDefaultsArray:[description objectForKey:@"defaultsArray"]];


    [AllClientRecords addObject:newRecord];
    [newRecord release];
}

@end

static BOOL OAOpenSystemPreferenceBundle(NSString *paneBundleIdentifier)
{
    OSErr err;
    FSRef fRef;
    CFURLRef prefDir;
    CFArrayRef panes;
    BOOL didOpen;
    
    // Find the folder containing the pref panes
    err = FSFindFolder(kSystemDomain, kSystemPreferencesFolderType, FALSE, &fRef);
    if (err != noErr) {
        NSLog(@"FSFindFolder(kSystemPreferencesFolderType) returned %d", err);
        return NO;
    }
    
    prefDir = CFURLCreateFromFSRef(kCFAllocatorDefault, &fRef);
    if (!prefDir)
        return NO; // shouldn't happen, really
    
    // List all the preference panes in that folder
    panes = CFBundleCreateBundlesFromDirectory(kCFAllocatorDefault, prefDir, NULL);
    CFRelease(prefDir);
    if (!panes) {
        return NO;
    }
    
    // Search for one with a matching bundle identifier
    CFIndex paneCount = CFArrayGetCount(panes), paneIndex;
    didOpen = NO;
    for(paneIndex = 0; paneIndex < paneCount; paneIndex ++) {
        CFBundleRef pane = (CFBundleRef)CFArrayGetValueAtIndex(panes, paneIndex);
        CFStringRef paneID = CFBundleGetIdentifier(pane);
        if (CFStringCompare(paneID, (CFStringRef)paneBundleIdentifier, 0) == kCFCompareEqualTo) {
            CFURLRef paneLocation = CFBundleCopyBundleURL(pane);
            didOpen = [[NSWorkspace sharedWorkspace] openURL:(NSURL *)paneLocation];
            CFRelease(paneLocation);
            break;
        }
    }
    CFRelease(panes);
    
    return didOpen;
}

static NSAppleEventDescriptor *whose(OSType form, OSType want, NSAppleEventDescriptor *seld, NSAppleEventDescriptor *container)
{
    NSAppleEventDescriptor *obj = [NSAppleEventDescriptor recordDescriptor];
    
    if (!container)
        container = [NSAppleEventDescriptor nullDescriptor];
    
    [obj setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:form] forKeyword:keyAEKeyForm];
    [obj setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:want] forKeyword:keyAEDesiredClass];
    [obj setDescriptor:seld forKeyword:keyAEKeyData];
    [obj setDescriptor:container forKeyword:keyAEContainer];
    
    return [obj coerceToDescriptorType:'obj '];
}

/* On 10.4, System Preferences has applescript support for revealing a specific tab (or anchor) within a specific pane. So we call that. */
static BOOL OAOpenSystemPreferenceTab(NSString *paneIdentifier, NSString *tabIdentifier)
{
    NSString *systemPreferencesBundleID = @"com.apple.systempreferences";
    NSAppleEventDescriptor *target = whose(formUniqueID, 'xppb', [NSAppleEventDescriptor descriptorWithString:paneIdentifier], nil);
    if (tabIdentifier)
        target = whose(formName, 'xppa', [NSAppleEventDescriptor descriptorWithString:tabIdentifier], target);
    
    NSData *prefsBundleID = [systemPreferencesBundleID dataUsingEncoding:NSUTF8StringEncoding];

    OSErr err;
    AppleEvent reveal, reply;
    
    err = AEBuildAppleEvent('misc','mvis',
                      typeApplicationBundleID, [prefsBundleID bytes], [prefsBundleID length],
                      kAutoGenerateReturnID,
                      kAnyTransactionID,
                      &reveal, NULL, "'----':@", [target aeDesc]);
    if (err !=  aeBuildSyntaxNoErr)
        return NO;
    
    // Send the event with a timeout of 5 seconds. That should be long enough to get a failure response, but not so long that it'll be really annoying if there's a holdup for some reason.
    UInt32 aevtTimeout = 5 * 60;
    
    err = AESend(&reveal, &reply, kAEWaitReply|kAEAlwaysInteract|kAECanSwitchLayer, kAENormalPriority, aevtTimeout, NULL, NULL);
    if (err == procNotFound) {
        // Prefs hasn't been launched, perhaps.
        BOOL ok;
        ok = [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:systemPreferencesBundleID
                                                                  options:NSWorkspaceLaunchWithoutActivation
                                           additionalEventParamDescriptor:nil
                                                         launchIdentifier:NULL];
        if (ok)
            err = AESend(&reveal, &reply, kAEWaitReply|kAEAlwaysInteract|kAECanSwitchLayer, kAENormalPriority, aevtTimeout, NULL, NULL);
    }
    AEDisposeDesc(&reveal);
    if (err != noErr)
        return NO;
    
    BOOL successResponse = YES;
    AEDesc dummy;
    
    err = AEGetParamDesc(&reply, keyErrorNumber, typeWildCard, &dummy);
    if (err == noErr) {
        AEDisposeDesc(&dummy);
        successResponse = NO;
    } else {
        err = AEGetParamDesc(&reply, keyErrorString, typeWildCard, &dummy);
        if (err == noErr) {
            AEDisposeDesc(&dummy);
            successResponse = NO;
        }
    }
    AEDisposeDesc(&reply);

    return successResponse;
}

BOOL OAOpenSystemPreferencePane(NSString *bundleIdentifier, NSString *tabIdentifier)
{
    BOOL success = OAOpenSystemPreferenceTab(bundleIdentifier, tabIdentifier);
    
    /* Fall back to the 10.3 technique of asking System Preferences to open a given preference bundle. */
    if (!success)
        success = OAOpenSystemPreferenceBundle(bundleIdentifier);
    
    return success;
}

