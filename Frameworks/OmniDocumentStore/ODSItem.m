// Copyright 2010-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSItem.h>

#import <Foundation/NSDateFormatter.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSFolderItem.h>

#import "ODSItem-Internal.h"
#import <OmniDocumentStore/ODSScope-Subclass.h> // For our scopeInfo property.

RCS_ID("$Id$");

NSString * const ODSItemNameBinding = @"name";
NSString * const ODSItemUserModificationDateBinding = @"userModificationDate";
NSString * const ODSItemSelectedBinding = @"selected";
NSString * const ODSItemScopeBinding = @"scope";

NSString * const ODSItemHasDownloadQueuedBinding = @"hasDownloadQueued";
NSString * const ODSItemIsDownloadedBinding = @"isDownloaded";
NSString * const ODSItemIsDownloadingBinding = @"isDownloading";
NSString * const ODSItemIsUploadedBinding = @"isUploaded";
NSString * const ODSItemIsUploadingBinding = @"isUploading";
NSString * const ODSItemTotalSizeBinding = @"totalSize";
NSString * const ODSItemDownloadedSizeBinding = @"downloadedSize";
NSString * const ODSItemUploadedSizeBinding = @"uploadedSize";
NSString * const ODSItemPercentDownloadedBinding = @"percentDownloaded";
NSString * const ODSItemPercentUploadedBinding = @"percentUploaded";

@implementation ODSItem

static NSCalendar *CurrentCalendar = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    // Calling this on iOS can be very slow (possibly if no one is holding onto it). It should auto-track changes anyway, so we'll hold onto it.
    CurrentCalendar = [NSCalendar currentCalendar];
}

static NSDate *_day(NSDate *date)
{
    NSDateComponents *components = [CurrentCalendar components:NSCalendarUnitYear|NSCalendarUnitMonth |NSCalendarUnitDay fromDate:date];
    return [CurrentCalendar dateFromComponents:components];
}

static NSDate *_dayOffset(NSDate *date, NSInteger offset)
{
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setDay:offset];
    NSDate *result = [CurrentCalendar dateByAddingComponents:components toDate:date options:0];
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
        NSString *dayFormat = NSLocalizedStringWithDefaultValue(@"Today, %@ <day name>", @"OmniDocumentStore", OMNI_BUNDLE, @"Today, %@", @"time display format for today");
        NSString *timePart = [timeFormatter stringFromDate:date];
        return [NSString stringWithFormat:dayFormat, timePart];
    } else if ([day isEqualToDate:yesterday]) {
        NSString *dayFormat = NSLocalizedStringWithDefaultValue(@"Yesterday, %@ <day name>", @"OmniDocumentStore", OMNI_BUNDLE, @"Yesterday, %@", @"time display format for yesterday");
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

- initWithScope:(ODSScope *)scope;
{
    OBPRECONDITION(scope);
    OBPRECONDITION(scope.documentStore);
    OBPRECONDITION([self conformsToProtocol:@protocol(ODSItem)]);
    
    if (!(self = [super init]))
        return nil;

    _weak_scope = scope;

    return self;
}

- (BOOL)isValid;
{
    return _weak_scope != nil;
}

@synthesize scope = _weak_scope;

- (ODSScope *)scope;
{
    OBPRECONDITION(_weak_scope, "Don't call this after -_invalidate");
    return _weak_scope;
}

@synthesize parentFolder = _weak_parentFolder;
- (ODSFolderItem *)parentFolder;
{
    OBPRECONDITION(_weak_scope, "Don't call this after -_invalidate");
    
    ODSFolderItem *parentFolder = _weak_parentFolder;
    OBASSERT(parentFolder || (id)self == _weak_scope.rootFolder);
    return parentFolder;
}

- (NSUInteger)depth;
{
    ODSFolderItem *parentFolder = _weak_parentFolder;
    if (parentFolder == nil)
        return 0; // We are the root
    return 1 + parentFolder.depth;
}

+ (NSSet *)keyPathsForValuesAffectingPercentDownloaded;
{
    return [NSSet setWithObjects:ODSItemDownloadedSizeBinding, ODSItemTotalSizeBinding, nil];
}
- (double)percentDownloaded;
{
    uint64_t totalSize = self.totalSize;
    if (totalSize == 0)
        return 0;
    uint64_t downloadedSize = self.downloadedSize;
    if (downloadedSize == 0)
        return 1;
    return (double)downloadedSize / (double)totalSize;
}
+ (NSSet *)keyPathsForValuesAffectingPercentUploaded;
{
    return [NSSet setWithObjects:ODSItemUploadedSizeBinding, ODSItemTotalSizeBinding, nil];
}
- (double)percentUploaded;
{
    uint64_t totalSize = self.totalSize;
    if (totalSize == 0)
        return 0;
    uint64_t uploadedSize = self.uploadedSize;
    if (uploadedSize == 0)
        return 1;
    return (double)uploadedSize / (double)totalSize;
}

#pragma mark - NSCopying

// So we can be a dictionary key
- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

#pragma mark - Internal

- (void)_invalidate;
{
    // If we are getting called due to our scope being deallocated, this will already be cleared. Weak pointers to an object get cleared before the object's -dealloc is run.
    _weak_scope = nil;
    _weak_parentFolder = nil;
}

- (void)_setParentFolder:(ODSFolderItem *)parentFolder;
{
    OBPRECONDITION(parentFolder, "The root folder's parent should never change");
    _weak_parentFolder = parentFolder;
}

- (void)_addMotions:(NSMutableArray *)motions toParentFolderURL:(NSURL *)destinationFolderURL isTopLevel:(BOOL)isTopLevel usedFolderNames:(NSMutableSet *)usedFolderNames ignoringFileItems:(NSSet *)ignoredFileItems;
{
    OBRequestConcreteImplementation(self, _cmd);
}

@end
