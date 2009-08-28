// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.
//
// $Id$

#import <OmniFoundation/OFXMLMaker.h>

/* XMLCFXMLTreeSink is a concrete subclass of XMLSink which writes its nodes into a CFXMLTree. */
@interface OFXMLCFXMLTreeSink : OFXMLSink
{
    CFXMLTreeRef topNode, currentEltTree;
#ifdef DEBUG
    OFXMLMaker *currentElt;
#endif
}

- initWithCFXMLTree:(CFXMLTreeRef)toplevel;

- (void)learnAncestralNamespaces;

- (CFXMLTreeRef)topNode;
- (void)addCFXMLNode:(CFXMLNodeRef)newNode;

- (NSData *)xmlData;

@end

