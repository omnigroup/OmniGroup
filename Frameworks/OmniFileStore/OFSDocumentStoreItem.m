// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentStoreItem.h>

#import <OmniFileStore/OFSFeatures.h>

#if OFS_DOCUMENT_STORE_SUPPORTED

#import <Foundation/NSDateFormatter.h>

#import "OFSDocumentStoreItem-Internal.h"

RCS_ID("$Id$");

NSString * const OFSDocumentStoreItemNameBinding = @"name";
NSString * const OFSDocumentStoreItemDateBinding = @"date";

NSString * const OFSDocumentStoreItemReadyBinding = @"ready";

NSString * const OFSDocumentStoreItemHasUnresolvedConflictsBinding = @"hasUnresolvedConflicts";
NSString * const OFSDocumentStoreItemIsDownloadedBinding = @"isDownloaded";
NSString * const OFSDocumentStoreItemIsDownloadingBinding = @"isDownloading";
NSString * const OFSDocumentStoreItemIsUploadedBinding = @"isUploaded";
NSString * const OFSDocumentStoreItemIsUploadingBinding = @"isUploading";
NSString * const OFSDocumentStoreItemPercentDownloadedBinding = @"percentDownloaded";
NSString * const OFSDocumentStoreItemPercentUploadedBinding = @"percentUploaded";

@implementation OFSDocumentStoreItem
{
    OFSDocumentStore *_nonretained_documentStore;
}

static NSCalendar *CurrentCalendar = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    // Calling this on iOS can be very slow (possibly if no one is holding onto it). It should auto-track changes anyway, so we'll hold onto it.
    CurrentCalendar = [[NSCalendar currentCalendar] retain];
}

static NSDate *_day(NSDate *date)
{
    NSDateComponents *components = [CurrentCalendar components:NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit fromDate:date];
    return [CurrentCalendar dateFromComponents:components];
}

static NSDate *_dayOffset(NSDate *date, NSInteger offset)
{
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setDay:offset];
    NSDate *result = [CurrentCalendar dateByAddingComponents:components toDate:date options:0];
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
        NSString *dayFormat = NSLocalizedStringWithDefaultValue(@"Today, %@ <day name>", @"OmniFileStore", OMNI_BUNDLE, @"Today, %@", @"time display format for today");
        NSString *timePart = [timeFormatter stringFromDate:date];
        return [NSString stringWithFormat:dayFormat, timePart];
    } else if ([day isEqualToDate:yesterday]) {
        NSString *dayFormat = NSLocalizedStringWithDefaultValue(@"Yesterday, %@ <day name>", @"OmniFileStore", OMNI_BUNDLE, @"Yesterday, %@", @"time display format for yesterday");
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

- initWithDocumentStore:(OFSDocumentStore *)documentStore;
{
    OBPRECONDITION(documentStore);
    OBPRECONDITION([self conformsToProtocol:@protocol(OFSDocumentStoreItem)]);
    
    if (!(self = [super init]))
        return nil;

    _nonretained_documentStore = documentStore;
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_nonretained_documentStore == nil); // Document store should call -invalidate
    
    [super dealloc];
}

- (OFSDocumentStore *)documentStore;
{
    OBPRECONDITION(_nonretained_documentStore); // Don't call this after -_invalidate
    return _nonretained_documentStore;
}

#pragma mark -
#pragma mark Internal

- (BOOL)_hasBeenInvalidated;
{
    return _nonretained_documentStore == nil;
}

- (void)_invalidate;
{
    OBPRECONDITION(_nonretained_documentStore != nil); // Shouldn't be keeping references to previously invalidated items, so double invalidation signals a problem
    
    _nonretained_documentStore = nil;
}

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
