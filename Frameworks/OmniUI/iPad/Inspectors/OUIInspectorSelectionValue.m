// Copyright 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSelectionValue.h>

RCS_ID("$Id$");

@implementation OUIInspectorSelectionValue

- initWithValue:(id)value;
{
    if (!(self = [super init]))
        return nil;

    _values = [[NSArray alloc] initWithObjects:value, nil]; // value might be nil.
    
    return self;
}

- initWithValues:(NSArray *)values;
{
    if (!(self = [super init]))
        return nil;
    
    _values = [[NSArray alloc] initWithArray:values];
    
    return self;
}

- (id)firstValue;
{
    if ([_values count] > 0)
        return [_values objectAtIndex:0];
    return nil;
}

@end
