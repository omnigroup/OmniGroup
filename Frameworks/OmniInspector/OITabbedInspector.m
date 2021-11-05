// Copyright 2005-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OITabbedInspector.h>

#import <AppKit/AppKit.h>
#import <OmniAppKit/OmniAppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniInspector/OIButtonMatrixBackgroundView.h>
#import <OmniInspector/OIInspectionSet.h>
#import <OmniInspector/OIInspectorController.h>
#import <OmniInspector/OIInspectorHeaderView.h>
#import <OmniInspector/OIInspectorRegistry.h>
#import <OmniInspector/OIInspectorTabController.h>
#import <OmniInspector/OITabMatrix.h>
#import <OmniInspector/OITabCell.h>

RCS_ID("$Id$")

@interface OITabbedInspector (/*Private*/)

@property (nonatomic) NSTitlebarAccessoryViewController *titlebarAccessory;

@end

#pragma mark -

@implementation OITabbedInspector
{
    NSArray *_tabControllers;
    NSMutableDictionary *_preferredTabIdentifierForInspectionIdentifier;
}

@synthesize buttonMatrix = buttonMatrix;

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib;
{
    NSView *inspectorView = self.view;
    NSArray *subviews = [inspectorView subviews];
    for(NSView *aView in subviews) {
        if ([aView isKindOfClass:[NSBox class]]) {
            [aView setHidden:YES];
            break;
        }
    }
    
    float inspectorWidth;
    
    OIInspectorController *inspectorController = self.inspectorController;
    if (inspectorController)
        inspectorWidth = [inspectorController.inspectorRegistry inspectorWidth];
    else
        inspectorWidth = [[OIInspectorRegistry inspectorRegistryForMainWindow] inspectorWidth];
    
    NSRect inspectionFrame = [inspectorView frame];
    OBASSERT(inspectionFrame.size.width <= inspectorWidth); // OK to make views from nibs wider, but probably indicates a problem if we are making them smaller.
    inspectionFrame.size.width = inspectorWidth;
    [inspectorView setFrame:inspectionFrame];
    
    NSRect contentFrame = [contentView frame];
    OBASSERT(contentFrame.size.width <= inspectorWidth); // OK to make views from nibs wider, but probably indicates a problem if we are making them smaller.
    contentFrame.size.width = inspectorWidth;
    [contentView setFrame:contentFrame];

    [contentView setAutoresizesSubviews:NO]; // Must turn this off, or inspector views can get scrambled when we change the view size after adding pane views to the contentView
    
    if (_singleSelection) {
        [buttonMatrix setMode:NSRadioModeMatrix];
        [buttonMatrix setAllowsEmptySelection:NO];
    } else {
        // list mode set in nib
        [buttonMatrix setAllowsEmptySelection:YES];
    }
    buttonMatrix.allowPinning = !self.pinningDisabled;

    OIButtonMatrixBackgroundView *buttonMatrixBackground = (id)[buttonMatrix superview];
    OBASSERT([buttonMatrixBackground isKindOfClass:[OIButtonMatrixBackgroundView class]]);
    [buttonMatrixBackground setBackgroundColor:nil];

    [self _createButtonCellForAllTabs];
    [self _layoutSelectedTabs]; // updates the inspection set in the tabs
}

#pragma mark -
#pragma mark API

