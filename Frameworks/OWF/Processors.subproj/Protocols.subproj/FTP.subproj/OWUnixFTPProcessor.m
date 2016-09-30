// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWUnixFTPProcessor.h>

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

@implementation OWUnixFTPProcessor

+ (void)didLoad;
{
    [self registerForContentTypeString:@"OWFTPDirectory/UNIX" cost:1.0f];
    [self registerForContentTypeString:@"OWFTPDirectory/RHAPSODY" cost:1.0f];
    [self registerForContentTypeString:@"OWFTPDirectory/unknown" cost:10.0f];
    [self registerForContentTypeString:@"OWFTPDirectory/Windows_NT" cost:3.0f];
    [self registerForContentTypeString:@"OWFTPDirectory/MacOS-MachTen" cost:2.0f];
}

- (OWFileInfo *)fileInfoForLine:(NSString *)line;
{
    OWFileInfo *fileInfo;
    NSScanner *lineScanner;
    NSString *directoryFlag, *permissions = nil;
    int linkCount = 0;
    NSString *owner = nil, *group = nil;
    long long int size = 0;
    NSString *month = nil, *day = nil, *timeOrYear = nil;
    NSString *dateString, *name = nil;
    NSCharacterSet *whitespace;
    NSCalendarDate *changeDate;
    NSRange range;

    if (lineNumber == 1 && [line hasPrefix:@"total "]) {
        // On some servers, the first line gives the total size, so we just skip it.
        return nil;
    }

    whitespace = [NSCharacterSet whitespaceCharacterSet];
    lineScanner = [NSScanner scannerWithString:line];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&permissions];
    directoryFlag = [permissions substringToIndex:1];
    permissions = [permissions substringFromIndex:1];
    [lineScanner scanInt:(int *)&linkCount];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&owner];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&group];
    if (![lineScanner scanLongLong:(long long *)&size]) {
	size = [group intValue];
	group = nil;
    }
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&month];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&day];
    [lineScanner scanUpToCharactersFromSet:whitespace intoString:&timeOrYear];
    range = [timeOrYear rangeOfString:@":"];
    if (range.length) {
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
        // Skip the current and parent directories, since we know about them implicitly
        return nil;
    }
    
    // TODO: if 'name' is empty or nil, we'll end up putting a bogus link into the directory listing

    fileInfo = [[OWFileInfo alloc] initWithAddress:[baseAddress addressForRelativeString:[NSString encodeURLString:name asQuery:NO leaveSlashes:NO leaveColons:NO]] size:[NSNumber numberWithUnsignedLong:size] isDirectory:[directoryFlag isEqualToString:@"d"] isShortcut:[directoryFlag isEqualToString:@"l"] lastChangeDate:changeDate];

    return fileInfo;
}

@end
