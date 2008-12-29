// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWObjectTree.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
//#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>

RCS_ID("$Id$")

@implementation OWObjectTree

- initWithRepresentedObject:(id <NSObject>)object;
{
    [super initWithParent:nil representedObject:object];
    nonretainedRoot = self;
    OFSimpleLockInit(&mutex);
    contentInfo = [[OWContentInfo alloc] initWithContent:self typeString:@"ObjectTree"]; 
    // The string "ObjectTree" should technically be localized --- it can theoretically show up in the UI. Not a problem in practice I think.
    return self;
}

- (void)dealloc;
{
    [contentInfo nullifyContent];
    [contentInfo release];
    OFSimpleLockFree(&mutex);
    [super dealloc];
}

- (void)setContentType:(OWContentType *)aContentType;
{
    nonretainedContentType = aContentType;
}

- (void)setContentTypeString:(NSString *)aString;
{
    [self setContentType:[OWContentType contentTypeForString:aString]];
}

// OWContent protocol

- (OWContentType *)contentType;
{
    return nonretainedContentType;
}

- (OWContentInfo *)contentInfo;
{
    return contentInfo;
}

@end

@implementation OWObjectTree (lockAccess)

- (OFSimpleLockType *)mutex;
{
    return &mutex;
}

@end
