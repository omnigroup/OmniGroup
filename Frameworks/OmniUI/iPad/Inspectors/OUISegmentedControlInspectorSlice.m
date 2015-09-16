// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISegmentedControlInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUISegmentedControl.h>
#import <OmniUI/OUISegmentedControlButton.h>

RCS_ID("$Id$")

@implementation OUISegmentedControlInspectorSlice
{
    OUISegmentedControl *_segment;
    Class _objectClass;
    NSString *_keyPath;
    NSArray *_titlesAndObjectValues;
}

+ (instancetype)segmentedControlSliceWithObjectClass:(Class)objectClass
                                             keyPath:(NSString *)keyPath
                               titlesAndObjectValues:(NSString *)title, ...;
{
    OBPRECONDITION(objectClass);
    
    NSMutableArray *titlesSubtitlesAndObjectValues = [[NSMutableArray alloc] initWithObjects:title, nil];
    if (title) {
        id nextObject;
        
        va_list argList;
        va_start(argList, title);
        while ((nextObject = va_arg(argList, id)) != nil) {
            [titlesSubtitlesAndObjectValues addObject:nextObject];
        }
        va_end(argList);
    }
    
    OBASSERT([titlesSubtitlesAndObjectValues count] > 0);
    OBASSERT(([titlesSubtitlesAndObjectValues count] % 2) == 0);
    
    OUISegmentedControlInspectorSlice *result = [[self alloc] init];
    result->_objectClass = objectClass;
    result->_keyPath = [keyPath copy];
    result->_titlesAndObjectValues = [titlesSubtitlesAndObjectValues copy];
    
    return result;
}

- (void)loadView;
{
    _segment = [[OUISegmentedControl alloc] initWithFrame:CGRectMake(0, 0, [OUIInspector defaultInspectorContentWidth], 46)];
    
    _segment.sizesSegmentsToFit = YES;
    _segment.allowsMultipleSelection = NO;
    [_segment addTarget:self action:@selector(_changeValue:) forControlEvents:UIControlEventValueChanged];
    
    for (NSUInteger index = 0; index < _titlesAndObjectValues.count; index += 2) 
        [_segment addSegmentWithText:[_titlesAndObjectValues objectAtIndex:index] representedObject:[_titlesAndObjectValues objectAtIndex:index+1]];

    [self updateSelectedSegment];
    
    self.view = _segment;
}
     
- (void)updateSelectedSegment;
{
    id representedObject = nil;
    
    for (id object in self.appropriateObjectsForInspection) {
        id value = [object valueForKeyPath:_keyPath];
        if (representedObject && ![representedObject isEqual:value]) {
            [_segment setSelectedSegment:nil];
            return;
        }
        
        representedObject = value;
    }

    [_segment setSelectedSegment:[_segment segmentWithRepresentedObject:representedObject]];
}

- (void)_changeValue:(id)sender;
{
    id value = [[sender selectedSegment] representedObject];
    OUIInspector *inspector = self.inspector;
    
    [inspector willBeginChangingInspectedObjects];
    {
        for (id object in self.appropriateObjectsForInspection) {
            [object setValue:value forKeyPath:_keyPath];
        }
    }
    [inspector didEndChangingInspectedObjects];
}

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:_objectClass];
}


@end
