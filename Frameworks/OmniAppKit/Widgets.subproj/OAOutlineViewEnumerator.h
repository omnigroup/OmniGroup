// Copyright 2000-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAOutlineViewEnumerator.h 104581 2008-09-06 21:18:23Z kc $


#import <OmniFoundation/OFObject.h>

@class NSOutlineView;
@class NSArray;

@interface OAOutlineViewEnumerator : OFObject
{
    NSOutlineView *_outlineView;
    id             _dataSource;
    
    struct OAOutlineViewEnumeratorState *_state;
    unsigned int _stateCount;
    unsigned int _stateCapacity;
}

- initWithOutlineView: (NSOutlineView *) outlineView
          visibleItem: (id) visibleItem;

- (NSArray *) nextPath;
- (NSArray *) previousPath;

- (void) resetToBeginning;
- (void) resetToEnd;

@end
