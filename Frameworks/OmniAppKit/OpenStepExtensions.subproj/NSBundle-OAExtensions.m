// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSBundle-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSBundle-OAExtensions.m 68913 2005-10-03 19:36:19Z kc $")

@implementation NSBundle (OAExtensions)

- (void)loadNibNamed:(NSString *)nibName owner:(id <NSObject>)owner;
{
    NSMutableDictionary *ownerDictionary;
    BOOL successfulLoad;

    ownerDictionary = [[NSMutableDictionary alloc] init];
    [ownerDictionary setObject:owner forKey:@"NSOwner"];
    successfulLoad = [self loadNibFile:nibName externalNameTable:ownerDictionary withZone:[owner zone]];
    [ownerDictionary release];
    if (!successfulLoad)
        [NSException raise:NSInternalInconsistencyException format:@"Unable to load nib %@", nibName];
}

@end

