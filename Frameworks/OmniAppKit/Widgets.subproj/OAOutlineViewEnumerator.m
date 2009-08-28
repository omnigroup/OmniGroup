// Copyright 2000-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAOutlineViewEnumerator.h"

#import <OmniBase/OmniBase.h>
#import <AppKit/NSOutlineView.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <string.h>

RCS_ID("$Id$")

struct OAOutlineViewEnumeratorState {
    id item;
    NSInteger index;
    NSInteger count;
};

@implementation OAOutlineViewEnumerator

- (void) _prependItem: (id) item index: (NSInteger) index count: (NSInteger) count;
{
    if (_stateCount >= _stateCapacity) { 
        _stateCapacity *= 2; 
        _state = NSZoneRealloc(NULL, _state, sizeof(*_state) * _stateCapacity);
    }
    
    memmove(&_state[1], &_state[0], _stateCount * sizeof(*_state));
    _state[0].item  = item;
    _state[0].index = index;
    _state[0].count = count;
    _stateCount++;
}

- (void) _appendEmptyItem;
{
    if (_stateCount >= _stateCapacity) { 
        _stateCapacity *= 2; 
        _state = NSZoneRealloc(NULL, _state, sizeof(*_state) * _stateCapacity);
    }
    _stateCount++;
}

#ifdef OMNI_ASSERTIONS_ON
- (BOOL) _checkState
{
    unsigned int stateIndex;
    id parentItem;
    struct OAOutlineViewEnumeratorState *state;
    
    parentItem = nil;
    state = _state;
    for (stateIndex = 0; stateIndex < _stateCount; stateIndex++, state++) {
        OBASSERT(!parentItem || [_dataSource outlineView: _outlineView isItemExpandable: parentItem]);
        OBASSERT([_dataSource outlineView: _outlineView numberOfChildrenOfItem: parentItem] == state->count);
        OBASSERT([_dataSource outlineView: _outlineView child: state->index ofItem: parentItem] == state->item);
        parentItem = state->item;
    }
    
    return YES;
}
#endif

- initWithOutlineView: (NSOutlineView *) outlineView
          visibleItem: (id) visibleItem;
{
    NSInteger row, level, childIndex;
    id childItem, parentItem;
    
    _outlineView = [outlineView retain];
    _dataSource = [[outlineView dataSource] retain];

    _stateCount = 0;
    _stateCapacity = 32;
    _state = NSZoneMalloc(NULL, sizeof(*_state) * _stateCapacity);
    
    // Now, figure out the path to the specified item, which MUST be visible
    row = [_outlineView rowForItem: visibleItem];
    if (row == NSNotFound) {
        [self release];
        return nil;
    }

    // The number of previous rows at the same level gives the index of the
    // child in the parents list of children.  We need to be careful that
    // we don't count open children.
    level = [_outlineView levelForRow: row];
    childIndex = 0;
    childItem = visibleItem;
    //NSLog(@"starting at row = %d, level = %d, childItem = %@", row, level, [childItem label]);
    while (row--) {
        NSInteger newLevel;
        
        newLevel = [_outlineView levelForRow: row];
        //NSLog(@"  new level = %d", newLevel);
        if (newLevel == level) {
            // A previous sibling
            childIndex++;
            //NSLog(@"  sibling, childIndex = %d", childIndex);
        } else if (newLevel < level) {
            // This row must be the parent for the current item.
            OBASSERT(newLevel == level - 1);
            
            parentItem = [_outlineView itemAtRow: row];
            //NSLog(@"  parent = %@", [parentItem label]);
            [self _prependItem: childItem
                         index: childIndex
                         count: [_dataSource outlineView: _outlineView numberOfChildrenOfItem: parentItem]];
            childItem = parentItem;
            childIndex = 0;
            level = newLevel;
        } else {
            // One of the previous siblings must be open and this is one of its decendants
        }
    }
    
    [self _prependItem: childItem
                 index: childIndex
                 count: [_dataSource outlineView: _outlineView numberOfChildrenOfItem: nil]];
    
    OBPOSTCONDITION([self _checkState]);
    OBPOSTCONDITION(_state[_stateCount - 1].item == visibleItem);
    
    return self;
}

- (void) dealloc;
{
    NSZoneFree(NULL, _state);
    [_outlineView release];
    [_dataSource release];
    [super dealloc];
}

