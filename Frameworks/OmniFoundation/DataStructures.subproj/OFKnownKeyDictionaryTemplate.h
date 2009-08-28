// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray, NSObject;

@interface OFKnownKeyDictionaryTemplate : OFObject
/*.doc.
This class holds information common to a set of OFMutableKnownKeyDictionaries.  This makes the space requirements for OFMutableKnownKeyDictionary smaller.  Instances of this class are variable size, so this class cannot be subclassed easily.
*/
{
@public // These should really only be accessed by OFMutableKnownKeyDictionary
    NSArray *_keyArray;
    NSUInteger _keyCount;
    NSObject *_keys[0];
}

+ (OFKnownKeyDictionaryTemplate *) templateWithKeys: (NSArray *) keys;
/*.doc.
Returns a uniqued instance of OFKnownKeyDictionaryTemplate.
*/

- (NSArray *) keys;
/*.doc.
Returns the keys of this template.
*/

@end
