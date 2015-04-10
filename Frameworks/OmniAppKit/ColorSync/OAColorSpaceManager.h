//
//  OAColorSpaceManager.h
//  OmniAppKit
//
//  Created by Kevin Steele on 4/7/15.
//
//

#import <Foundation/Foundation.h>

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
