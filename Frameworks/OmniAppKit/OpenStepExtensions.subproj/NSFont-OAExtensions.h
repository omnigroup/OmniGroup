// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSFont.h>

@interface NSFont (OAExtensions)

- (BOOL)isScreenFont;

+ (NSFont *)fontFromPropertyListRepresentation:(NSDictionary *)dict;
- (NSDictionary *)propertyListRepresentation;

- (NSString *)panose1String;  // Returns nil if not available, otherwise a 10-number string

@end
