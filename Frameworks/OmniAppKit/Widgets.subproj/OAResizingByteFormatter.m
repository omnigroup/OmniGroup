// Copyright 2000-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAResizingByteFormatter.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@implementation OAResizingByteFormatter

static NSArray *formatters = nil;

static void _addFormatter(NSMutableArray *results, NSString *formatString)
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setFormat:formatString];
    [results addObject:formatter];
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSBundle *bundle = [OAResizingByteFormatter bundle];
    NSMutableArray *results = [[NSMutableArray alloc] init];
    _addFormatter(results, NSLocalizedStringFromTableInBundle(@"#,##0", @"OmniAppKit", bundle, "resizing bytes formatter bytes format"));
    _addFormatter(results, NSLocalizedStringFromTableInBundle(@"#,##0.0 kB", @"OmniAppKit", bundle, "resizing bytes formatter kilobytes format"));
    _addFormatter(results, NSLocalizedStringFromTableInBundle(@"#,##0.0 MB", @"OmniAppKit", bundle, "resizing bytes formatter megabytes format"));
    _addFormatter(results, NSLocalizedStringFromTableInBundle(@"#,##0.0 GB", @"OmniAppKit", bundle, "resizing bytes formatter gigabytes format"));
    _addFormatter(results, NSLocalizedStringFromTableInBundle(@"#,##0.0 TB", @"OmniAppKit", bundle, "resizing bytes formatter terabytes format"));
    _addFormatter(results, NSLocalizedStringFromTableInBundle(@"#,##0.0 PB", @"OmniAppKit", bundle, "resizing bytes formatter petabytes format"));
    
    formatters = [results copy];
}

- initWithNonretainedTableColumn:(NSTableColumn *)tableColumn;
{
    if (!(self = [super init]))
        return nil;
        
    nonretainedTableColumn = tableColumn;
    return self;
}

// NSFormatter

- (NSString *)stringForObjectValue:(id)obj;
{
    NSString *bytesString = @"";
    NSCell *dataCell = [nonretainedTableColumn dataCell];
    double scaledBytes = [obj doubleValue];
    
    NSUInteger formatterIndex, formatterCount = [formatters count];
    for (formatterIndex = 0; formatterIndex < formatterCount; formatterIndex++) {
        NSNumberFormatter *formatter = [formatters objectAtIndex:formatterIndex];

        if (formatterIndex == 0) {
            // Sadly, you can't include an 'e' in a NSNumberFormatter's format string
            bytesString = [[formatter stringForObjectValue:obj] stringByAppendingString:NSLocalizedStringFromTableInBundle(@" bytes", @"OmniAppKit", [OAResizingByteFormatter bundle], "resizing byte formatter - this word is separate because of a bug in NSNumberFormatter")];
        } else {
            bytesString = [formatter stringForObjectValue:[NSNumber numberWithDouble:scaledBytes]];
        }
        
        if (scaledBytes < (1024.0 / 10.0)) // if our new value < (1024 / 10), we aren't going to get any skinnier
            return bytesString;
        
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[dataCell font] forKey:NSFontAttributeName];
        NSSize size = [bytesString sizeWithAttributes:attributes];
        
        if (size.width + 5 <= NSWidth([dataCell titleRectForBounds:NSMakeRect(0, 0, [nonretainedTableColumn width], 30)]))
            return bytesString;
            
        scaledBytes /= 1024.0;
    }
    
    return bytesString;
}

- (NSAttributedString *)attributedStringForObjectValue:(id)obj withDefaultAttributes:(NSDictionary *)attrs;
{
    return [[NSAttributedString alloc] initWithString:[self stringForObjectValue:obj] attributes:attrs];
}


- (NSString *)editingStringForObjectValue:(id)obj;
{
    return [obj stringValue];
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string errorDescription:(out NSString **)error;
{
    *obj = [NSNumber numberWithInt:[string intValue]];
    return YES;
}

//- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;


@end
