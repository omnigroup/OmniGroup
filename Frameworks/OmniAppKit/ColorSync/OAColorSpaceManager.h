// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OAColorSpaceHelper : NSObject
@property (readwrite, nonatomic, retain) NSString *sha1;
@property (readwrite, nonatomic, retain) NSColorSpace *colorSpace;
@end

@interface OAColorSpaceManager : NSObject

@property (readwrite, nonatomic, retain) NSMutableArray *colorSpaceList;
// A list of OAColorSpaceHelpers

- (NSArray *)propertyListRepresentations;
- (void)loadPropertyListRepresentations:(NSArray *)array;

+ (BOOL)isColorSpaceGeneric:(NSColorSpace *)colorSpace;
// generic rgb, generic gray, or generic cmyk

+ (NSString *)nameForColorSpace:(NSColorSpace *)colorSpace;
// returns a shorthand name for Apple default colorspaces, otherwise nil
+ (NSColorSpace *)colorSpaceForName:(NSString *)name;

- (NSString *)nameForColorSpace:(NSColorSpace *)colorSpace;
// returns a shorthand name for Apple default colorspaces
// returns an unadornedLowercaseHexString sha-1 of the iccprofile data for unknown colorspaces and adds them to the list
- (NSColorSpace *)colorSpaceForName:(NSString *)name;
// checks the shorthand names, and the sha-1 strings
// nil if not found
@end
