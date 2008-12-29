// Copyright 2004-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFVersionNumber.h 102831 2008-07-15 00:30:17Z bungi $

#import <Foundation/NSObject.h>
#import <OmniBase/system.h>

@interface OFVersionNumber : NSObject <NSCopying>
{
    NSString *_originalVersionString;
    NSString *_cleanVersionString;
    
    unsigned int  _componentCount;
    unsigned int *_components;
}

+ (OFVersionNumber *)userVisibleOperatingSystemVersionNumber;

- initWithVersionString:(NSString *)versionString;

- (NSString *)originalVersionString;
- (NSString *)cleanVersionString;

- (unsigned int)componentCount;
- (unsigned int)componentAtIndex:(unsigned int)componentIndex;

- (NSComparisonResult)compareToVersionNumber:(OFVersionNumber *)otherVersion;

@end