- (NSAttributedString *)windowTitle;
{
    NSArray *cells = [buttonMatrix cells];
    BOOL addedColon = NO;
    BOOL duringMouseDown = NO;
    
    OIInspectorController *inspectorController = self.inspectorController;

    // If we are the only inspector, don't prefix our window title with the tabbed inspector's name.  Just use the tab names.
    NSString *prefix;
    BOOL hasSingleInspector = [inspectorController.inspectorRegistry hasSingleInspector];
    if (hasSingleInspector)
        prefix = @"";
    else
        prefix = [self displayName];
    
    NSString *windowTitle = prefix;
    
    NSUInteger tabIndex, tabCount = [_enabledTabControllers count];
    for (tabIndex = 0; tabIndex < tabCount; tabIndex++) {
	OITabCell *cell = [cells objectAtIndex:tabIndex];
	if ([cell state]) {
	    if ([cell duringMouseDown])
		duringMouseDown = YES;
	    if (!addedColon) {
                if (!hasSingleInspector) // Only need the colon if we used this inspector's name as a prefix
                    windowTitle = [windowTitle stringByAppendingString:@": "];
		addedColon = YES;
	    } else {
		windowTitle = [windowTitle stringByAppendingString:@", "];
	    }
	    windowTitle = [windowTitle stringByAppendingString:[[_enabledTabControllers objectAtIndex:tabIndex] displayName]];
	}
    }
    
    if (!duringMouseDown && [buttonMatrix window]) {
        NSPoint point = [[buttonMatrix window] mouseLocationOutsideOfEventStream];
        point = [buttonMatrix convertPoint:point fromView:nil];
        NSInteger row, column;
        if ([buttonMatrix getRow:&row column:&column forPoint:point]) {
	    OIInspectorTabController *tab = [_enabledTabControllers objectAtIndex:column];
            
            windowTitle = prefix;
            if (!hasSingleInspector)
                windowTitle = [windowTitle stringByAppendingString:@": "];
            
            windowTitle = [windowTitle stringByAppendingString:[tab displayName]];
            if ([[tab shortcutKey] length]) {
                windowTitle = [windowTitle stringByAppendingString:@" ("];
                windowTitle = [windowTitle stringByAppendingString:[NSString stringForKeyEquivalent:[tab shortcutKey] andModifierMask:[tab shortcutModifierFlags]]];
                windowTitle = [windowTitle stringByAppendingString:@")"];
            }
        }
    }
    NSDictionary *textAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:[NSFont labelFontSize]], NSFontAttributeName, nil];
    NSMutableAttributedString *windowTitleAttributedstring = [[NSMutableAttributedString alloc] init];
    [windowTitleAttributedstring replaceCharactersInRange:NSMakeRange(0, [[windowTitleAttributedstring string] length]) withString:windowTitle];
    [windowTitleAttributedstring setAttributes:textAttributes range:NSMakeRange(0, [[windowTitleAttributedstring string] length])];
    
    return windowTitleAttributedstring;
}

- (void)loadConfiguration:(NSDictionary *)config;
{    
    NSMutableArray *selectedIdentifiers = [NSMutableArray array];
    NSMutableArray *pinnedIdentifiers = [NSMutableArray array];
    
    for (OIInspectorTabController *tab in _enabledTabControllers) {
        id tabIdentifier = tab.inspectorIdentifier;
        [tab loadConfiguration:[config objectForKey:tabIdentifier]];
        
        switch ([tab visibilityState]) {
            case OIPinnedVisibilityState:
                [pinnedIdentifiers addObject:tabIdentifier];
                // Fall through to OIVisibleVisibilityState because all pinned tabs must be visible
            case OIVisibleVisibilityState:
                [selectedIdentifiers addObject:tabIdentifier];
                break;
            default:
                OBASSERT([tab visibilityState] == OIHiddenVisibilityState); // If we get here and the visibility state isn't Hidden, there must be some new visibility state we don't know about or we've been given bad data
                break;  // Nothing to do for hidden tabs
        }
    }
    
    // If we are starting with a fresh configuration, we might not have anything selected in a radio-style inspector.
    if ([selectedIdentifiers count] == 0 && _singleSelection && [_enabledTabControllers count] > 0)
        selectedIdentifiers = [NSMutableArray arrayWithObject:[[_enabledTabControllers objectAtIndex:0] identifier]];
    
    [self setSelectedTabIdentifiers:selectedIdentifiers pinnedTabIdentifiers:pinnedIdentifiers];
    
    // Force a layout here since -setSelectedTabIdentifiers: will think nothing has changed (since the inspectors and selection are in sync at this point even though the view isn't).
    [self _layoutSelectedTabs];
    
    if (!config) {
        OIInspectorController *inspectorController = self.inspectorController;
        NSRect windowFrame = [[inspectorController window] frame];
        [inspectorController setExpanded:YES withNewTopLeftPoint:NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame))];
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OIShowInspectorsOnFirstLaunch"])
            [inspectorController showInspector];
    }
}

