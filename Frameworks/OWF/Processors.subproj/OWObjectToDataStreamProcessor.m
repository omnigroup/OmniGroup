// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWObjectToDataStreamProcessor.h>
#import <OWF/OWDataStreamCharacterProcessor.h>

#import <OWF/OWDataStream.h>
#import <OWF/OWContent.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OWObjectToDataStreamProcessor

+ (NSString *)resultContentType
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)startProcessing;
{
    OBPRECONDITION(outputStream == nil);

    outputStream = [[OWDataStream alloc] init];
    OWContent *outputContent = [[OWContent alloc] initWithContent:outputStream];
    [outputContent setContentTypeString:[[self class] resultContentType]];
    [outputContent setCharsetProvenance:OWStringEncodingProvenance_Generated];
    [outputContent markEndOfHeaders];

    // In case our subclass is intending to write strings, make sure the data stream's writeEncoding is set to the same encoding that a reader will expect based on its content-type
    CFStringEncoding writeEncoding = [OWDataStreamCharacterProcessor stringEncodingForContentType:[outputContent fullContentType]];
    if (writeEncoding != kCFStringEncodingInvalidId)
        [outputStream setWriteEncoding:writeEncoding];
    
    [self.pipeline addContent:outputContent fromProcessor:self flags:OWProcessorTypeDerived];

    [super startProcessing];
}

- (void)processAbort;
{
    [outputStream dataAbort];
    [super processAbort];
}

@end

