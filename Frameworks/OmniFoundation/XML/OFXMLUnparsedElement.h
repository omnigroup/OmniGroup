// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/XML/OFXMLUnparsedElement.h 102859 2008-07-15 04:28:01Z bungi $

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
