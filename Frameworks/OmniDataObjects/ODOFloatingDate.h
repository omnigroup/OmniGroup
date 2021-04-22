// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@import Foundation.NSDate;

@class NSString;

NS_ASSUME_NONNULL_BEGIN

@interface ODOFloatingDate : NSDate
- (instancetype)initWithFloatingXMLString:(NSString *)floatingXMLString NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDate:(NSDate *)date;
- (NSDate *)initWithXMLString:(NSString *)xmlString; // Can return a non-floating date
@end

@interface NSDate (XMLDataExtensions)
@property (nonatomic, readonly) BOOL isFloating;
@property (nonatomic, readonly) NSDate *floatingDate;
@property (nonatomic, readonly) NSDate *fixedDate;
@end

NS_ASSUME_NONNULL_END
