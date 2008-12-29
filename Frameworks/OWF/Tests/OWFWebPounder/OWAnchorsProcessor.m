// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWAnchorsProcessor.h"

#import <OmniBase/OmniBase.h>
#import <OWF/OWF.h>
#import <OWF/OWContent.h>

RCS_ID("$Id$")

NSString *OWAnchorsResultContentTypeString = @"ObjectStream/Anchors";

static OWContentType *OWAnchorsProcessorSourceContentType = nil;
static OWContentType *OWAnchorsProcessorResultContentType = nil;

static OWSGMLTagType *anchorTagType;
static unsigned int   anchorHrefAttributeIndex;

@implementation OWAnchorsProcessor

+ (void) initialize;
{
    OWSGMLMethods *methods;
    OWSGMLDTD *dtd;

    OBINITIALIZE;

    OWAnchorsProcessorSourceContentType = [[OWContentType contentTypeForString: @"ObjectStream/sgml"] retain];
    OWAnchorsProcessorResultContentType = [[OWContentType contentTypeForString: OWAnchorsResultContentTypeString] retain];
    
    [self registerProcessorClass: self
                 fromContentType: OWAnchorsProcessorSourceContentType
                   toContentType: OWAnchorsProcessorResultContentType
                            cost: 1.0
                 producingSource: NO];

    dtd = [self dtd];
    anchorTagType = [dtd tagTypeNamed:@"a"];
    anchorHrefAttributeIndex = [anchorTagType addAttributeNamed:@"href"];

    methods = [self sgmlMethods];
    [methods registerMethod:@"Anchor" forTagName:@"a"];
}

+ (OWContentType *) anchorsContentType;
{
    return OWAnchorsProcessorResultContentType;
}

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline
{
    if (![super initWithContent:initialContent context:aPipeline])
        return nil;

    _outputObjectStream = [[OWObjectStream alloc] init];
    
    return self;
}

- (void) dealloc;
{
    [_outputObjectStream release];
    [super dealloc];
}


//
// OWSGMLProcessor subclass
//

- (void)processBegin;
{
    OWContent *outputContent;
    
    [super processBegin];
    [self setStatusString:@"Finding anchors"];

    outputContent = [(OWContent *)[OWContent alloc] initWithContent:_outputObjectStream];
    [outputContent setContentTypeString:OWAnchorsResultContentTypeString];
    [outputContent markEndOfHeaders];
    [outputContent autorelease];

    [pipeline addContent:outputContent fromProcessor:self flags:OWProcessorTypeDerived];
}

- (void)process;
{
    [super process];
}

- (void)processEnd;
{
    [_outputObjectStream dataEnd];
}

- (void)processAbort;
{
    [_outputObjectStream dataAbort];
}

//
// Registered SGML methods
//

- (void)processAnchorTag:(OWSGMLTag *)tag;
{
    // NSLog(@"anchor = %@", tag);
    // [_outputObjectStream writeObject: tag];
    [_outputObjectStream writeObject:[self addressForAnchorTag: tag]];
}

@end

