// Copyright 2001-2008, 2010-2011, 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSURunOperationParameters.h"

RCS_ID("$Id$");

OB_REQUIRE_ARC // Since we don't have a -dealloc method

@implementation OSURunOperationParameters

#pragma mark - NSSecureCoding

// Needed for passing over a XPC connection
+ (BOOL)supportsSecureCoding;
{
    return YES;
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)aCoder;
{
#define ENC_OBJECT(x) [aCoder encodeObject:_ ## x forKey:@"" #x]
#define ENC_BOOL(x) [aCoder encodeBool:_ ## x forKey:@"" #x]
    
    ENC_OBJECT(firstHopHost);
    ENC_OBJECT(baseURLString);
    ENC_OBJECT(appIdentifier);
    ENC_OBJECT(appVersionString);
    ENC_OBJECT(track);
    
    ENC_BOOL(includeHardwareInfo);
    ENC_BOOL(reportMode);
    
    ENC_OBJECT(uuidString);
    ENC_OBJECT(licenseType);
    ENC_OBJECT(osuVersionString);
}

- (id)initWithCoder:(NSCoder *)aDecoder; // NS_DESIGNATED_INITIALIZER
{
    if (!(self = [super init]))
        return nil;
    
#define DEC_OBJECT(cls, x) _ ## x = [(typeof(_ ## x))[aDecoder decodeObjectOfClass:[cls class] forKey:@"" #x] copy]
#define DEC_BOOL(x) _ ## x = [aDecoder decodeBoolForKey:@"" #x]
    
    DEC_OBJECT(NSString, firstHopHost);
    DEC_OBJECT(NSString, baseURLString);
    DEC_OBJECT(NSString, appIdentifier);
    DEC_OBJECT(NSString, appVersionString);
    DEC_OBJECT(NSString, track);
    
    DEC_BOOL(includeHardwareInfo);
    DEC_BOOL(reportMode);
    
    DEC_OBJECT(NSString, uuidString);
    DEC_OBJECT(NSString, licenseType);
    DEC_OBJECT(NSString, osuVersionString);
    
    return self;
}

@end