- (NSDictionary *)configuration;
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (OIInspectorTabController *tab in _enabledTabControllers) {
        NSDictionary *config = [tab copyConfiguration];
        [dict setObject:config forKey:tab.inspectorIdentifier];
    }
    return dict;
}

- (NSArray *)tabIdentifiers;
{
    return [_enabledTabControllers arrayByPerformingSelector:@selector(inspectorIdentifier)];
}

// While the code doesn't currently strictly require it, the expectation is that pinnedIdentifiers is a subset of selectedIdentifiers. Pass in nil for the pinnedIdentifiers if you wish to keep the currently-pinned selection (in which case selectedIdentifiers need not include the
- (void)setSelectedTabIdentifiers:(NSArray *)selectedIdentifiers pinnedTabIdentifiers:(NSArray *)pinnedIdentifiers;
{
    if (pinnedIdentifiers == nil) {
        pinnedIdentifiers = [self pinnedTabIdentifiers];
        NSMutableSet *selectionSet = [NSMutableSet setWithArray:selectedIdentifiers];
        [selectionSet addObjectsFromArray:pinnedIdentifiers];
        selectedIdentifiers = [selectionSet allObjects];
    }
    
    NSSet *pinnedIdentifiersSet = [NSSet setWithArray:pinnedIdentifiers];
    NSSet *selectedIdentifiersSet = [NSSet setWithArray:selectedIdentifiers];
    OBASSERT([pinnedIdentifiersSet isSubsetOfSet:selectedIdentifiersSet]);
    
    BOOL needsLayout = NO;
    for (OIInspectorTabController *tab in _enabledTabControllers) {
        id tabIdentifier = tab.inspectorIdentifier;
        OIVisibilityState visibilityState;
        if ([pinnedIdentifiersSet member:tabIdentifier]) {
            visibilityState = OIPinnedVisibilityState;
        } else if ([selectedIdentifiersSet member:tabIdentifier]) {
            visibilityState = OIVisibleVisibilityState;
        } else {
            visibilityState = OIHiddenVisibilityState;
        }
        if ([tab visibilityState] != visibilityState) {
            if (![tab isVisible]) {
                NSWindow *inspectorPanel = [self.view window];
                NSResponder *firstResponder = [inspectorPanel firstResponder];
                if ([firstResponder isKindOfClass:[NSView class]] && [(NSView *)firstResponder isDescendantOf:contentView]) {
                    BOOL result __attribute__((unused));
                    result = [inspectorPanel makeFirstResponder:inspectorPanel];   // make sure that switching to a new tab causes any edits to commit
                    OBASSERT(result);
                }
            }
            [tab setVisibilityState:visibilityState];
            needsLayout = YES;
        }
    }
    
    if (needsLayout)
        [self _layoutSelectedTabs];
}

- (NSArray *)allTabIdentifiers;
{
    return [_tabControllers arrayByPerformingSelector:@selector(inspectorIdentifier)];
}

- (void)setEnabledTabIdentifiers:(NSArray *)tabIdentifiers;
{
    NSMutableArray *newEnabledTabControllers = [NSMutableArray array];
    for (OIInspectorTabController *tab in _tabControllers) {
        NSString *tabIdentifier = tab.inspector.inspectorIdentifier;
        if ([tabIdentifiers containsObject:tabIdentifier]) {
            [newEnabledTabControllers addObject:tab];
        }
    }
    if (![newEnabledTabControllers isEqualToArray:_enabledTabControllers]) {
        _enabledTabControllers = [NSArray arrayWithArray:newEnabledTabControllers];
        [self _createButtonCellForAllTabs];
        [self _layoutSelectedTabs];
    }
}


