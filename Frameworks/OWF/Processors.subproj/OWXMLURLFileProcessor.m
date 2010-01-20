// Copyright 1999-2005, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWXMLURLFileProcessor.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniFoundation/OFResourceFork.h>

#import "OWContent.h"
#import "OWContentType.h"
#import "OWAddress.h"
#import "OWDataStreamProcessor.h"
#import "OWDataStreamScanner.h"
#import "OWDataStreamCharacterCursor.h"
#import "OWPipeline.h"

RCS_ID("$Id$")

static OWContentType *sourceContentType;

@interface OWXMLURLFileProcessor (Private)
- (OWAddress *)addressFromXMLData;
- (OWAddress *)addressFromResourceFork;
@end

@implementation OWXMLURLFileProcessor

+ (void)initialize;
{
    OBINITIALIZE;

    sourceContentType = [OWContentType contentTypeForString:@"application/x-xml-url"];
}

+ (void)didLoad;
{
    [self registerProcessorClass:self fromContentType:sourceContentType toContentType:[OWContentType wildcardContentType] cost:1.0f producingSource:YES];
}

+ (OWContentType *)sourceContentType;
{
    return sourceContentType;
}

- (void)process;
{
    OWAddress *anAddress;
    
    anAddress = [self addressFromXMLData];
    if (anAddress == nil)
        anAddress = [self addressFromResourceFork];
    if (anAddress == nil)
        return;
    
    [pipeline addContent:[OWContent contentWithAddress:anAddress] fromProcessor:self flags:OWProcessorContentNoDiskCache|OWProcessorTypeRetrieval];
}

@end

@implementation OWXMLURLFileProcessor (Private)

- (OWAddress *)addressFromXMLData;
{
    OWDataStreamScanner *dataStreamScanner;
    NSString *urlString;

    // Sherlock before 10.0 wrote Mac OS content type "ilht" files that look like this:
    //
    // <?xml version="1.0" encoding="UTF-8"?>
    // <!DOCTYPE plist SYSTEM "file://localhost/System/Library/DTDs/PropertyList.dtd">
    // <plist version="0.9">
    // <dict>
    // 	<key>URL</key>
    // 	<string>http://search.britannica.com/sherlock_redir.jsp?href=http%3A%2F%2Fwww.britannica.com%2Fbcom%2Feb%2Farticle%2F1%2F0%2C5716%2C42921%2B1%2B41973%2C00.html</string>
    // </dict>
    // </plist>

    // After 10.0, Sherlock and OmniWeb are writing "ilht" that ONLY contain resource forks, and have empty data forks.  YIPES!
    
    dataStreamScanner = [[[OWDataStreamScanner alloc] initWithCursor:characterCursor] autorelease];
    
    if (![dataStreamScanner scanString:@"<?xml version" peek:YES])
        return nil;
        
    if (![dataStreamScanner scanUpToString:@"<string>"])
        return nil;
    if (![dataStreamScanner scanString:@"<string>" peek:NO])
        return nil;
        
    urlString = [dataStreamScanner readFullTokenWithDelimiterCharacter:'<'];
    if (urlString == nil || [urlString length] == 0)
        return nil;

    return [OWAddress addressForDirtyString:urlString];
}

- (OWAddress *)addressFromResourceFork;
{
    OWAddress *sourceAddress;
    NSString *filePath;
    OFResourceFork *fork;
    NSData *resourceData;
    NSString *urlString = nil;
    OWAddress *address = nil;
    
    sourceAddress = [[self pipeline] contextObjectForKey:OWCacheArcSourceAddressKey];
    if (sourceAddress == nil)
        return nil;
    filePath = [sourceAddress localFilename];
    fork = [[OFResourceFork alloc] initWithContentsOfFile:filePath forkType:OFResourceForkType];
    resourceData = [fork dataForResourceType:FOUR_CHAR_CODE('url ') atIndex:0];
    if (resourceData != nil)
        urlString = [[NSString alloc] initWithData:resourceData encoding:NSMacOSRomanStringEncoding];
    [fork release];
    if (urlString != nil && [urlString length] > 0)
        address = [OWAddress addressForDirtyString:urlString];
    [urlString release];
    return address;
}

@end
