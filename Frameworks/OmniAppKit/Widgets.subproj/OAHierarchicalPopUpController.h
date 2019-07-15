// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSArray, NSDictionary, NSMutableArray, NSMutableDictionary;
@class NSPopUpButton, NSMenu, NSMenuItem;

#import <AppKit/NSNibDeclarations.h>

extern NSString * const OAFavoriteCharsetsDefaultsKey;

@interface OAHierarchicalPopUpController : NSObject

@property (nonatomic, retain) IBOutlet NSPopUpButton *theButton;

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


