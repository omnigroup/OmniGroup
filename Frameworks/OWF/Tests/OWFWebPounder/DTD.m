// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "DTD.h"

#import <OmniBase/OmniBase.h>
#import <OWF/OWF.h>

RCS_ID("$Id$")

@implementation OWSGMLProcessor (DTD)

+ (OWSGMLDTD *)dtd;
{
    static OWSGMLDTD *dtd = nil;
    OWContentType *html, *sgml;

    if (dtd)
        return dtd;

    html = [OWContentType contentTypeForString:@"text/html"];
    sgml = [OWContentType contentTypeForString:@"ObjectStream/sgml"];

    [OWHTMLToSGMLObjects registerProcessorClass:[OWHTMLToSGMLObjects class] fromContentType:html toContentType:sgml cost:1.0 producingSource:NO];

    dtd = [[OWSGMLDTD registeredDTDForSourceContentType:html destinationContentType:sgml] retain];

    return dtd;
}

@end

