// Copyright 2001-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OATypeAheadSelectionHelper.h 104581 2008-09-06 21:18:23Z kc $

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h> // For unichar

@class NSArray, NSMutableString, OFScheduledEvent;

// This class provides a mechanism for easily implementing the common Mac behavior of "you have a list of objects, and you can select an item in the list by typing the first few letters of its name". Any interface element that displays named items should be able to take advantage of this. In fact, it should be pretty easy to support both type-ahead-selection and Find without much trouble.

@interface OATypeAheadSelectionHelper : NSObject
{
    id _dataSource;
    struct {
        unsigned int cycleResults:1;
    } flags;

    
    NSArray *typeAheadSearchCache;
    NSMutableString *typeAheadSearchString;
    OFScheduledEvent *typeAheadTimeoutEvent;
}

// API
- (id)dataSource;
- (void)setDataSource:(id)anObject;
    // This class isn't very useful without a provider of possible strings to select from.

- (BOOL)cyclesSimilarResults;
- (void)setCyclesSimilarResults:(BOOL)newValue;
    // Most applications of type-ahead-selection will be Finder-like views, and should thus type-ahead should behave the same way it does there. But for a small few applications (such as selecting links in web pages), it's more useful to have a slightly different behavior, in which repeated attepts to type something for which there are multiple matches will cycle through the possible matches instead of re-selecting the first match.


- (void)rebuildTypeAheadSearchCache;
    // We cache the set of strings used for searching; if your content changes, you should call this method so that our cache is updated to match.
    
- (void)processKeyDownCharacter:(unichar)character;
    // Call this in -keyDown: to have us do that type-ahead-selection magic. You'll want filter the event characters and modifier flags before calling, especially if you do stuff with keys that aren't valid for type-ahead. 
    
- (BOOL)isProcessing;
    // Returns YES if our internal timer is still ticking (and thus the next character typed could be part of the search string instead of starting a new one). You may want to use this in your filtering of characters before calling processKeyDownCharacter:.

@end

@interface NSObject (OATypeAheadSelectionDataSource)
// All data source methods are required.

- (NSArray *)typeAheadSelectionItems;
    // This is where we build the list of possible items which the user can select by typing the first few letters. You should return an array of NSStrings.

- (NSString *)currentlySelectedItem;
    // Type-ahead-selection behavior can change if an item is currently selected (especially if the item was selected by type-ahead-selection). Return nil if you have no selection or a multiple selection.

- (void)typeAheadSelectItemAtIndex:(NSUInteger)itemIndex;
    // We call this when a type-ahead-selection match has been made; you should select the item based on its index in the array you provided in -typeAheadSelectionItems.

@end
