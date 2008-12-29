// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OWF/OWDataStream.h>

@interface OWFileDataStream : OWDataStream
{
    NSString *inputFilename;
}

- initWithData:(NSData *)data filename:(NSString *)aFilename;
- initWithContentsOfFile:(NSString *)aFilename;
- initWithContentsOfMappedFile:(NSString *)aFilename;

@end
