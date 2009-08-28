// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSArray, NSDictionary, NSMutableArray, NSMutableDictionary;
@class NSPopUpButton, NSMenu, NSMenuItem;

#import <AppKit/NSNibDeclarations.h>

extern NSString * const OAFavoriteCharsetsDefaultsKey;

@interface OAHierarchicalPopUpController : NSObject
{
    id <NSObject> nonretainedTarget;
    SEL anAction;
    
    NSArray *structure;
    NSMutableDictionary *representedObjects;
    
    /* Pull-down buttons secretly store their title as the first menu item, so we have to keep that around. */
    NSMenuItem *pulldownButtonTitleItem;
    id pulldownLastSelection;  /* temporarily holds last selected object for a pulldown or submenu */
    
    /* Managing the "recent selections" portion of the menu */
    NSString *recentSelectionsDefaultKey;  /* non-nil to store selections in defaults db */
    NSArray *recentSelectionsHeading;      /* menu tuple to insert ahead of any recent sel'ns */
    unsigned int recentSelectionsMaxCount; /* max nr. of items in the recent stuff section */
    NSMutableArray *recentSelections;      /* LRU-ordered list of recent selections */
    
    /* Exactly one of these should be non-nil, depending on whether our hierarchical menu is attached to a popup button or is a submenu */
    IBOutlet NSPopUpButton *theButton;
    NSMenu *theTopMenu;
}



/* NB The controller must be set up in a particular order. After -awakeFromnib, first -setRecentSelectionsHeading:..., then -setMenuStructure:, finally -setSelectedObject:.

Alternatively, a controller that manages a submenu attached to a menu item can be initialized with -initForMenu:, then an optional -setRecentSelectionsHeading: and -setMenuStructure:.

Having a non-zero recent selections count is necessary for popups to work correctly but is not needed for submenus. */

- initForMenu:(NSMenu *)theMenu;

- (void)setMenuStructure:(NSArray *)newPopupStructure;
- (void)setRecentSelectionsHeading:(NSString *)heading count:(int)count defaultKey:(NSString *)key;

- (id <NSObject>)selectedObject;
- (void)setSelectedObject:(id <NSObject>)newSelection;

- (void)setTarget:(id <NSObject>)anObject;
- (void)setAction:(SEL)anAction;

/* random utility method */
+ (NSArray *)menuStructureFromDictionaries:(NSDictionary *)topDictionary subcategories:(NSArray *)subcatStrings;
+ (NSMutableArray *)buildEncodingPopupMenuStructure;
@end


