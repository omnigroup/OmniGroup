// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSCell-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation NSCell (OAExtensions)

- (void) applySettingsToCell: (NSCell *) cell;
{
    [cell setType: [self type]];
    [cell setState: [self state]];
    [cell setTarget: [self target]];
    [cell setAction: [self action]];
    [cell setTag: [self tag]];
    [cell setEnabled: [self isEnabled]];
    // do something about -sendActionOn:
    [cell setContinuous: [self isContinuous]];
    [cell setEditable: [self isEditable]];
    [cell setSelectable: [self isSelectable]];
    [cell setBordered: [self isBordered]];
    [cell setBezeled: [self isBezeled]];
    [cell setScrollable: [self isScrollable]];
    [cell setAlignment: [self alignment]];
    [cell setWraps: [self wraps]];
    [cell setFont: [self font]];
    // do something about -setFloatingPointFormat:left:right:?
    // do something about -keyEquivalent?
    [cell setFormatter: [self formatter]];
    [cell setObjectValue: [self objectValue]];  // this might fail if the starting cell has an invalid object value
    [cell setImage: [self image]];
    [cell setRepresentedObject: [self representedObject]];
    [cell setMenu: [self menu]];
    [cell setSendsActionOnEndEditing: [self sendsActionOnEndEditing]];
    [cell setRefusesFirstResponder: [self refusesFirstResponder]];
    [cell setShowsFirstResponder: [self showsFirstResponder]];
    [cell setMnemonicLocation: [self mnemonicLocation]];  // subclasses will need to set the title, I guess
    [cell setAllowsEditingTextAttributes: [self allowsEditingTextAttributes]];
    [cell setImportsGraphics: [self importsGraphics]];
    [cell setAllowsMixedState: [self allowsMixedState]];
}

@end
