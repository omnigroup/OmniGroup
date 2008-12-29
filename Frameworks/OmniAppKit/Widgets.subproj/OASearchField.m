// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OASearchField.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import "NSImage-OAExtensions.h"

RCS_ID("$Id$");

@interface OASearchField (Private)
- (NSString *)_searchModeString;
- (void)_chooseSearchMode:(id)sender;
@end

@implementation OASearchField

// NSView subclass

- (id)initWithFrame:(NSRect)frame;
{    
    if ([super initWithFrame:frame] == nil)
        return nil;
    
    // Create search field
    [super setDelegate:(id)self];
    [[self cell] setScrollable:YES];
    [[self cell] setSendsActionOnEndEditing:NO];
    [self updateSearchModeString];
    [self setSendsWholeSearchString:YES];
    
    return self;
}

- (void)dealloc;
{    
    [searchMode release];
    searchMode = nil;
    [super dealloc];
}

// API

- (id)delegate;
{
    return delegate;
}

- (void)setDelegate:(id)newValue;
{
    delegate = newValue;
    
    delegateRespondsTo.searchFieldDidEndEditing = [delegate respondsToSelector:@selector(searchFieldDidEndEditing:)];
    delegateRespondsTo.searchField_didChooseSearchMode = [delegate respondsToSelector:@selector(searchField:didChooseSearchMode:)];
    delegateRespondsTo.searchField_validateMenuItem = [delegate respondsToSelector:@selector(searchField:validateMenuItem:)];
    delegateRespondsTo.control_textView_doCommandBySelector = [delegate respondsToSelector:@selector(control:textView:doCommandBySelector:)];
}

- (NSMenu *)menu;
{
    return [[self cell] searchMenuTemplate];
}

- (void)setMenu:(NSMenu *)aMenu;
{
    id newSearchMode = nil, firstSearchMode = nil;

    NSArray *items = [aMenu itemArray];
    unsigned int itemIndex, itemCount = [items count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        NSMenuItem *item = [items objectAtIndex:itemIndex];
        int tag = [item tag];
        if (tag == DoNotModifyMenuItemTag || tag == NSSearchFieldRecentsTitleMenuItemTag || tag == NSSearchFieldRecentsMenuItemTag || tag == NSSearchFieldClearRecentsMenuItemTag || tag == NSSearchFieldNoRecentsMenuItemTag)
            continue;
        if ([item target] != nil)
            [item setTarget:self];
        if ([item action] == NULL)
            [item setAction:@selector(_chooseSearchMode:)];
        
        // Find the first non-nil search mode in case we can't preserve the previously selected search mode
        id aSearchMode = [item representedObject];
        if (firstSearchMode == nil && aSearchMode != nil)
            firstSearchMode = aSearchMode;
        
        // Try to preserve the previously selected search mode
        if ([aSearchMode isEqual:searchMode])
            newSearchMode = aSearchMode;
    }
        
    // If the previously selected search mode is no longer in the menu, use the first one found
    if (newSearchMode == nil)
        newSearchMode = firstSearchMode;
        
    // Restore the previously selected search mode
    [[self cell] setSearchMenuTemplate:aMenu];
    [self setSearchMode:newSearchMode];
}

- (id)searchMode;
{
    return searchMode;
}

- (void)setSearchMode:(id)newSearchMode;
{
    NSMenu *menu = [self menu];
    NSInteger selectedItemIndex = [menu indexOfItemWithRepresentedObject:newSearchMode];
    if (selectedItemIndex == NSNotFound)
        return;
        
    id oldSearchMode = [searchMode retain];
        
    NSArray *items = [menu itemArray];
    NSInteger itemIndex, itemCount = [items count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        NSMenuItem *item = [items objectAtIndex:itemIndex];
        if ([item tag] != DoNotModifyMenuItemTag)
            [item setState:(itemIndex == selectedItemIndex)];
    }
    
    [searchMode release];
    searchMode = [newSearchMode retain];
    
    // If the old search mode is no longer in the menu, and the user is not editing the search field, update its search mode string
    if (oldSearchMode == nil || ![searchMode isEqual:oldSearchMode]) {
        [self updateSearchModeString];
    }
    
    [oldSearchMode release];
    [[self cell] setSearchMenuTemplate:menu];
}

- (void)updateSearchModeString;
{
    [[self cell] setPlaceholderString:[self _searchModeString]];
}

- (BOOL)sendsActionOnEndEditing;
{
    return [[self cell] sendsActionOnEndEditing];
}

- (void)setSendsActionOnEndEditing:(BOOL)newValue;
{
    [[self cell] setSendsActionOnEndEditing:newValue];
}

- (BOOL)sendsWholeSearchString;
{
    return [[self cell] sendsWholeSearchString];
}

- (void)clearSearch;
{
    [self setStringValue:@""];
    [self sendAction:[self action] to:[self target]];
}

- (void)setSendsWholeSearchString:(BOOL)newValue;
{
    [[self cell] setSendsWholeSearchString:newValue];
}


//
// Validation
//

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    if (delegateRespondsTo.searchField_validateMenuItem)
        return [delegate searchField:self validateMenuItem:item];
    return YES;
}

@end

@implementation OASearchField (NotificationsDelegatesDatasources)

// NSControl delegate

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    if (delegateRespondsTo.searchFieldDidEndEditing && ![self sendsWholeSearchString])
        [delegate searchFieldDidEndEditing:self];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification;
{
    if (delegateRespondsTo.searchFieldDidEndEditing)
        [delegate searchFieldDidEndEditing:self];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
{
    if (delegateRespondsTo.control_textView_doCommandBySelector)
        return [delegate control:self textView:textView doCommandBySelector:commandSelector];
    else
        return NO;
}

@end

@implementation OASearchField (Private)

- (NSString *)_searchModeString;
{
    NSMenu *menu = [self menu];
    // Get the search mode from the selected menu item if possible
    if (menu != nil && searchMode != nil) {
        int searchModeIndex = [menu indexOfItemWithRepresentedObject:searchMode];
        if (searchModeIndex != -1) {
            NSMenuItem *item = [menu itemAtIndex:searchModeIndex];
            [self validateMenuItem:item];	// Make sure the item title is up to date (but don't actually disable the menu item if validation returns NO)
            return [item title];
        }
    }
    return NSLocalizedStringFromTableInBundle(@"Search", @"OmniAppKit", [OASearchField bundle], @"default search mode menu item");
}

- (void)_chooseSearchMode:(id)sender;
{
    [self setSearchMode:[sender representedObject]];
    if (delegateRespondsTo.searchField_didChooseSearchMode)
        [delegate searchField:self didChooseSearchMode:[self searchMode]];
}

@end
