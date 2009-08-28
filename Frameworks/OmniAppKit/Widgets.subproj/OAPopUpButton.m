// Copyright 1998-2005,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPopUpButton.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OATypeAheadSelectionHelper.h"

RCS_ID("$Id$")

@interface OAPopUpButton (PrivateAPI)
- (void)_updateLabel;
@end

@implementation OAPopUpButton

- (id)initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;

    // we don't currently archive the label field since this object isn't palettized.
    // rather, IB encodes a connector and manually sets the ivar
    //label = [[coder decodeObject] retain];
    if (label)
        [self _updateLabel];

    return self;
}

- (void)dealloc;
{
    [typeAheadHelper release];
    [super dealloc];
}


// NSResponder subclass

- (void)moveUp:(id)sender;
{
    NSInteger itemIndex;

    itemIndex = [self indexOfSelectedItem];
    if (itemIndex > 0)
        itemIndex--;
    while (itemIndex > 0 && [[self itemAtIndex:itemIndex] isSeparatorItem])
        itemIndex--;
    if ([[self itemAtIndex:itemIndex] isSeparatorItem])
        return; // All previous items are separators, do nothing
    [self selectItemAtIndex:itemIndex];
    [self sendAction:[self action] to:[self target]];
}

- (void)moveDown:(id)sender;
{
    NSInteger itemIndex, lastItemIndex;

    lastItemIndex = [self numberOfItems] - 1;
    itemIndex = [self indexOfSelectedItem];
    if (itemIndex < lastItemIndex)
        itemIndex++;
    while (itemIndex < lastItemIndex && [[self itemAtIndex:itemIndex] isSeparatorItem])
        itemIndex++;
    if ([[self itemAtIndex:itemIndex] isSeparatorItem])
        return; // All subsequent items are separators, do nothing
    [self selectItemAtIndex:itemIndex];
    [self sendAction:[self action] to:[self target]];
}

- (void)keyDown:(NSEvent *)theEvent;
{
    NSString *characters = [theEvent characters];
    if ([characters length] > 0) {
        unichar firstCharacter = [characters characterAtIndex:0];
        
        // See if there's an item whose title matches what the user is typing.
        // This can only be activated, initially, by typing an alphanumeric character.  This means the user can still press space to show the menu.
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DisableTypeAheadSelection"] && ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:firstCharacter] || ([typeAheadHelper isProcessing] && ![[NSCharacterSet controlCharacterSet] characterIsMember:firstCharacter]))) {
            if (typeAheadHelper == nil) {
                typeAheadHelper = [[OATypeAheadSelectionHelper alloc] init];
                [typeAheadHelper setDataSource:self];
            }
            
            [typeAheadHelper processKeyDownCharacter:firstCharacter];
            return;
        }
    }
    
    [super keyDown:theEvent];
}

// NSControl subclass

- (void)setEnabled:(BOOL)isEnabled;
{
    [super setEnabled:isEnabled];
    if (label)
        [self _updateLabel];
}

@end

@implementation OAPopUpButton (NotificationsDelegatesDataSources)

// OATypeAheadSelectionDataSource (cakewalk)

- (NSArray *)typeAheadSelectionItems;
{
    return [self itemTitles];
}

- (NSString *)currentlySelectedItem;
{
    return [self titleOfSelectedItem];
}

- (void)typeAheadSelectItemAtIndex:(NSUInteger)itemIndex;
{
    [self selectItemAtIndex:itemIndex];
    [self sendAction:[self action] to:[self target]];
}

@end

@implementation OAPopUpButton (PrivateAPI)

- (void)_updateLabel;
{
    NSColor *color;

    if ([self isEnabled]) {
        color = [NSColor controlTextColor];
    } else {
        color = [NSColor disabledControlTextColor];
    }

    [label setTextColor:color];
}

@end
