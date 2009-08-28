// Copyright 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.
//
// $Id$

#import <OmniFoundation/OFXMLMaker.h>

/* OFLibXML2Sink is a concrete subclass of XMLSink which writes its nodes into a libxml2 'xmlTextWriter'. */
@interface OFXMLTextWriterSink : OFXMLSink
{
    struct _xmlTextWriter *writer;
#ifdef DEBUG
    OFXMLMaker *currentElt;
#endif
}

// API
- initWithTextWriter:(struct _xmlTextWriter *)w freeWhenDone:(BOOL)shouldFree;
- (void)flush;

@end