- (NSArray *) nextPath;
{
    struct OAOutlineViewEnumeratorState *state;
    NSInteger childCount;
    NSMutableArray *path;
    
    OBPRECONDITION([self _checkState]);
    
    // Grab the current item, describe by the state path
    if (_stateCount) {
        unsigned int pathIndex;
        
        path = [NSMutableArray arrayWithCapacity: _stateCount];
        for (pathIndex = 0; pathIndex < _stateCount; pathIndex++)
            [path addObject: _state[pathIndex].item];
        
        // Step the state for the next item to return after this one.
        
        // Check if we can descend in this item (and it actually has children)
        state = &_state[_stateCount - 1];
        childCount = 0;
        if ([_dataSource outlineView: _outlineView isItemExpandable: state->item])
            childCount = [_dataSource outlineView: _outlineView numberOfChildrenOfItem: state->item];
            
        if (childCount) {
            [self _appendEmptyItem];
            state = &_state[_stateCount - 1];
            state->item = [_dataSource outlineView: _outlineView child: 0 ofItem: state[-1].item];
            state->index = 0;
            state->count = childCount;
        } else {
            // Can't go down.  We need to go to our next sibling.
            // Close off any entries that we've finished.
            while (_stateCount) {
                if (state->index == state->count - 1) {
                    // end it
                    //NSLog(@"nextItem -- ended %@", [state->item label]);
                    _stateCount--;
                    state--;
                } else {
                    id parent;
                    
                    // we have a next item
                    state->index++;
                    if (_stateCount > 1)
                        parent = state[-1].item;
                    else
                        parent = nil;
                        
                    //NSLog(@"nextItem -- looking for sibling %d of parent %@",
                    //      state->index, [parent label]);
                    state->item = [_dataSource outlineView: _outlineView child: state->index ofItem: parent];
                    break;
                }
            }
        }
    } else {
        // We don't have any more items
        path = nil;
    }

    OBPOSTCONDITION([self _checkState]);
    
    return path;
}

- (NSArray *) previousPath;
{
    struct OAOutlineViewEnumeratorState *state;
    NSMutableArray *path;

    //NSLog(@"START previousPath on %@", self);
    
    OBPRECONDITION([self _checkState]);

    if (_stateCount) {
        unsigned int pathIndex;
        
        path = [NSMutableArray arrayWithCapacity: _stateCount];
        for (pathIndex = 0; pathIndex < _stateCount; pathIndex++)
            [path addObject: _state[pathIndex].item];
        //NSLog(@"path = %@", path);
        
        // If the last item is on index zero, finish it off.  Don't finish off all trailing
        // items on index zero since each of them needs to be returned on a call to -previousPath
        state = &_state[_stateCount - 1];
        if (!state->index) {
            //NSLog(@"finished %@", [state->item label]);
            _stateCount--;
            state--;
        } else {
            id parent;
            
            // Back up to the previous sibling and descend into its last descendant.
            if (_stateCount > 1)
                parent = state[-1].item;
            else
                parent = nil;
            state->index--;
            state->item = [_dataSource outlineView: _outlineView child: state->index ofItem: parent];

            //NSLog(@"descending into %@", [state->item label]);
            parent = state->item;
            while (YES) {
                if (![_dataSource outlineView: _outlineView isItemExpandable: parent])
                    break;
                
                NSInteger count = [_dataSource outlineView: _outlineView numberOfChildrenOfItem: parent];
                if (!count)
                    break;
                
                // Take the last item
                [self _appendEmptyItem];
                state = &_state[_stateCount - 1];
                state->item = [_dataSource outlineView: _outlineView child: count - 1 ofItem: parent];
                state->index = count - 1;
                state->count = count;
                
                parent = state->item;
            }
            //NSLog(@"descending to %@", [state->item label]);
        }
    } else
        path = nil;
        
    //NSLog(@"END previousPath on %@", self);
    
    OBPOSTCONDITION([self _checkState]);
    return path;
}

- (void) resetToBeginning;
{
    OBPRECONDITION([self _checkState]);
    _state[0].count = [_dataSource outlineView: _outlineView numberOfChildrenOfItem: nil];
    if (_state[0].count) {
        _stateCount = 1;
        _state[0].index = 0;
        _state[0].item = [_dataSource outlineView: _outlineView child: 0 ofItem: nil];
    } else {
        _stateCount = 0;
    }
    OBPOSTCONDITION([self _checkState]);
}

- (void) resetToEnd;
{
    id parent;
    struct OAOutlineViewEnumeratorState *state;
    
    OBPRECONDITION([self _checkState]);

    parent = nil;
    _stateCount = 0;
    
    while (YES) {
        
        if (parent && ![_dataSource outlineView: _outlineView isItemExpandable: parent])
            break;
        
        NSInteger count = [_dataSource outlineView: _outlineView numberOfChildrenOfItem: parent];
        if (!count)
            break;
        
        // Take the last item
        [self _appendEmptyItem];
        state = &_state[_stateCount - 1];
        state->item = [_dataSource outlineView: _outlineView child: count - 1 ofItem: parent];
        state->index = count - 1;
        state->count = count;
        
        parent = state->item;
    }
    OBPOSTCONDITION([self _checkState]);
}

//
// Debugging
//

- (NSMutableDictionary *) debugDictionary;
{
    NSMutableDictionary *dict;
    NSMutableArray *stateArray;
    unsigned int index;
    struct OAOutlineViewEnumeratorState *state;
    
    dict = [super debugDictionary];
    stateArray = [[NSMutableArray alloc] initWithCapacity: _stateCount];
    [dict setObject: stateArray forKey: @"state"];
    [stateArray release];
    
    state = _state;
    for (index = 0; index < _stateCount; index++, state++) {
        NSMutableDictionary *entry;
        
        entry = [[NSMutableDictionary alloc] init];
        [entry setObject: [NSNumber numberWithInt: state->index] forKey: @"index"];
        [entry setObject: [NSNumber numberWithInt: state->count] forKey: @"count"];
        [entry setObject: state->item forKey: @"item"];
        
        [stateArray addObject: entry];
        [entry release];
    }
    
    return dict;
}

@end