- (OIInspectorTabController *)tabWithIdentifier:(NSString *)identifier;
{
    for (OIInspectorTabController *tab in _enabledTabControllers)
        if (OFISEQUAL(identifier, tab.inspector.inspectorIdentifier))
            return tab;
    return nil;
}

- (OIInspector <OIConcreteInspector> *)inspectorWithIdentifier:(NSString *)tabIdentifier;
{
    return [[self tabWithIdentifier:tabIdentifier] inspector];
}

- (NSArray *)selectedTabIdentifiers;
{
    NSMutableArray *identifiers = [NSMutableArray array];
    
    for (OIInspectorTabController *tab in _enabledTabControllers) {
	if ([tab isVisible])
            [identifiers addObject:tab.inspectorIdentifier];
    }
    return identifiers;
}

- (NSArray *)pinnedTabIdentifiers;
{
    NSMutableArray *identifiers = [NSMutableArray array];
    for (OIInspectorTabController *tab in _enabledTabControllers) {
        if ([tab isPinned]) {
            [identifiers addObject:tab.inspectorIdentifier];
        }
    }
    return identifiers;
}

- (CGFloat)defaultHeaderHeight;
{
    CGFloat height = [super defaultHeaderHeight];

    if (self.placesButtonsInHeaderView) {
        if (buttonMatrix) {
            height += NSHeight(buttonMatrix.frame);
        } else {
            height += 31.0f;
        }
    }

    return height;
}

- (void)switchToInspectorWithIdentifier:(NSString *)tabIdentifier;
{
    [self setSelectedTabIdentifiers:[NSArray arrayWithObject:tabIdentifier] pinnedTabIdentifiers:nil];
    
    [self.inspectorController showInspector];
}

#pragma mark -
#pragma mark Actions

// Poorly named action of the button ribbon in Tabbed.nib
- (IBAction)selectInspector:(id)sender;
{
    NSArray *selectedCells = [sender selectedCells];
    NSSet *pinnedCellsSet = [NSSet setWithArray:[sender pinnedCells]];
    NSMutableArray *selectedIdentifiers = [NSMutableArray array];
    NSMutableArray *pinnedIdentifiers = [NSMutableArray array];

    for (NSCell *cell in selectedCells) {
        NSString *identifier = [cell representedObject];
        [selectedIdentifiers addObject:identifier];
        if ([pinnedCellsSet member:cell]) {
            [pinnedIdentifiers addObject:identifier];
        }
    }
    [self setSelectedTabIdentifiers:selectedIdentifiers pinnedTabIdentifiers:pinnedIdentifiers];
}

#pragma mark -
#pragma mark OIInspector subclass

