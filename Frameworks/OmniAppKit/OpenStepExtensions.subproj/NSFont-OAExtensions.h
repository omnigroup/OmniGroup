// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSFont.h>

@interface NSFont (OAExtensions)

+ (NSFont *)heavySystemFontOfSize:(CGFloat)size;
+ (NSFont *)mediumSystemFontOfSize:(CGFloat)size;
+ (NSFont *)lightSystemFontOfSize:(CGFloat)size;
+ (NSFont *)thinSystemFontOfSize:(CGFloat)size;
+ (NSFont *)ultraLightSystemFontOfSize:(CGFloat)size;

- (BOOL)isScreenFont;

+ (NSFont *)fontFromPropertyListRepresentation:(NSDictionary *)dict;
- (NSDictionary *)propertyListRepresentation;

- (NSString *)panose1String;  // Returns nil if not available, otherwise a 10-number string

@end
