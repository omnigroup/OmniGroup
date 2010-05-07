// Copyright 2010 The Omni Group.  All rights reserved.
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

    _uniqueValues = [[NSSet alloc] initWithObjects:value, nil]; // works if value == nil.
    _dominantValue = [value retain];
    
    return self;
}

- initWithValues:(NSArray *)values;
{
    if (!(self = [super init]))
        return nil;
    
    _uniqueValues = [[NSSet alloc] initWithArray:values];
    
    switch ([values count]) {
        case 0:
            _dominantValue = nil;
            break;
        case 1:
        case 2:
            _dominantValue = [[values objectAtIndex:0] retain];
            break;
        default: {
            NSCountedSet *countedSet = [[NSCountedSet alloc] init];
            for (id value in values)
                [countedSet addObject:value];
            
            id mostCommonValue = nil;
            NSUInteger mostCommonCount = 0;
            
            for (id value in countedSet) {
                NSUInteger count = [countedSet countForObject:value];
                if (mostCommonCount < count) {
                    mostCommonCount = count;
                    mostCommonValue = value;
                }
            }
            
            _dominantValue = [mostCommonValue retain];
            [countedSet release];
        }
    }
    
    return self;
}

- (void)dealloc;
{
    [_dominantValue release];
    [_uniqueValues release];
    [super dealloc];
}

@synthesize dominantValue = _dominantValue;
@synthesize uniqueValues = _uniqueValues;

- (id)uniqueValue;
{
    if ([_uniqueValues count] == 1)
        return _dominantValue;
    return 0;
}

@end
