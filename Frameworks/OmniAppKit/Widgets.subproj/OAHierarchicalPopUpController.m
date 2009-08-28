// Copyright 2000-2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAHierarchicalPopUpController.h"

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$")

NSString * const OAFavoriteCharsetsDefaultsKey = @"FavoriteCharsets";

@interface OAHierarchicalPopUpController (Private)

static NSComparisonResult menuTupleComparison(id left, id right, void *userData);

- (void)_updateRecentSelections:newSelection;
- (void)_submenuAction:sender;
- (void)_topmenuAction:sender;
- (void)_buildMenusForStructure:(NSArray *)menuStructure into:(NSMenu *)menu copyToplevelItems:(NSMutableArray *)toplevelItems toplevel:(BOOL)atTopLevel;
- (void)_writeDefaults;
- (void)_readDefaults;

@end


@implementation OAHierarchicalPopUpController
/*" OAHierarchicalPopUpController manages a NSPopUpButton with a hierarchical menu structure, that is, one with submenus. It manages creating the tree of NSMenu objects, adding selected items to the top level of the menu (so that the NSPopUpButton will correctly show them as selected), and optionally saving the most recently selected items to the defaults database. 

OAHierarchicalPopUpController should be instantiated in a NIB file, with its theButton outlet connected to the relevant NSPopUpButton. The user of the popup will need to initialize the button before it is used by calling -setRecentSelectionsHeading:count:defaultKey:, -setMenuStructure:, and -setSelectedObject:.
"*/

- init
{
    if (!(self = [super init]))
        return nil;

    nonretainedTarget = nil;
    anAction = NULL;

    structure = [[NSArray array] retain];
    representedObjects = [[NSMutableDictionary alloc] init];
    pulldownLastSelection = nil;
    
    recentSelectionsDefaultKey = nil;
    recentSelectionsHeading = nil;
    recentSelectionsMaxCount = 5;
    recentSelections = [[NSMutableArray alloc] initWithCapacity:6];
    
    return self;
}

/*" Initialize an OAHierarchicalPopUpController attached to a menu. Do not use this for a menu that is controlled by a NSPopUpButton; for that, put the OAHierarchicalPopUpController in the nib file along with the button. "*/
- initForMenu:(NSMenu *)theMenu
{
    if (!(self = [self init])) 
        return nil;
    
    pulldownButtonTitleItem = nil;
    theButton = nil;
    theTopMenu = [theMenu retain];
    recentSelectionsMaxCount = 0;
    
    return self;
}

- (void)dealloc
{
    [structure release];
    [pulldownButtonTitleItem release];
    [representedObjects release];
    [recentSelectionsDefaultKey release];
    [recentSelectionsHeading release];
    [recentSelections release];
    [theButton release];
    [super dealloc];
}

- (void)awakeFromNib
{
    OBASSERT(theButton != nil);
    OBASSERT(theTopMenu == nil);

    [theButton retain];
    if ([theButton pullsDown]) {
        pulldownButtonTitleItem = [[theButton itemAtIndex:0] retain];
    } else {
        pulldownButtonTitleItem = nil;
    }
    
    [theButton setTarget:self];
    [theButton setAction:@selector(_topmenuAction:)];
}

