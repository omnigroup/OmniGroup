// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAControlTextColorTransformer.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFNull.h>
#import <AppKit/AppKit.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Bindings/OAControlTextColorTransformer.m 103138 2008-07-22 02:23:17Z wiml $");

@implementation OAControlTextColorTransformer

/*" This value transformer transforms a boolean into either the controlTextColor or the disabledControlTextColor. It's useful for binding a text field to a boolean which controls the enabled state of the control it is the label for. (See also -[NSTextField(OAExtensions) changeColorAsIfEnabledStateWas:].) "*/

+ (void)didLoad;
{
    OAControlTextColorTransformer *normal = [[self alloc] init];
    normal->negate = NO;
    [NSValueTransformer setValueTransformer:normal forName:@"OAControlTextColor"];
    [normal release];
    
    OAControlTextColorTransformer *negated = [[self alloc] init];
    negated->negate = YES;
    [NSValueTransformer setValueTransformer:negated forName:@"OAControlTextColorInverted"];
    [negated release];
}

+ (Class)transformedValueClass;
{
    return [NSColor class];
}

+ (BOOL)allowsReverseTransformation;
{
    return NO;
}

- (id)transformedValue:(id)value;
{
    BOOL enable;
    
    if (value) {
        if ([value respondsToSelector:@selector(boolValue)])
            enable = [value boolValue];
        else
            enable = OFNOTNULL(value);
        
        if (negate)
            enable = !enable;
    } else
        enable = NO;
    
    return enable? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
}

@end

