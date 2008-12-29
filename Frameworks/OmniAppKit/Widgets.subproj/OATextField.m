// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATextField.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@interface OATextField (PrivateAPI)
- (void) _updateLabel;
@end

@implementation OATextField

- initWithCoder: (NSCoder *) coder;
{
    if (!(self = [super initWithCoder: coder]))
        return nil;

    // we don't currently archive the label field since this object isn't palettized.
    // rather, IB encodes a connector and manually sets the ivar
    //label = [[coder decodeObject] retain];
    if (label)
        [self _updateLabel];

    return self;
}

- (void) setEditable: (BOOL) isEditable;
{
    [super setEditable: isEditable];
    if (label)
        [self _updateLabel];
}

- (void) setEnabled: (BOOL) isEnabled;
{
    [super setEnabled: isEnabled];
    if (label)
        [self _updateLabel];
}

@end


@implementation OATextField (PrivateAPI)

- (void) _updateLabel;
{
    NSColor *color;

    if ([self isEnabled] && [self isEditable])
        color = [NSColor controlTextColor];
    else
        color = [NSColor disabledControlTextColor];

    [label setTextColor: color];
}

@end
