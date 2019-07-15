// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class ODAVFileInfo;

NS_ASSUME_NONNULL_BEGIN

@class NSRegularExpression;

extern NSString * const ODAVStaleFilesPreferenceKey;

@interface ODAVStaleFiles : NSObject

/// Creates an instance with a given identifier for remembering how long files have been around.
///
/// `ident` must uniquely correspond to the directory whose contents is passed to `-examineDirectoryContents:localDate:serverDate:`. A URL is a good choice.
- (instancetype __nullable)initWithIdentifier:(NSString *)ident NS_DESIGNATED_INITIALIZER;

@property (nonatomic,readonly,copy) NSString *identifier;

/// Filters the filenames we consider for removal. Not stored; you must pass the same pattern in for a given identifier each time, or you'll get inconsistent results.
@property (nonatomic,nullable,copy) NSRegularExpression *pattern;

/// Returns the items in `currentItems` that match pattern and are sufficiently stale to warrant deleting.
///
/// Call this when you get a directory listing. `currentItems` will be filtered to only those matching `self.pattern` if set. If there are items that should not be deleted even if they are old, then either don't include them in `currentItems` or ensure that `self.pattern` is set to filter them.
///
/// - parameter currentItems
/// - parameter serverDate: the current time according to the server's clock, used to correct for clock skew
- (NSArray <ODAVFileInfo *> *)examineDirectoryContents:(NSArray <ODAVFileInfo *> *)currentItems serverDate:(NSDate *)serverDate;

// Testing Extensions
@property (nonatomic, retain, nullable) NSMutableDictionary *userDefaultsMock;
- (NSArray <ODAVFileInfo *> *)examineDirectoryContents:(NSArray <ODAVFileInfo *> *)currentItems localDate:(NSDate *)localDate serverDate:(NSDate *)serverDate;
@end

NS_ASSUME_NONNULL_END
