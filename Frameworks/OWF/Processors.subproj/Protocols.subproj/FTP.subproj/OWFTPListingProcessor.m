// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWFTPListingProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>

#import <OWF/OWAddress.h>
#import <OWF/OWContent.h>
#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWFileInfo.h>
#import <OWF/OWObjectStream.h>
#import <OWF/OWPipeline.h>

RCS_ID("$Id$");

@implementation OWFTPListingProcessor

+ (void)registerForContentTypeString:(NSString *)sourceType cost:(int)cost;
{
    [self registerProcessorClass:self fromContentTypeString:sourceType toContentTypeString:@"ObjectStream/OWFileInfoList" cost:cost producingSource:NO];
}

// Init and dealloc

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (!(self = [super initWithContent:initialContent context:aPipeline]))
        return nil;

    baseAddress = [self.pipeline contextObjectForKey:OWCacheArcSourceAddressKey];

    return self;
}

- (void)startProcessing
{
    OBPRECONDITION(objectStream == nil);

    objectStream = [[OWObjectStream alloc] init];

    OWContent *resultContent = [[OWContent alloc] initWithContent:objectStream];
    [resultContent setContentTypeString:@"ObjectStream/OWFileInfoList"];
    [resultContent markEndOfHeaders];
    [self.pipeline addContent:resultContent fromProcessor:self flags:OWProcessorTypeDerived];

    [super startProcessing];
}

- (void)addFileForLine:(NSString *)line
{
    OWFileInfo *fileInfo = [self fileInfoForLine:line];
    
    if (fileInfo == nil)
        return;

    [objectStream writeObject:fileInfo];
    
    // Store file info in the cache for use by other processes
    OWContent *fileInfoContent = [[OWContent alloc] initWithContent:fileInfo];
    [fileInfoContent markEndOfHeaders];
    [self.pipeline extraContent:fileInfoContent fromProcessor:self forAddress:[fileInfo address]];
}

- (OWFileInfo *)fileInfoForLine:(NSString *)line;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)process;
{
    lineNumber = 0;
    @try {
        for (;;) {
            @autoreleasepool {
                NSString *line = [characterCursor readLine];
                if (line == nil)
                    break;
                lineNumber++;
                [self addFileForLine:line];
            }
        }
    } @finally {
        [objectStream dataEnd];
    }
}

- (void)processAbort;
{
    [objectStream dataAbort];
    [super processAbort];
}

@end