- (id)initWithDictionary:(NSDictionary *)dict inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(NSBundle *)sourceBundle;
{
    if (!(self = [super initWithDictionary:dict inspectorRegistry:inspectorRegistry bundle:sourceBundle]))
	return nil;
    
    _singleSelection = [dict boolForKey:@"single-selection" defaultValue:NO];
    _autoSelection = [dict boolForKey:@"auto-selection" defaultValue:_singleSelection];
    _placesButtonsInTitlebar = [dict boolForKey:@"placesButtonsInTitlebar"];
    _placesButtonsInHeaderView = [dict boolForKey:@"placesButtonsInHeaderView"];
    _preferredTabIdentifierForInspectionIdentifier = [[NSMutableDictionary alloc] init];

    OBASSERT_IF(_placesButtonsInHeaderView, !(self.isCollapsible), @"Support for both collapsable and placesButtonsInHeaderView are not fully implemented, please update code if this configuration needs to be used");

    NSMutableArray *tabControllers = [[NSMutableArray alloc] init];
    
    // Read our sub-inspectors from the plist
    for (NSDictionary *tabPlist in [dict objectForKey:@"tabs"]) {
        NSDictionary *inspectorPlist = [tabPlist objectForKey:@"inspector"];
        NSString *identifier = [inspectorPlist objectForKey:@"identifier"];
        
        NSObject *appDelegate = (NSObject *)[[NSApplication sharedApplication] delegate];
        if (![appDelegate shouldLoadInspectorWithIdentifier:identifier inspectorRegistry:inspectorRegistry])
            continue;

        OIInspectorTabController *tabController = [[OIInspectorTabController alloc] initWithInspectorDictionary:tabPlist inspectorRegistry:inspectorRegistry bundle:sourceBundle];
	if (!tabController)
	    continue;

        NSString *inspectionIdentifier = [tabPlist objectForKey:@"preferredForInspectionIdentifier"];
        if (inspectionIdentifier != nil) {
            _preferredTabIdentifierForInspectionIdentifier[inspectionIdentifier] = tabController.inspectorIdentifier;
        }

        [tabControllers addObject:tabController];
    }

    [tabControllers sortUsingComparator:^NSComparisonResult(OIInspectorController *obj1, OIInspectorController *obj2) {
        return OISortByDefaultDisplayOrderInGroup(obj1, obj2);
    }];
    
    _tabControllers = [[NSArray alloc] initWithArray:tabControllers];
    _enabledTabControllers = [[NSArray alloc] initWithArray:tabControllers];
    
    _trackingRectTags = [[NSMutableArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_tabTitleDidChange:) name:TabTitleDidChangeNotification object:nil];

    // Default to the first tab in case nobody else picks. Maybe we're not autoswitching
    NSString *firstIdentifier = [self tabIdentifiers].firstObject;
    NSArray *selectedTabIdentifiers = firstIdentifier ? @[firstIdentifier] : @[];
    [self setSelectedTabIdentifiers:selectedTabIdentifiers pinnedTabIdentifiers:@[]];

    return self;
}

- (NSString *)nibName;
{
    return @"Tabbed";
}

- (NSBundle *)nibBundle;
{
    return OMNI_BUNDLE;
}

- (void)registerInspectorDictionary:(NSDictionary *)tabPlist inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(NSBundle *)sourceBundle
{
    OIInspectorTabController *tabController = [[OIInspectorTabController alloc] initWithInspectorDictionary:tabPlist inspectorRegistry:inspectorRegistry bundle:sourceBundle];
    if (!tabController)
        return;
    
    NSMutableArray *newTabControllers = [[NSMutableArray alloc] initWithArray:_enabledTabControllers];
    [newTabControllers insertObject:tabController inArraySortedUsingComparator:^NSComparisonResult(OIInspectorController *obj1, OIInspectorController *obj2) {
        return OISortByDefaultDisplayOrderInGroup(obj1, obj2);
    }];

    _tabControllers = [[NSArray alloc] initWithArray:newTabControllers];
    _enabledTabControllers = [[NSArray alloc] initWithArray:newTabControllers];
    
    if (buttonMatrix) {
        [self _createButtonCellForAllTabs];
    }
}


- (NSArray *)menuItemsForTarget:(nullable id)target action:(SEL)action;
{
    // If there is a single tabbed inspector; don't wrap up the menu items for the tabs in a higher level menu item.
    OIInspectorController *inspectorController = self.inspectorController;
    BOOL hasSingleInspector = [inspectorController.inspectorRegistry hasSingleInspector];

    NSMutableArray *menuItems = [NSMutableArray array];

    if (!hasSingleInspector) {
        // Call -menuItem here too so that we can have shortcuts registered for whole inspectors (OmniOutliner) or for individual tabs (OmniGraffle).
        NSMenuItem *headerItem = [self menuItemForTarget:target action:action];
        [menuItems addObject:headerItem];
    }
    
    for (OIInspectorTabController *tab in _enabledTabControllers) {
	NSMenuItem *item = [tab menuItemForTarget:nil action:@selector(revealEmbeddedInspectorFromMenuItem:)];
        [item setRepresentedObject:tab.inspectorIdentifier];
        if (!hasSingleInspector)
            [item setIndentationLevel:2];
	[menuItems addObject:item];
    }
    
    return menuItems;
}

