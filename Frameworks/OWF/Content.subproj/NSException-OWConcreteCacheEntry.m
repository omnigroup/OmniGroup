// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/NSException-OWConcreteCacheEntry.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWContentType.h>

RCS_ID("$Id$");

@implementation NSException (OWConcreteCacheEntry)

- (BOOL)endOfData;
{
    return YES;
}

- (BOOL)contentIsValid;
{
    return YES;
}

- (OWContentType *)contentType;
{
    return [OWContentType contentTypeForString:@"Omni/ErrorContent"];
}

@end

