// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUnzip/OUZipMember.h>

@interface OUZipLinkMember : OUZipMember
{
@private
    NSString *_destination;
}

- initWithName:(NSString *)name date:(NSDate *)date destination:(NSString *)destination;

- (NSString *)destination;

@end