- (void)inspectorDidResize:(OIInspector *)resizedInspector;
{
    OBASSERT(resizedInspector != self); // Don't call us if we are the resized inspector, only on ancestors of that inspector
    NSView *resizedView = [resizedInspector view];
    OIInspectorTabController *tab = [self _tabControllerForInspectorView:resizedView];
    OBASSERT(tab != nil);   // Don't call us if we aren't an ancestor of the resized inspector
    OIInspector *tabInspector = [tab inspector];
    if (tabInspector != resizedInspector) {
        [tabInspector inspectorDidResize:resizedInspector];
    }
    [self _layoutSelectedTabs];
}

- (void)didSetInspectorController;
{
    [super didSetInspectorController];

    // Set the controller on all of our child inspectors as well
    for (OIInspectorTabController *tab in _enabledTabControllers) {
        tab.inspector.inspectorController = self.inspectorController;
    }
}

#pragma mark -
#pragma mark OIConcreteInspector protocol

- (NSPredicate *)inspectedObjectsPredicate;
{
    static NSPredicate *truePredicate = nil;
    if (!truePredicate)
        truePredicate = [NSPredicate predicateWithValue:YES];
    return truePredicate;
}

- (void)inspectObjects:(NSArray *)list 
{
    // list will be nil when we are collapsed
    _shouldInspectNothing = (list == nil);
    [self _updateSubInspectorObjects];
    
    if (_autoSelection && [list count] > 0 && [[self pinnedTabIdentifiers] count] == 0)
        [self _selectTabBasedOnObjects:list];
}


#pragma mark -
#pragma mark NSResponder subclass

- (void)mouseEntered:(NSEvent *)event;
{
    [self.inspectorController updateTitle];
}

- (void)mouseExited:(NSEvent *)event;
{
    [self.inspectorController updateTitle];
}

#pragma mark -
#pragma mark NSObject (NSMenuItemValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    OIInspectorController *inspectorController = self.inspectorController;
    BOOL isVisible = [inspectorController isExpanded] && [inspectorController isVisible];
    
    if  (!isVisible) {
        [item setState:NSControlStateValueOff];
    }
    return YES;
}

#pragma mark -
#pragma mark Private

- (void)_selectTabBasedOnObjects:(NSArray *)objects;
{
    // Find the 'most relevant' object that has an inspector that directly applies to it.  You can either register a preferred tab identifier for an inspection identifier, or auto-select a tab based on the order in which objects were added to the inspection set.
    OIInspectorController *inspectorController = self.inspectorController;
    OIInspectorRegistry *inspectorRegistry = inspectorController.inspectorRegistry;
    OIInspectionSet *inspectionSet = [inspectorRegistry inspectionSet];
    NSArray *sortedObjects = [inspectionSet objectsSortedByInsertionOrder:objects];
    
    NSString *inspectionIdentifier = [inspectorRegistry inspectionIdentifierForCurrentInspectionSet];
    if (_currentInspectionIdentifier || inspectionIdentifier) {
        // do not change the selected tab if the inspectionIdentifier has not changed.
        if ([inspectionIdentifier isEqual:_currentInspectionIdentifier])
            return;
        _currentInspectionIdentifier = [inspectionIdentifier copy];
    }

    NSString *preferredIdentifier = _currentInspectionIdentifier != nil ? _preferredTabIdentifierForInspectionIdentifier[_currentInspectionIdentifier] : nil;
    if (preferredIdentifier == nil) {
        NSArray *tabIdentifiers = [self tabIdentifiers];
        for (id object in sortedObjects) {
            // Ask each of the tabs if this tab is the perfect match for the object
            for (NSString *tabIdentifier in tabIdentifiers) {
                OIInspector *inspector = [self inspectorWithIdentifier:tabIdentifier];
                if ([inspector shouldBeUsedForObject:object]) {
                    preferredIdentifier = tabIdentifier;
                    break;
                }
            }
            if (preferredIdentifier != nil) {
                break;
            }
        }
    }

    if (preferredIdentifier != nil) {
        [self setSelectedTabIdentifiers:@[preferredIdentifier] pinnedTabIdentifiers:@[]];
    } else {
        // Nothing appropriate found; just leave it.
    }
}

