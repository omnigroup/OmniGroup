// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class ODAVFileInfo;

NS_ASSUME_NONNULL_BEGIN

@class NSRegularExpression;

@interface ODAVStaleFiles : NSObject

/* Create an instance with a given identifier for remembering how long a given file has been around. The identifier must uniquely correspond to the directory whose contents is passed to -examineDirectoryContents:serverDate:. A URL is a good choice. */
- (instancetype __nullable)initWithIdentifier:(NSString *)ident NS_DESIGNATED_INITIALIZER;

@property (readonly,nonatomic,copy) NSString *identifier;
@property (readwrite,nonatomic,nullable,copy) NSRegularExpression *pattern;  // Optional; filters the filenames we consider for removal. Not stored; you must pass the same pattern in for a given identifier each time, or you'll get inconsistent results.

/* Call this when you get a directory listing. CurrentItems must be filtered to contain only the items that should be deleted if they stick around for too long (if the pattern property is non-nil, it will further filter currentItems.) The returned array contains items which have been here for a long time and can safely be deleted. */
- (NSArray <ODAVFileInfo *> *)examineDirectoryContents:(NSArray <ODAVFileInfo *> *)currentItems serverDate:(NSDate * __nullable)serverDate;

@end

NS_ASSUME_NONNULL_END