/*" Rebuilds the popup's menus according to the menu structure described by newPopupStructure. The menu structure is an array of items. Each item is a (name, value) pair, represented again by an NSArray. If the value is an NSArray, it is taken to the the menu structure of a submenu. If the value is not an array, it is stored as that item's represented object, and returned by -selectedObject. If the value is missing (if the tuple array has only one item), a disabled menu item will be displayed. If the tuple is empty, it indicates that an item separator should be displayed. "*/
- (void)setMenuStructure:(NSArray *)newPopupStructure;
{
    NSMutableArray *extraToplevelItems;
    NSMenu *topMenu;
    
    OBASSERT(theButton != nil || theTopMenu != nil);
    OBASSERT(!(theButton != nil && theTopMenu != nil));
    
    /* get the top menu in the hierarchy; empty it out */
    if (theButton) {
        topMenu = [[theButton lastItem] menu];
        [theButton removeAllItems];
    } else {
        topMenu = theTopMenu;
        [topMenu setAutoenablesItems:NO];
        while([topMenu numberOfItems] > 0)
            [topMenu removeItemAtIndex:0];
    }
    [representedObjects removeAllObjects];
        
    /* pulldown buttons need their title to be the first item */
    if (pulldownButtonTitleItem) 
        [topMenu addItem:pulldownButtonTitleItem];
        
    /* fill in the menu with the new structure */
    extraToplevelItems = [[NSMutableArray alloc] init];
    [self _buildMenusForStructure:newPopupStructure into:topMenu copyToplevelItems:extraToplevelItems toplevel:YES];
    if ([extraToplevelItems count] > 0) {
        [extraToplevelItems sortUsingFunction:menuTupleComparison context:NULL];
        [extraToplevelItems insertObject:[NSArray array] atIndex:0];
        if (recentSelectionsHeading != nil)
            [extraToplevelItems insertObject:recentSelectionsHeading atIndex:1];
        [self _buildMenusForStructure:extraToplevelItems into:topMenu copyToplevelItems:nil toplevel:YES];
    }
    [extraToplevelItems release];
        
    [structure autorelease];
    structure = [newPopupStructure retain];
    
    /* popups must have a current selection in the top level */
    if (theButton && ![theButton pullsDown]) {
        /* give the button a reasonable selection */
        while ([recentSelections count] > 0) {
            id tryMe = [recentSelections lastObject];
            NSMenuItem *myItem = [representedObjects objectForKey:tryMe];
            if (myItem == nil) {
                [recentSelections removeLastObject];
            } else {
                [theButton selectItem:myItem];
                break;
            }
        }
        if (![recentSelections count])  /* last ditch attempt at normalcy */
            [theButton selectItem:[topMenu itemAtIndex:0]];
    }
}

- (void)setTarget:(id <NSObject>)anObject
{
    nonretainedTarget = anObject;
}

- (void)setAction:(SEL)newAction
{
    anAction = newAction;
}

/*" Controls the recent-selections behavior of the popup.

heading, if non-nil, indicates a text heading to be displayed over the recent selections, e.g. "Recent Blodges".

count indicates how many recent selections are displayed; it must be at least 1.

key, if non-nil, indicates that the recent selections should be stored in the defaults database under the given key. 

-setMenuStructure: must be called after this method in order to set up the button correctly. "*/
- (void)setRecentSelectionsHeading:(NSString *)heading count:(int)count defaultKey:(NSString *)key
{
    [recentSelectionsDefaultKey autorelease];
    [recentSelectionsHeading autorelease];
    
    recentSelectionsDefaultKey = [key retain];
    if (heading == nil)
        recentSelectionsHeading = nil;
    else
        recentSelectionsHeading = [[NSArray alloc] initWithObjects:heading, nil];
    recentSelectionsMaxCount = count;
    
    [self _readDefaults];
}

/*" Returns the object represented by the popup's current selection. For pulldowns and independent menus, this is only valid during the action method callback. For popups, this is valid at any time. "*/
- (id <NSObject>)selectedObject
{
    if (theButton && ![theButton pullsDown]) {
        /* Popups know what their selection is */
        return [[theButton selectedItem] representedObject];
    } else {
        /* For pulldowns and submenus, we keep track of the selection */
        return pulldownLastSelection;
    }
}

/*" Changes the popup's selection to the item which represents the given object. If there is no such item in the button's menu structure, this method has no effect. "*/
- (void)setSelectedObject:(id <NSObject>)newSelection
{
    NSInteger itemIndex;
    
    if (![representedObjects objectForKey:newSelection])
        return;
    
    if (theButton)
        itemIndex = [theButton indexOfItemWithRepresentedObject:newSelection];
    else
        itemIndex = [theTopMenu indexOfItemWithRepresentedObject:newSelection];
    
    if (itemIndex == -1 && recentSelectionsMaxCount > 0) {
        /* add the selected item to the recently-selected array */
        [recentSelections addObject:newSelection];
        if ([recentSelections count] > recentSelectionsMaxCount)
            [recentSelections removeObjectAtIndex:0];
        [self _writeDefaults];
        [self setMenuStructure:structure]; /* and rebuild the menus */
        return;
    }
    
    if (theButton && ![theButton pullsDown] &&
        itemIndex != [theButton indexOfSelectedItem])
        [theButton selectItemAtIndex:itemIndex];
    
    [self _updateRecentSelections:newSelection];
    
}