- (void)_updateSubInspectorObjects;
{
    for (OIInspectorTabController *tab in _enabledTabControllers) {
	[tab inspectObjects:_shouldInspectNothing];
    }
}

- (void)_createButtonCellForAllTabs;
{
    OBPRECONDITION(buttonMatrix);

    NSUInteger tabIndex = [_enabledTabControllers count];
    
    [buttonMatrix renewRows:1 columns:tabIndex];
    [buttonMatrix sizeToCells];
    [buttonMatrix deselectAllCells];
    
    while (tabIndex--) {
        OIInspectorTabController *tab = [_enabledTabControllers objectAtIndex:tabIndex];
        NSButtonCell *cell = [buttonMatrix cellAtRow:0 column:tabIndex];
        [cell setImage:[tab image]];
        [cell setRepresentedObject:tab.inspectorIdentifier];
        
        if ([tab isVisible])
            [buttonMatrix setSelectionFrom:tabIndex to:tabIndex anchor:tabIndex highlight:YES];
    }
}

- (void)_updateTrackingRects;
{
    for (NSNumber *rectTag in _trackingRectTags)
        [buttonMatrix removeTrackingRect:[rectTag integerValue]];

    [_trackingRectTags removeAllObjects];
    
    NSUInteger i, count = [_enabledTabControllers count];
    for (i=0;i<count;i++) {
        NSRect rect = [buttonMatrix cellFrameAtRow:0 column:i];
        NSInteger tag = [buttonMatrix addTrackingRect:rect owner:self userData:nil assumeInside:NO];
        [_trackingRectTags addObject:[NSNumber numberWithInteger:tag]];
    }
}

- (void)_tabTitleDidChange:(NSNotification *)notification;
{
    OIInspectorController *inspectorController = self.inspectorController;
    for (OITabCell *cell in [buttonMatrix cells]) {
        if (cell == [notification object]) {
            [inspectorController updateTitle];
            break;
        }
    }
}

- (void)_layoutSelectedTabs;
{
    OBPRECONDITION([_enabledTabControllers count] > 0);
    OBPRECONDITION([contentView isFlipped]); // We use an OITabbedInspectorContentView in the nib to make layout easier.
    
    NSSize size = NSMakeSize([contentView frame].size.width, 0);
    
    for (OIInspectorTabController *tab in _enabledTabControllers) {
	if (![tab isVisible]) {
	    if ([tab hasLoadedView]) { // hack to avoid asking for the view before it's needed; don't want to load the nib just to hide it
		[[tab inspectorView] removeFromSuperview];
		[[tab dividerView] removeFromSuperview];
	    }
	}
    }
    
    NSUInteger selectedTabCount = 0;
    
    for (OIInspectorTabController *tab in _enabledTabControllers) {
        if (![tab isVisible])
            continue;
        
        if (selectedTabCount > 0) {
            NSRect dividerFrame = [contentView frame];
            dividerFrame.origin.y = size.height;
            dividerFrame.size.height = 1;
            NSView *divider = [tab dividerView];
	    [divider setFrame:dividerFrame];
            [contentView addSubview:divider];
            size.height += 1;
        } else {
	    [[tab dividerView] removeFromSuperview];
	}
	
	selectedTabCount++;

        NSView *tabInspectorView = [tab inspectorView];
        NSRect viewFrame = [tabInspectorView frame];
	OBASSERT(viewFrame.size.width <= size.width); // make sure it'll fit
	
        viewFrame.origin.x = (CGFloat)floor((size.width - viewFrame.size.width) / 2.0);
        viewFrame.origin.y = size.height;
        viewFrame.size = [tabInspectorView frame].size;
        [tabInspectorView setFrame:viewFrame];
	[contentView addSubview:tabInspectorView];
	
        size.height += [tabInspectorView frame].size.height;
    }
    
    if (selectedTabCount == 0)
	// hide the line underneath our matrix if we have nothing below it
        size.height -= 2;
    
    NSRect contentFrame = [contentView frame];
    contentFrame.size.height = size.height;
    [contentView setFrame:contentFrame];
    
    NSView *inspectorView = self.view;
    if (!self.placesButtonsInTitlebar && !self.placesButtonsInHeaderView) {
        size.height += [buttonMatrix frame].size.height + 2.0;
    }
    NSRect frame = [inspectorView frame];
    frame.size.height = size.height;
    [inspectorView setFrame:frame];

    // Have to do this before calling -updateTitle since it reads the button state (needs to for things like mouse down on the buttons)
    [self _updateButtonsToMatchSelection];

    [contentView setNeedsDisplay:YES];

    OIInspectorController *inspectorController = self.inspectorController;
    [inspectorController updateTitle];
    if (inspectorController.interfaceType == OIInspectorInterfaceTypeFloating) {
        [inspectorController containerView];
        [inspectorController loadInterface];
        [inspectorController prepareWindowForDisplay];
    }
    [inspectorController updateExpandedness:NO];
    [self _updateTrackingRects];
    
    // Any newly exposed inspectors should start tracking; any newly hidden should stop
    [self _updateSubInspectorObjects];

    [inspectorController.inspectorRegistry configurationsChanged];
}

