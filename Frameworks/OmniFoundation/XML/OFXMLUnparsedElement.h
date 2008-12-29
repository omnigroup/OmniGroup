// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@interface OFXMLUnparsedElement : OFObject
{
@private
    NSString *_name;
    NSData *_data;
}

- initWithName:(NSString *)name data:(NSData *)data; 

- (NSString *)name;
- (NSData *)data;

@end
