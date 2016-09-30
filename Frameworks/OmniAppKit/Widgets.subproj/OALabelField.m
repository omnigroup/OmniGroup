// Copyright 1998-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniAppKit/OALabelField.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$")

@implementation OALabelField

- (id)initWithCoder:(NSCoder *)coder;
{
    if ((self = [super initWithCoder:coder]) == nil) {
        return nil;
    }
    
    [self _updateTextColor];
    
    return self;
}

- (void)setEnabled:(BOOL)newValue;
{
    [super setEnabled:newValue];
    [self _updateTextColor];
}

- (void)setTextColor:(NSColor *)newValue;
{
    // No-one should be trying to change our text color - we're managing it automatically. Block any attempts and assert so that we'll know if anyone tries, rather than possibly overlooking some obscure bugs.
    OBASSERT_NOT_REACHED("Don't tell us to change our text color - we're managing it based on our enabled state");
}

- (BOOL)allowsVibrancy
{
    return NO;
}

#pragma mark - Private

- (void)_updateTextColor;
{
    NSColor *color;
    
    if ([self isEnabled]) {
        color = [NSColor controlTextColor];
    } else {
        color = [NSColor disabledControlTextColor];
    }
    
    [super setTextColor:color]; // Call the superclass implementation because we purposefully block others from changing our color
}

#pragma mark - NSTextField (OAExtensions) subclass

- (void)changeColorAsIfEnabledStateWas:(BOOL)newEnabled;
{
    // We're handling our own color changes based on our actual enabled state, so we want to opt out of anyone else telling us what to do.
}

@end