- (void)_updateButtonsToMatchSelection;
{
    [buttonMatrix deselectAllCells];
    
    NSArray *matrixCells = [buttonMatrix cells];
    NSUInteger tabIndex, tabCount = [_enabledTabControllers count];
    for (tabIndex = 0; tabIndex < tabCount; tabIndex++) {
        OIInspectorTabController *tabController = [_enabledTabControllers objectAtIndex:tabIndex];
        if ([tabController isVisible])
            [buttonMatrix setSelectionFrom:tabIndex to:tabIndex anchor:tabIndex highlight:YES];
        [[matrixCells objectAtIndex:tabIndex] setIsPinned:[tabController isPinned]];
    }
    [buttonMatrix setNeedsDisplay:YES];
}

- (OIInspectorTabController *)_tabControllerForInspectorView:(NSView *)view;
{
    for (OIInspectorTabController *tab in _enabledTabControllers) {
        if ([tab hasLoadedView]) {  // Avoid loading any UI that isn't already loaded - if it's not loaded, it can't be one we care about anyway
            NSView *tabView = [tab inspectorView];
            if ([view isDescendantOf:tabView]) {
                return tab;
            }
        }
    }
    OBASSERT_NOT_REACHED("Don't call this on an inspector that isn't an ancestor of the view in question.");
    return nil;
}

- (void)adjustContentFrame;
{
    NSView *view = contentView.window.contentView;
    NSRect rect = view.frame;
    OBASSERT(rect.origin.y == 0);
    rect.origin.y = 0;
    if (!NSEqualRects(view.frame, rect)) {
        view.frame = rect;
    }
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    
    OIInspectorController *inspectorController = self.inspectorController;

    NSWindow *window = self.view.window;
    if (window && !self.titlebarAccessory && self.placesButtonsInTitlebar) {
        NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 296, 33)];
        self.titlebarAccessory = [[NSTitlebarAccessoryViewController alloc] init];
        self.titlebarAccessory.view = accessory;
        [window addTitlebarAccessoryViewController:self.titlebarAccessory];
        [self.titlebarAccessory.view addSubview:buttonMatrix.superview];
        NSRect rButtonMatrixBackground = buttonMatrix.superview.frame;
        rButtonMatrixBackground.origin = NSZeroPoint;
        buttonMatrix.superview.frame = rButtonMatrixBackground;
    } else if (window && self.placesButtonsInHeaderView && !inspectorController.headingButton.accessoryView) {
        OIInspectorHeaderView *headerView = inspectorController.headingButton;
        headerView.accessoryView = buttonMatrix.superview;
        NSRect rButtonMatrixBackground = buttonMatrix.superview.frame;
        rButtonMatrixBackground.origin = CGPointMake(0.0f, headerView.titleContentHeight);
        buttonMatrix.superview.frame = rButtonMatrixBackground;
    }
    
    [self adjustContentFrame];
}

@end

