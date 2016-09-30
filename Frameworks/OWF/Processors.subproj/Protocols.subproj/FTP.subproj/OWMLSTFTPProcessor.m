// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWMLSTFTPProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWContent.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWDataStreamCursor.h>
#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWFileInfo.h>
#import <OWF/OWObjectStream.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$");

/*
    This class is intended to support the MLST/MLSD command as described in
    http://www.ietf.org/internet-drafts/draft-ietf-ftpext-mlst-16.txt
    "Extensions to FTP", a codification of current practice, R.Elz, P.Hethmon, September 2002.
*/

@implementation OWMLSTFTPProcessor

+ (void)didLoad;
{
    [self registerForContentTypeString:@"OWFTPDirectory/MLST" cost:1.0f];
}

// As an OWDataStreamCharacterProcessor subclass we can override this method
- (CFStringEncoding)chooseStringEncoding:(OWDataStreamCursor *)dataCursor content:(OWContent *)sourceContent
{
    return OFDeferredASCIISupersetStringEncoding;
}

// API

+ (NSCalendarDate *)parseDate:(NSString *)date
{
    NSString *fixed, *variable;
    NSCalendarDate *parsed;
    NSRange dotRange;

    dotRange = [date rangeOfString:@"."];
    if (dotRange.length) {
        fixed = [date substringToIndex:dotRange.location];
        variable = [date substringFromIndex:NSMaxRange(dotRange)];
        if ([variable length] < 1)
            variable = nil;
    } else {
        fixed = date;
        variable = nil;
    }
    
    if ([fixed length] != 14)
        return nil;

    parsed = [NSCalendarDate dateWithString:[fixed stringByAppendingString:@" UTC"] calendarFormat:@"%Y%m%d%H%M%S %Z" locale:nil];
    if (parsed == nil)
        return nil;

    if (parsed != nil && variable != nil) {
        NSInteger decimalPlaces = [variable length];

        parsed = [parsed dateByAddingTimeInterval:(NSTimeInterval)(pow(10., - decimalPlaces) * [variable doubleValue])];
    }

    return parsed;
}

- (OWFileInfo *)fileInfoForLine:(NSString *)line;
{
    NSRange spaceSeparator = [line rangeOfString:@" "];
    if (spaceSeparator.length == 0) {
        [NSException raise:@"ListAborted" reason:NSLocalizedStringFromTableInBundle(@"Incorrect response to MLST command", @"OWF", [OWMLSTFTPProcessor bundle], @"ftpsession error - MLST (directory listing) command returned invalid data")];
    }
    NSArray *facts = [[line substringToIndex:spaceSeparator.location] componentsSeparatedByString:@";"];
    NSString *filename = [line substringFromIndex:NSMaxRange(spaceSeparator)];

    /* Ignore entries with zero-length names. */
    if ([filename isEqual:@""])
        return nil;

    NSString *fileTypeName = @"file";
    NSNumber *fileSize = nil;
    NSCalendarDate *modDate = nil;
    NSString *nameCharset = nil;
    BOOL isDir = NO;
    BOOL isLink = NO;

    for (NSString *fact in facts) {
        NSString *factName, *factValue;
        
        NSRange separator = [fact rangeOfString:@"="];
        if (separator.length) {
            factName = [fact substringToIndex:separator.location];
            factValue = [fact substringFromIndex:NSMaxRange(separator)];
        } else {
            factName = fact;
            factValue = nil;
        }

        if ([factName caseInsensitiveCompare:@"type"] == NSOrderedSame) {
            fileTypeName = factValue;
        } else if ([factName caseInsensitiveCompare:@"size"] == NSOrderedSame &&
                   ![NSString isEmptyString:factValue]) {
            fileSize = [NSNumber numberWithLongLong:factValue != nil ? [factValue longLongValue] : 0LL];
        } else if ([factName caseInsensitiveCompare:@"modify"] == NSOrderedSame) {
            modDate = [[self class] parseDate:factValue];
        } else if ([factName caseInsensitiveCompare:@"charset"] == NSOrderedSame) {
            nameCharset = factValue;
        }

        /* Unrecognized fact names are OK. */
        
        /* TODO: Handle the "unique" fact usefully. */
    }

    /* Ignore "." and ".." entries */
    if ([fileTypeName caseInsensitiveCompare:@"cdir"] == NSOrderedSame ||
        [fileTypeName caseInsensitiveCompare:@"pdir"] == NSOrderedSame)
        return nil;
    
    /* Other file types */
    if ([fileTypeName caseInsensitiveCompare:@"file"] == NSOrderedSame) {
        /* Perfectly normal file. */
    } else if ([fileTypeName caseInsensitiveCompare:@"dir"] == NSOrderedSame) {
        isDir = YES;
    } else if ([fileTypeName caseInsensitiveCompare:@"OS.unix=slink"] == NSOrderedSame) {
        /* Supposedly this will never happen, because the FTP server should resolve all symlinks before returning the listing to us. But this is the string the *bsd ftpd would return if it didn't resolve links. */
        isLink = YES;
    } else {
        /* ??? */
        /* TODO: Alter OWFileInfo to be able to represent special files */
    }
    
    /* Reëncode the filename into the specified character set. */
    CFStringEncoding nameEncoding;
    if (nameCharset == nil) {
        /* The spec says that lines with no charset fact are in UTF-8. */
        nameEncoding = kCFStringEncodingUTF8;
    } else if (lastNameCharset != nil && [nameCharset isEqualToString:lastNameCharset]) {
        nameEncoding = lastNameEncoding;
    } else {
        nameEncoding = [OWDataStreamCharacterProcessor stringEncodingForIANACharSetName:nameCharset];
        /* Cache the result of -stringEncodingForIANACharSetName: here ... */
        lastNameCharset = nameCharset;
        lastNameEncoding = nameEncoding;
    }
    NSString *unicodeFilename = [filename stringByApplyingDeferredCFEncoding:nameEncoding];
    
    /* Here's the subtle part. For display, we need to interpret the filename according to its specified encoding, in order to get a valid sequence of characters/glyphs. But in order to retrieve the file later, we'll need to send back the same *sequence of bytes/octets* we got from the server, regardless of what encoding they were in or what transformations we've applied to make them displayable. So the URL we compute for this file needs to be derived from the filename without applying the encoding. */

    /* -encodeURLString:... knows about OF deferred encoding and will correctly represent deferred bytes as hex escapes */
    NSString *urlCodedFilename = [NSString encodeURLString:filename asQuery:NO leaveSlashes:NO leaveColons:NO];
    if (isDir)
        urlCodedFilename = [urlCodedFilename stringByAppendingString:@"/"];
    OWFileInfo *fileInfo = [[OWFileInfo alloc] initWithAddress:[baseAddress addressForRelativeString:urlCodedFilename] size:fileSize isDirectory:isDir isShortcut:isLink lastChangeDate:modDate];
    [fileInfo setName:unicodeFilename];

    return fileInfo;
}

@end

