// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFSignature.h 104581 2008-09-06 21:18:23Z kc $

#import <OmniFoundation/OFObject.h>

@class NSData;

// This is here so that those that want to define small buffers
// for a signature w/o yet having one can do so.
#define OF_SIGNATURE_LENGTH (20)

@interface OFSignature : OFObject
{
    void   *_private;
    NSData *_signatureData;
}

- initWithData: (NSData *) data;
- initWithBytes: (const void *) bytes length: (NSUInteger) length;

- (void) addData: (NSData *) data;
- (void) addBytes: (const void *) bytes length: (NSUInteger) length;

- (NSData *) signatureData;

@end
