// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OWF/OWDataStreamProcessor.h>

@class NSData;

@interface OWUnknownDataStreamProcessor : OWDataStreamProcessor
{
    OWContent *workingContent;
}

+ (OWContentType *)unknownContentType;
+ (void)registerGuessesDictionary:(NSDictionary *)guessesDictionary;

@end
