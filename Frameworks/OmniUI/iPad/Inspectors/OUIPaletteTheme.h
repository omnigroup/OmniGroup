// Copyright 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray, NSDictionary, NSString;

@interface OUIPaletteTheme : OFObject

+ (NSArray *)defaultThemes;

- initWithDictionary:(NSDictionary *)dict stringTable:(NSString *)stringTable bundle:(NSBundle *)bundle;

@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSString *displayName;
@property(nonatomic,readonly) NSArray *colors;

@end
