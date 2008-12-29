// Copyright 2000-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAExtendedOutlineView.h 103156 2008-07-22 17:31:05Z wiml $

#import <AppKit/NSNibDeclarations.h> // For IBOutlet
#import <AppKit/NSOutlineView.h>

@class NSMutableString, NSPasteboard;
@class OATypeAheadSelectionHelper;

#import <OmniAppKit/OAFindControllerTargetProtocol.h>

@interface OAExtendedOutlineView : NSOutlineView <OAFindControllerTarget>
{
    struct {
        unsigned int isDraggingSource:1;
        unsigned int isDraggingDestination:1;
        unsigned int isDraggingDestinationAcceptable:1;
        unsigned int justAcceptedDrag:1;
        unsigned int allowsTypeAheadSelection:1;
        unsigned int shouldEditNextItemWhenEditingEnds:1;
        unsigned int indentWithTabKey:1;
        unsigned int newItemWithReturnKey:1;
    } flags;
    NSInteger dragDestinationRow;
    NSInteger dragDestinationLevel;
        
    NSMutableArray *autoExpandedItems;

    OATypeAheadSelectionHelper *typeAheadHelper;
}

// API
- (id)parentItemForRow:(int)row child:(unsigned int *)childIndexPointer;
- (id)parentItemForRow:(int)row indentLevel:(int)childLevel child:(unsigned int *)childIndexPointer;

- (void)setShouldEditNextItemWhenEditingEnds:(BOOL)value;
- (BOOL)shouldEditNextItemWhenEditingEnds;

- (void)setTypeAheadSelectionEnabled:(BOOL)flag;
- (BOOL)typeAheadSelectionEnabled;
    // Defaults to YES, but requires that cell object values in the outline column be strings (or respond to -stringValue)

- (void)setIndentsWithTabKey:(BOOL)value;
- (BOOL)indentsWithTabKey;
- (void)setCreatesNewItemWithReturnKey:(BOOL)value;
- (BOOL)createsNewItemWithReturnKey;

- (void)autoExpandItems:(NSArray *)items;

- (CGFloat)rowOffset:(NSInteger)row;

// Actions
- (IBAction)expandSelection:(id)sender;
- (IBAction)contractSelection:(id)sender;
- (IBAction)group:(id)sender;
- (IBAction)ungroup:(id)sender;
- (IBAction)addNewItem:(id)sender;
//
- (IBAction)copy:(id)sender;
- (IBAction)cut:(id)sender;
- (IBAction)delete:(id)sender;
- (IBAction)paste:(id)sender;


@end

@interface NSObject (OAExtendedOutlineViewDataSource)
// Implement this if you want to accept dragging in.
- (NSArray *)outlineViewAcceptedPasteboardTypes:(OAExtendedOutlineView *)outlineView;

// If you implement the above, then you MUST implement these:
- (BOOL)outlineView:(OAExtendedOutlineView *)outlineView allowPasteItemsFromPasteboard:(NSPasteboard *)pasteboard parentItem:(id)parentItem child:(int)index;
- (NSArray *)outlineView:(OAExtendedOutlineView *)outlineView pasteItemsFromPasteboard:(NSPasteboard *)pasteboard parentItem:(id)parentItem child:(int)index;

- (void)outlineView:(OAExtendedOutlineView *)outlineView parentItem:(id)parentItem moveChildren:(NSArray *)movingChildren toNewParentItem:(id)newParentItem;

- (void)outlineView:(OAExtendedOutlineView *)outlineView parentItem:(id)parentItem moveChildren:(NSArray *)movingChildren toNewParentItem:(id)newParentItem beforeIndex:(int)beforeIndex; // beforeIndex == -1 means add to end

// Implement this if you want find support
- (BOOL)outlineView:(OAExtendedOutlineView *)outlineView item:(id)item matchesPattern:(id <OAFindPattern>)pattern;

// Implement this if you want to allow dragging out.
- (void)outlineView:(OAExtendedOutlineView *)outlineView copyItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard;
- (void)outlineView:(OAExtendedOutlineView *)outlineView deleteItems:(NSArray *)items;

- (BOOL)outlineView:(OAExtendedOutlineView *)outlineView shouldShowDragImageForItem:(id)item;
    // If you'd like to support dragging of multiple selections, but want to control which of the selected rows is valid for dragging, implement this method in addition to -outlineView:copyItems:toPasteboard:. If none of the selected rows are valid, return NO in -outlineView:copyItems:toPasteboard:. If some of them are, write the valid ones to the pasteboard and return YES in -outlineView:copyItems:toPasteboard:, and implement this method to return NO for the invalid ones. This prevents them from being drawn as part of the drag image, so that the items the user appears to be dragging are in sync with the items she's actually dragging. 

// Obselete -- wasn't good for multiple selections. Don't use. (But if you do use this method, we'll still honor it.)
- (NSImage *)outlineView:(OAExtendedOutlineView *)outlineView dragImageForItem:(id)item;

- (BOOL)outlineView:(OAExtendedOutlineView *)outlineView shouldDeleteItemDuringUngroup:(id)item;

- (NSUndoManager *)undoManagerForOutlineView:(OAExtendedOutlineView *)outlineView;

// When the return key is pressed, we ask the data source to create a new item
- (BOOL)outlineView:(NSOutlineView *)anOutlineView createNewItemAsChild:(int)index ofItem:(id)item;

// Implement this if you want context menus.
- (NSMenu *)outlineView:(OAExtendedOutlineView *)outlineView contextMenuForItem:(id)item;

@end


@interface NSObject (DataCellExtraMethods)
- (void)modifyFieldEditor:(NSText *)fieldEditor forOutlineView:(OAExtendedOutlineView *)outlineView column:(int)columnIndex row:(int)rowIndex;
@end