/*" A convenience routine for producing a menuStructure array from a dictionary of title/value pairs. Values may be dictionaries, indicating a submenu. Items are sorted according to the strings in subcatStrings, and are alphabetized within each category. "*/
+ (NSArray *)menuStructureFromDictionaries:(NSDictionary *)topDictionary subcategories:(NSArray *)subcatStrings
{
    NSMutableArray **subcategories;
    int subcategoryCount;
    int categoryIndex;
    NSString *itemTitle;
    NSEnumerator *itemEnumerator;
    NSMutableArray *result;
    
    if (!subcatStrings)
        subcatStrings = [NSArray array];
    subcategoryCount = [subcatStrings count];
    subcategories = alloca( sizeof(*subcategories) * (subcategoryCount+1) );
    
    for(categoryIndex = 0; categoryIndex <= subcategoryCount; categoryIndex ++)
        subcategories[categoryIndex] = nil;
    
    itemEnumerator = [topDictionary keyEnumerator];
    while ((itemTitle = [itemEnumerator nextObject]) != nil) {
        NSArray *tuple;
        id tupleValue;
        for(categoryIndex = 0; categoryIndex < subcategoryCount; categoryIndex ++)
            if([itemTitle rangeOfString:[subcatStrings objectAtIndex:categoryIndex]].length > 0)
                break;
        if (subcategories[categoryIndex] == nil)
            subcategories[categoryIndex] = [[NSMutableArray alloc] init];
        tupleValue = [topDictionary objectForKey:itemTitle];
        if ([tupleValue isKindOfClass:[NSDictionary class]])
            tupleValue = [self menuStructureFromDictionaries:tupleValue subcategories:subcatStrings];
        tuple = [[NSArray alloc] initWithObjects:itemTitle, tupleValue, nil];
        [subcategories[categoryIndex] addObject:tuple];
        [tuple release];
    }
    
    result = [[NSMutableArray alloc] init];
    for(categoryIndex = 0; categoryIndex <= subcategoryCount; categoryIndex ++)
    {
        if (subcategories[categoryIndex] == nil)
            continue;
        if ([result count] > 0)
            [result addObject:[NSArray array]];
        
        [subcategories[categoryIndex] sortUsingFunction:menuTupleComparison context:NULL];
        [result addObjectsFromArray:subcategories[categoryIndex]];
        [subcategories[categoryIndex] release];
        subcategories[categoryIndex] = nil;
    }
    
    {
        NSArray *retval = [NSArray arrayWithArray:result];
        [result release];
        return retval;
    }
}

