// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentStoreItem.h>

#import "OUIDocumentStoreItem-Internal.h"

RCS_ID("$Id$");

NSString * const OUIDocumentStoreItemNameBinding = @"name";
NSString * const OUIDocumentStoreItemDateBinding = @"date";

NSString * const OUIDocumentStoreItemReadyBinding = @"ready";

NSString * const OUIDocumentStoreItemHasUnresolvedConflictsBinding = @"hasUnresolvedConflicts";
NSString * const OUIDocumentStoreItemIsDownloadedBinding = @"isDownloaded";
NSString * const OUIDocumentStoreItemIsDownloadingBinding = @"isDownloading";
NSString * const OUIDocumentStoreItemIsUploadedBinding = @"isUploaded";
NSString * const OUIDocumentStoreItemIsUploadingBinding = @"isUploading";
NSString * const OUIDocumentStoreItemPercentDownloadedBinding = @"percentDownloaded";
NSString * const OUIDocumentStoreItemPercentUploadedBinding = @"percentUploaded";

@implementation OUIDocumentStoreItem
{
    OUIDocumentStore *_nonretained_documentStore;
    CGRect _frame;
    BOOL _layoutShouldAdvance;
}

static NSDate *_day(NSDate *date)
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit fromDate:date];
    return [calendar dateFromComponents:components];
}

static NSDate *_dayOffset(NSDate *date, NSInteger offset)
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setDay:offset];
    NSDate *result = [calendar dateByAddingComponents:components toDate:date options:0];
    [components release];
    return result;
}

+ (NSString *)displayStringForDate:(NSDate *)date;
{
    if (!date)
        return @"";
    
    static NSDateFormatter *dateFormatter = nil;
    static NSDateFormatter *timeFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterFullStyle];
        [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
        
        timeFormatter = [[NSDateFormatter alloc] init];
        [timeFormatter setDateStyle:NSDateFormatterNoStyle];
        [timeFormatter setTimeStyle:NSDateFormatterShortStyle];
    });
    
    
    NSDate *today = _day([NSDate date]);
    NSDate *yesterday = _dayOffset(today, -1);
    
    NSDate *day = _day(date);
    
    //NSDate *day = _day([NSDate dateWithTimeIntervalSinceNow:-1000000]);
    //NSDate *day = _day([NSDate dateWithTimeIntervalSinceNow:-86400]);
    //NSDate *day = today;
    
    if ([day isEqualToDate:today]) {
        NSString *dayFormat = NSLocalizedStringWithDefaultValue(@"Today, %@ <day name>", @"OmniUI", OMNI_BUNDLE, @"Today, %@", @"time display format for today");
        NSString *timePart = [timeFormatter stringFromDate:date];
        return [NSString stringWithFormat:dayFormat, timePart];
    } else if ([day isEqualToDate:yesterday]) {
        NSString *dayFormat = NSLocalizedStringWithDefaultValue(@"Yesterday, %@ <day name>", @"OmniUI", OMNI_BUNDLE, @"Yesterday, %@", @"time display format for yesterday");
        NSString *timePart = [timeFormatter stringFromDate:date];
        return [NSString stringWithFormat:dayFormat, timePart];
    } else {
        return [dateFormatter stringFromDate:day];
    }    
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithDocumentStore:(OUIDocumentStore *)documentStore;
{
    OBPRECONDITION(documentStore);
    OBPRECONDITION([self conformsToProtocol:@protocol(OUIDocumentStoreItem)]);
    
    if (!(self = [super init]))
        return nil;

    _nonretained_documentStore = documentStore;
    _frame = CGRectMake(0, 0, 400, 400);
    _layoutShouldAdvance = YES;
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_nonretained_documentStore == nil); // Document store should call -invalidate
    
    [super dealloc];
}

- (OUIDocumentStore *)documentStore;
{
    OBPRECONDITION(_nonretained_documentStore); // Don't call this after -_invalidate
    return _nonretained_documentStore;
}

@synthesize frame = _frame;
- (void)setFrame:(CGRect)frame;
{
    OBPRECONDITION(CGRectEqualToRect(frame, CGRectIntegral(frame)));
    _frame = frame;
}

@synthesize layoutShouldAdvance = _layoutShouldAdvance;

#pragma mark -
#pragma mark Internal

- (void)_invalidate;
{
    _nonretained_documentStore = nil;
}

@end
