// Copyright 1997-2005, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Cocoa/Cocoa.h>

#import <OmniAppKit/NSBundle-OAExtensions.h>
#import <OmniAppKit/NSNib-OAExtensions.h>

RCS_ID("$Id$")

@implementation NSBundle (OAExtensions)

+ (NSBundle *)OmniAppKit;
{
    return [self bundleWithIdentifier:@"com.omnigroup.OmniAppKit"];
}

+ (NSArray *)loadNibNamed:(NSString *)nibName owner:(id <NSObject>)owner options:(NSDictionary *)options;
{
    NSBundle *bundle = [NSBundle bundleForClass:[owner class]];
    return [bundle loadNibNamed:nibName owner:owner options:options];
}

- (NSArray *)loadNibNamed:(NSString *)nibName owner:(id)owner options:(NSDictionary *)options;
{
    NSNib *nib = [[NSNib alloc] initWithNibNamed:nibName bundle:self];
    
    NSArray *topLevelObjects;
    @try {
        topLevelObjects = [nib instantiateNibWithOwner:owner options:nil];
    } @finally {
        [nib release];
    }
    
    return topLevelObjects;
}

#pragma mark - Deprecated

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