+ (NSMutableArray *)buildEncodingPopupMenuStructure;
{
    static NSDictionary *charsetCategories = nil;
    const CFStringEncoding *encodings;
    NSString *categoryName;
    NSMutableDictionary *categorization, *categorizedCharsets, *category;
    NSEnumerator *categoryEnumerator, *charsetEnumerator;
    NSMutableArray *menuStructure;

    if (charsetCategories == nil) {
        NSString *plistPath = [OMNI_BUNDLE pathForResource:@"CharsetCategories" ofType:@"plist"];
        if (plistPath != nil)
            charsetCategories = [[NSDictionary alloc] initWithContentsOfFile:plistPath];
        if (charsetCategories == nil) {
            NSLog(@"Unable to read CharsetCategories.plist resource");
            return nil;
        }
    }

    categorization = [[NSMutableDictionary alloc] init];
    categoryEnumerator = [[charsetCategories objectForKey:@"Categories"] keyEnumerator];
    while ((categoryName = [categoryEnumerator nextObject]) != nil) {
        NSString *stringValue;
        charsetEnumerator = [[[charsetCategories objectForKey:@"Categories"] objectForKey:categoryName] objectEnumerator];
        while ((stringValue = [charsetEnumerator nextObject]) != nil)
            [categorization setObject:categoryName forKey:[NSNumber numberWithUnsignedInt:(unsigned int)[stringValue intValue]]];
    }

    // sort the character sets into categories
    categorizedCharsets = [[NSMutableDictionary alloc] init];
    for (encodings = CFStringGetListOfAvailableEncodings(); *encodings != kCFStringEncodingInvalidId; encodings++) {
        NSNumber *encodingValue = [NSNumber numberWithUnsignedInt:(unsigned int)*encodings];
        //        NSString *encodingTitle = (NSString *)CFStringGetNameOfEncoding(*encodings);
        NSString *encodingTitle = [NSString localizedNameOfStringEncoding:CFStringConvertEncodingToNSStringEncoding(*encodings)];

        if (!encodingTitle)
            encodingTitle = [NSString stringWithFormat:[charsetCategories objectForKey:@"BadEncodingFormat"], *encodings];
        categoryName = [categorization objectForKey:encodingValue];
        if (!categoryName) categoryName = [charsetCategories objectForKey:@"OtherCategory"];
        category = [categorizedCharsets objectForKey:categoryName];
        if (!category) {
            category = [[NSMutableDictionary alloc] init];
            [categorizedCharsets setObject:category forKey:categoryName];
            [category release];
        }
        [category setObject:encodingValue forKey:encodingTitle];
    }

    [categorization release];

    // produce a MenuStructure for the popup with the categories in the correct order
    menuStructure = [[NSMutableArray alloc] init];
    categoryEnumerator = [[[charsetCategories objectForKey:@"CategoryOrder"] arrayByAddingObjectsFromArray:[categorizedCharsets allKeys]] objectEnumerator];
    while ((categoryName = [categoryEnumerator nextObject]) != nil) {
        category = [categorizedCharsets objectForKey:categoryName];
        if (category) {
            [menuStructure addObject:[NSArray arrayWithObjects:categoryName, [OAHierarchicalPopUpController menuStructureFromDictionaries:category subcategories:[charsetCategories objectForKey:@"SortingStrings"]], nil]];
            [categorizedCharsets removeObjectForKey:categoryName];
        }
    }

    [categorizedCharsets release];


    return [menuStructure autorelease];
}

@end

@implementation OAHierarchicalPopUpController (Private)

static NSComparisonResult menuTupleComparison(id left_, id right_, void *userData)
{
    NSArray *left = left_;
    NSArray *right = right_;
    return [(NSString *)[left objectAtIndex:0] compare:(NSString *)[right objectAtIndex:0]];
}

- (void)_updateRecentSelections:newSelection
{
    NSUInteger objectIndex = [recentSelections indexOfObject:newSelection];
    if (objectIndex != NSNotFound && objectIndex != [recentSelections count]-1) {
        id selection = [recentSelections objectAtIndex:objectIndex];
        [selection retain];
        [recentSelections removeObjectAtIndex:objectIndex];
        [recentSelections addObject:selection];
        [selection release];
        [self _writeDefaults];
    }
}

/* Invoked by menu items in submenus */
- (void)_submenuAction:sender
{
    id representedObject = [sender representedObject];

    OBASSERT([sender isKindOfClass:[NSMenuItem class]]);
    [self setSelectedObject:representedObject]; /* possibly rebuild menus, possibly not */
    pulldownLastSelection = representedObject;
    NS_DURING {
        [nonretainedTarget performSelector:anAction withObject:self];
    } NS_HANDLER {
        pulldownLastSelection = nil;
        [localException raise];
    } NS_ENDHANDLER;
    pulldownLastSelection = nil;
}

