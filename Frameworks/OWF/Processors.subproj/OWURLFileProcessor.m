// Copyright 1999-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWURLFileProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContent.h>
#import <OWF/OWContentType.h>
#import <OWF/OWAddress.h>
#import <OWF/OWDataStreamProcessor.h>
#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWPipeline.h>

RCS_ID("$Id$")

static OWContentType *sourceContentType;

@implementation OWURLFileProcessor

+ (void)initialize;
{
    OBINITIALIZE;

    sourceContentType = [OWContentType contentTypeForString:@"application/x-url"];
}

OBDidLoad(^{
    Class self = [OWURLFileProcessor class];
    [self registerProcessorClass:self fromContentType:sourceContentType toContentType:[OWContentType wildcardContentType] cost:1.0f producingSource:NO];
});

+ (OWContentType *)sourceContentType;
{
    return sourceContentType;
}

- (void)process;
{
    NSString *line = [characterCursor readLine];

    // Internet Explorer writes .url files that look like this:
    //
    // [InternetShortcut]
    // URL=http://www.omnigroup.com/

    if ([line isEqualToString:@"[InternetShortcut]"]) {
        line = [characterCursor readLine];
        if ([line hasPrefix:@"URL="])
            line = [line substringFromIndex:4];
    }

    OWAddress *anAddress = [OWAddress addressForDirtyString:line];
    [self.pipeline addContent:[OWContent contentWithAddress:anAddress] fromProcessor:self flags:OWProcessorContentNoDiskCache|OWProcessorTypeRetrieval];
}

@end
