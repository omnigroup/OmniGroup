// Copyright 1999-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWMacOSPeterLewisFTPProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWFileInfo.h>
#import <OWF/OWObjectStream.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@implementation OWMacOSPeterLewisFTPProcessor

+ (void)didLoad;
{
    [self registerForContentTypeString:@"OWFTPDirectory/MacOS-PeterLewis" cost:1.0f];
}

- (OWFileInfo *)fileInfoForLine:(NSString *)line;
{
    OWFileInfo *fileInfo;
    NSScanner *lineScanner;
    NSString *directoryFlag, *permissions = nil;
    long long int resourceForkSize = 0, dataForkSize = 0, size = 0;
    NSString *month = nil, *day = nil, *timeOrYear = nil;
    NSString *dateString, *name = nil;
    NSCharacterSet *whitespace;
    NSCalendarDate *changeDate;
    NSRange timeSeparatorRange;
    OWAddress *fileAddress;
    BOOL isFolder;

    if (lineNumber == 1 && [line hasPrefix:@"total "]) {
        // On some servers, the first line gives the total size, so we just skip it.
        // TODO: Is this actually true for any PeterLewis FTP servers?
        return nil;
    }

    whitespace = [NSCharacterSet whitespaceCharacterSet];
    lineScanner = [NSScanner scannerWithString:line];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&permissions];
    directoryFlag = [permissions substringToIndex:1];
    permissions = [permissions substringFromIndex:1];

    if ([lineScanner scanString:@"folder" intoString:NULL]) {
        isFolder = YES;
        resourceForkSize = dataForkSize = 0;
        // NB: If isFolder is true, then the "size" field holds the count of items in the folder, not the size of the folder in bytes. We currently have no way of making use of this information. 
    } else {
        isFolder = NO;
        [lineScanner scanLongLong:(long long *)&resourceForkSize];
        [lineScanner scanLongLong:(long long *)&dataForkSize];
    }
    
    [lineScanner scanLongLong:(long long *)&size];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&month];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&day];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&timeOrYear];
    timeSeparatorRange = [timeOrYear rangeOfString:@":"];
    if (timeSeparatorRange.length) {
        NSCalendarDate *now = (NSCalendarDate *)[NSCalendarDate date];
	dateString = [NSString stringWithFormat:@"%@ %@ %@ %ld", month, day, timeOrYear, [now yearOfCommonEra]];
	changeDate = [NSCalendarDate dateWithString:dateString calendarFormat:@"%b %d %H:%M %Y"];
        
        // deal with year boundaries
        if ([changeDate monthOfYear] > [now monthOfYear])
            changeDate = [changeDate dateByAddingYears:-1 months:0 days:0 hours:0 minutes:0 seconds:0];
    } else {
	dateString = [NSString stringWithFormat:@"%@ %@ %@", month, day, timeOrYear];
	changeDate = [NSCalendarDate dateWithString:dateString calendarFormat:@"%b %d %Y"];
    }
    [lineScanner setCharactersToBeSkipped:nil];
    [lineScanner scanCharactersFromSet:whitespace intoString:NULL];
    [lineScanner scanUpToString:@" -> " intoString:&name];

    if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
	return nil;
    }

    fileAddress = [baseAddress addressForRelativeString:[NSString encodeURLString:name asQuery:NO leaveSlashes:NO leaveColons:NO]];
    fileInfo = [[OWFileInfo alloc] initWithAddress:fileAddress size:isFolder ? nil : [NSNumber numberWithUnsignedLong:size] isDirectory:(isFolder || [directoryFlag isEqualToString:@"d"]) isShortcut:[directoryFlag isEqualToString:@"l"] lastChangeDate:changeDate];

    return fileInfo;
}

@end