/* Invoked by menu items at the top level of a popup or pulldown (via the button). If we're managing a submenu attached to someone else's menu item, this isn't called. */
- (void)_topmenuAction:sender
{
    id representedObject = [[sender selectedItem] representedObject];
    
    OBASSERT(theButton != nil);
    
    [self _updateRecentSelections:representedObject];
    if ([theButton pullsDown])
        pulldownLastSelection = representedObject;
    NS_DURING {
        [nonretainedTarget performSelector:anAction withObject:self];
    } NS_HANDLER {
        pulldownLastSelection = nil;
        [localException raise];
    } NS_ENDHANDLER;
    pulldownLastSelection = nil;
}

- (void)_buildMenusForStructure:(NSArray *)menuStructure into:(NSMenu *)menu copyToplevelItems:(NSMutableArray *)toplevelItems toplevel:(BOOL)atTopLevel
{
    int itemCount, itemIndex;
        
    itemCount = [menuStructure count];

    for(itemIndex = 0; itemIndex < itemCount; itemIndex ++) {
        NSMenuItem *menuItem;
        NSArray *structureItem;

        structureItem = [menuStructure objectAtIndex:itemIndex];
        OBASSERT([structureItem isKindOfClass:[NSArray class]]);
        
        if ([structureItem count] == 0) {
            /* this is a separator item */
            menuItem = [[NSMenuItem separatorItem] retain];
            [menu addItem:menuItem]; 
        } else {
            NSString *title = [structureItem objectAtIndex:0];
            
            /* If we're at the top level of a button's menu, go through the PopUpButton so that the connections work out. If we're building a submenu, do it ourselves */
            if (atTopLevel && theButton != nil) {
                [theButton addItemWithTitle:title];
                menuItem = [[theButton lastItem] retain];
            } else {
                menuItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(_submenuAction:) keyEquivalent:@""];
                [menuItem setTarget:self];
                [menu addItem:menuItem];
            }

            if ([structureItem count] == 1) {
                /* This tuple has no value; it's a menu subheading */
                [menuItem setAction:NULL];
                [menuItem setEnabled:NO];
            } else {
                id representee = [structureItem objectAtIndex:1];

                if (toplevelItems && !atTopLevel && [recentSelections containsObject:representee])
                    [toplevelItems addObject:structureItem];
                [menuItem setEnabled:YES];
            
                if (![representee isKindOfClass:[NSArray class]]) {
                    /* this is a normal, selectable item */
                    [menuItem setRepresentedObject:representee];
                    [representedObjects setObject:menuItem forKey:representee];
                } else {
                    /* this item is a submenu */
                    NSMenu *submenu = [[NSMenu alloc] initWithTitle:title];
                    [submenu setAutoenablesItems:NO];
                    [self _buildMenusForStructure:representee into:submenu copyToplevelItems:toplevelItems toplevel:NO];
                    [menu setSubmenu:submenu forItem:menuItem];
                    [submenu release];
                }
            }
        }
        [menuItem release];
    }
}

- (void)_writeDefaults
{
    if (recentSelectionsDefaultKey != nil)
        [[NSUserDefaults standardUserDefaults] setObject:[NSArray arrayWithArray:recentSelections] forKey:recentSelectionsDefaultKey];
}

- (void)_readDefaults;
{
    NSEnumerator *recentSelectionsEnumerator;
    id recentSelection;
    
    if (!recentSelectionsDefaultKey)
        return;
    
    recentSelectionsEnumerator = [[[NSUserDefaults standardUserDefaults] arrayForKey:recentSelectionsDefaultKey] objectEnumerator];
    while ((recentSelection = [recentSelectionsEnumerator nextObject]) != nil) {
        NSUInteger objectIndex = [recentSelections indexOfObject:recentSelection];
        if (objectIndex != NSNotFound) {
            if(objectIndex != [recentSelections count]-1) {
                id selection = [recentSelections objectAtIndex:objectIndex];
                [selection retain];
                [recentSelections removeObjectAtIndex:objectIndex];
                [recentSelections addObject:selection];
                [selection release];
            }
        } else {
            /* Ideally, we could check here whether the object was a valid selection, but we are called before the popup list has been given its menuStructure, so we can't. */
            [recentSelections addObject:recentSelection];
        }
    }
    
    while ([recentSelections count] > recentSelectionsMaxCount) {
        [recentSelections removeObjectAtIndex:0];
    }
}


@end
