// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSDictionary.h>

// Internal class for returning snapshots to clients.

@class ODOObjectID;

@interface ODOSnapshotDictionary : NSDictionary
{
@private
    ODOObjectID *_objectID;
    NSArray *_snapshot;
}

- initWithObjectID:(ODOObjectID *)objectID snapshot:(NSArray *)snapshot;

@end
