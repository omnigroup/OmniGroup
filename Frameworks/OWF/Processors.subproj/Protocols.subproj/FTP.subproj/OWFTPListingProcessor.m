// Copyright 2003-2006, 2011 Omni Development, Inc. All rights reserved.
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

    baseAddress = [[pipeline contextObjectForKey:OWCacheArcSourceAddressKey] retain];

    return self;
}

- (void)dealloc;
{
    [objectStream release];
    [baseAddress release];
    [super dealloc];
}

- (void)startProcessing
{
    OWContent *resultContent;
    
    OBPRECONDITION(objectStream == nil);

    objectStream = [[OWObjectStream alloc] init];

    resultContent = [[OWContent alloc] initWithContent:objectStream];
    [resultContent setContentTypeString:@"ObjectStream/OWFileInfoList"];
    [resultContent markEndOfHeaders];
    [pipeline addContent:resultContent fromProcessor:self flags:OWProcessorTypeDerived];
    [resultContent release];

    [super startProcessing];
}

- (void)addFileForLine:(NSString *)line
{
    OWFileInfo *fileInfo = [self fileInfoForLine:line];
    OWContent *fileInfoContent;
    
    if (fileInfo == nil)
        return;

    [objectStream writeObject:fileInfo];
    
    // Store file info in the cache for use by other processes
    fileInfoContent = [[OWContent alloc] initWithContent:fileInfo];
    [fileInfoContent markEndOfHeaders];
    [pipeline extraContent:fileInfoContent fromProcessor:self forAddress:[fileInfo address]];
    [fileInfoContent release];
}

- (OWFileInfo *)fileInfoForLine:(NSString *)line;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#define LINES_PER_POOL (25)

- (void)process;
{
    NSString *line;
    int linesUntilNewPool;
    NSAutoreleasePool *pool;
    NSException *pendingException;

    pool = nil;
    pendingException = nil;
    linesUntilNewPool = 0;
    lineNumber = 0;
    NS_DURING;
    for(;;) {
        if (linesUntilNewPool < 1) {
            [pool release];
            pool = [[NSAutoreleasePool alloc] init];
            linesUntilNewPool = LINES_PER_POOL;
        }
        line = [characterCursor readLine];
        if (!line)
            break;
        linesUntilNewPool --;
        lineNumber ++;
        [self addFileForLine:line];
    }
    NS_HANDLER {
        [localException retain];
        [pool release];
        pool = nil;
        pendingException = [localException autorelease];
    } NS_ENDHANDLER; 
    [objectStream dataEnd];
    [pool release];
    if (pendingException)
        [pendingException raise];
}

- (void)processAbort;
{
    [objectStream dataAbort];
    [super processAbort];
}

@end

