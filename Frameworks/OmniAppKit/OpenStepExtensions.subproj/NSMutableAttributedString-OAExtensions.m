// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSMutableAttributedString-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");
#define CELL_PADDING 4.0

@implementation NSMutableAttributedString (OAExtensions)

- (void)setTableCellParagraphStyle:(NSTextTable *)table row:(NSInteger)row column:(NSInteger)column width:(CGFloat)width padding:(CGFloat)padding
{
    NSTextTableBlock *block = [[NSTextTableBlock alloc] initWithTable:table startingRow:row rowSpan:1 startingColumn:column columnSpan:1];
    if (width > 0)
        [block setValue:width type:NSTextBlockAbsoluteValueType forDimension:NSTextBlockWidth];
    if (padding > 0)
        [block setWidth:padding type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding edge:NSMaxXEdge];

    NSRange styleRange = NSMakeRange(0, [self length]);
    NSParagraphStyle *currentParagraphStyle  = [self attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:&styleRange];
    NSMutableParagraphStyle *paragraphStyle = currentParagraphStyle != nil ? [currentParagraphStyle mutableCopy] : [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [paragraphStyle setTextBlocks:[NSArray arrayWithObjects:block, nil]];
    [block release];

    [self addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, [self length])];
    [paragraphStyle release];
}

+ (NSMutableAttributedString *)tableFromDict:(NSDictionary *)dict keyAttributes:(NSDictionary *)keyAttributes valueAttributes:(NSDictionary *)valueAttributes keySeparatorString:(NSString *)separator indent:(BOOL)flag
{
    NSMutableAttributedString *tableString = [[NSMutableAttributedString alloc] init];
    NSMutableArray *attKeys = [NSMutableArray array];
    NSTextTable *table = [[NSTextTable alloc] init];
    [table setNumberOfColumns:3];
    NSArray *keys = [[dict allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSInteger row = 0;
    CGFloat maxKeyWidth = 0;
    NSInteger i, count = [keys count];
    for (i = 0; i < count; i++) {
        id key = [keys objectAtIndex:i];
        NSMutableAttributedString *cellString = [key isKindOfClass:[NSAttributedString class]] ? [[NSMutableAttributedString alloc] initWithAttributedString:key] : [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@%@", key, separator] attributes:keyAttributes];
        if (![[cellString string] hasSuffix:@"\n"])
            [[cellString mutableString] appendString:@"\n"];
        CGFloat width = NSWidth([cellString boundingRectWithSize:(NSSize){FLT_MAX, FLT_MAX} options:NSStringDrawingUsesLineFragmentOrigin]);
        if (width > maxKeyWidth)
            maxKeyWidth = width;
        [attKeys addObject:cellString];
        [cellString release];
    }
    NSInteger startColumn = flag ? 2 : 1;
    for (i = 0; i < count; i++) {
        NSString *key = [keys objectAtIndex:i];
        NSMutableAttributedString *attributedKey =  [attKeys objectAtIndex:row];
        id value = [dict objectForKey:key];
        NSMutableAttributedString *attributedValue = [value isKindOfClass:[NSAttributedString class]] ? [[NSMutableAttributedString alloc] initWithAttributedString:value] : [[NSMutableAttributedString alloc] initWithString:value attributes:valueAttributes];
        if (![[attributedValue string] hasSuffix:@"\n"])
            [[attributedValue mutableString] appendString:@"\n"];
        row++;
        if (flag) {
            NSMutableAttributedString *attributedIndent =  [[NSMutableAttributedString alloc] initWithString:@"\n" attributes:nil];
            [attributedIndent setTableCellParagraphStyle:table row:row column:1 width:16.0 padding:0];
            [tableString appendAttributedString:attributedIndent];
            [attributedIndent release];
        }
        [attributedKey setTableCellParagraphStyle:table row:row column:startColumn width:maxKeyWidth padding:CELL_PADDING];
        [tableString appendAttributedString:attributedKey];
        [attributedValue setTableCellParagraphStyle:table row:row column:startColumn+1 width:0 padding:0];
        [tableString appendAttributedString:attributedValue];
        [attributedValue release];
    }
    [table release];
    return [tableString autorelease];
}

+ (NSMutableAttributedString *)tableFromDict:(NSDictionary *)dict keyAttributes:(NSDictionary *)keyAttributes valueAttributes:(NSDictionary *)valueAttributes indent:(BOOL)flag
{
    return [self tableFromDict:dict keyAttributes:keyAttributes valueAttributes:valueAttributes keySeparatorString:@":" indent:flag];
}

@end
