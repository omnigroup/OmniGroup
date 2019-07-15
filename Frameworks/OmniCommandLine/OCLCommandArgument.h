// Copyright 2012-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

typedef enum {
    OCLCommandArgumentTypeString,
    OCLCommandArgumentTypeFile, // produces a URL, but the command line is interpreted as a file path
    OCLCommandArgumentTypeURL,
} OCLCommandArgumentType;

@interface OCLCommandArgument : NSObject

+ (instancetype)argumentWithName:(NSString *)name type:(OCLCommandArgumentType)type optional:(BOOL)optional;

- (id)initWithName:(NSString *)name type:(OCLCommandArgumentType)type optional:(BOOL)optional;
- (id)initWithSpecification:(NSString *)specification;

@property(nonatomic,readonly) NSString *name;
@property(nonatomic,readonly) OCLCommandArgumentType type;
@property(nonatomic,readonly) BOOL optional;

@property(nonatomic,readonly) NSString *usageDescription;

- (id)valueForString:(NSString *)string;

@end
