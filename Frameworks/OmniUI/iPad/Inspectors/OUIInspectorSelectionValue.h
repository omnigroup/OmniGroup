// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@interface OUIInspectorSelectionValue : OFObject
{
@private
    id _dominantValue;
    NSSet *_uniqueValues;
}

- initWithValue:(id)value;
- initWithValues:(NSArray *)values;

@property(readonly) id dominantValue;
@property(readonly) NSSet *uniqueValues;
@property(readonly) id uniqueValue; // dominantValue if that is the only value, nil otherwise

@end
