// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOSnapshotDictionary.h 104583 2008-09-06 21:23:18Z kc $

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
