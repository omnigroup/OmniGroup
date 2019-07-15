// Copyright 2009-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLMaker.h>

@class NSOutputStream;
struct _xmlTextWriter;

/* OFXMLTextWriterSink is a concrete subclass of XMLSink which writes its nodes into a libxml2 'xmlTextWriter'. */
@interface OFXMLTextWriterSink : OFXMLSink

// API
- (instancetype)initWithTextWriter:(struct _xmlTextWriter *)w freeWhenDone:(BOOL)shouldFree
        NS_SWIFT_UNAVAILABLE("libxml2 types are not available to Swift");
- (instancetype)initWithStream:(NSOutputStream *)outputStream;
- (void)flush;

@end

