// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFEnrichedTextReader.h>

#import <OmniFoundation/OFByteSet.h>
#import <OmniFoundation/OFDataCursor.h>
#import <OmniFoundation/OFImplementationHolder.h>
#import <OmniFoundation/OFRTFGenerator.h>
#import <OmniFoundation/NSObject-OFExtensions.h>

RCS_ID("$Id$")

@interface OFEnrichedTextReader (Private)
+ (void)registerSelector:(SEL)aSelector forTag:(NSString *)tagName;
- (NSString *)processContentForTag:(NSString *)tag;
- (NSString *)processNoOpTag:(NSString *)tag;
- (NSString *)processTag:(NSString *)tag;
- (NSString *)processUNKNOWNTag:(NSString *)tag;
@end

@implementation OFEnrichedTextReader

static NSMutableDictionary *tagImplementations;
static OFByteSet *literalTerminatorSet, *tagTerminatorSet;

+ (void)initialize;
{
    OBINITIALIZE;

    tagImplementations = [[NSMutableDictionary alloc] init];
    literalTerminatorSet = [[OFByteSet alloc] init];
    [literalTerminatorSet addByte:'<'];
    [literalTerminatorSet addByte:'\n'];
    tagTerminatorSet = [[OFByteSet alloc] init];
    [tagTerminatorSet addByte:'>'];
    [tagTerminatorSet addByte:'<'];
    [tagTerminatorSet addByte:'\n'];

    [self registerSelector:@selector(processCommentTag:) forTag:@"comment"];
    [self registerSelector:@selector(processNoFillTag:) forTag:@"nofill"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"no-op"];
    [self registerSelector:@selector(processParagraphTag:) forTag:@"paragraph"];

    [self registerSelector:@selector(processBoldTag:) forTag:@"bold"];
    [self registerSelector:@selector(processItalicTag:) forTag:@"italic"];
    [self registerSelector:@selector(processBiggerTag:) forTag:@"bigger"];
    [self registerSelector:@selector(processSmallerTag:) forTag:@"smaller"];

    [self registerSelector:@selector(processLtTag:) forTag:@"lt"];
    [self registerSelector:@selector(processNlTag:) forTag:@"nl"];
    [self registerSelector:@selector(processNpTag:) forTag:@"np"];

    [self registerSelector:@selector(processNoOpTag:) forTag:@"fixed"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"underline"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"center"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"flushleft"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"flushright"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"indent"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"indentright"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"outdent"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"outdentright"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"samepage"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"subscript"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"superscript"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"heading"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"footing"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"excerpt"];
    [self registerSelector:@selector(processNoOpTag:) forTag:@"signature"];
}

+ (NSData *)rtfDataFromEnrichedTextCursor:(OFDataCursor *)aCursor;
{
    OFEnrichedTextReader *reader;
    NSData *rtfData;
    
    reader = [[self alloc] initWithDataCursor:aCursor];
    rtfData = [[reader rtfGenerator] rtfData];
    [reader release];
    return rtfData;
}

// Init and dealloc

- initWithDataCursor:(OFDataCursor *)aCursor;
{
    if (![super init])
	return nil;

    cursor = [aCursor retain];
    rtfGenerator = [[OFRTFGenerator alloc] init];
    noFill = NO;
    [rtfGenerator setFontSize:12];
    [self processContentForTag:nil];

    return self;
}

- (void)dealloc;
{
    [cursor release];
    [rtfGenerator release];
    [super dealloc];
}

// API

- (OFRTFGenerator *)rtfGenerator;
{
    return rtfGenerator;
}

@end


@implementation OFEnrichedTextReader (Private)

+ (void)registerSelector:(SEL)aSelector forTag:(NSString *)tagName;
{
    OFImplementationHolder *holder;

    holder = [[OFImplementationHolder alloc] initWithSelector:aSelector];
    [tagImplementations setObject:holder forKey:tagName];
    [holder release];
}

- (NSString *)processContentForTag:(NSString *)tag;
{
    NSString *openTag, *closeTag;
    unsigned int startOffset;

    while ([cursor hasMoreData]) {
        switch ([cursor peekByte]) {
            case '<':
                [cursor skipByte];
                startOffset = [cursor currentOffset];
                if ([cursor peekByte] == '/') {
                    [cursor skipByte];
                    closeTag = [[cursor readStringUpToByteInSet:tagTerminatorSet] lowercaseString];
                    if (![cursor hasMoreData] || [cursor peekByte] != '>') {
                        [cursor seekToOffset:startOffset fromPosition:OFDataCursorSeekFromStart];
                        rtfAppendUnprocessedCharacter(rtfGenerator, '<');
                        break;
                    }
                    [cursor skipByte];
                    return [closeTag isEqualToString:tag] ? nil : closeTag;
                } else {
                    openTag = [cursor readStringUpToByteInSet:tagTerminatorSet];
                    if (![cursor hasMoreData] || [cursor peekByte] != '>') {
                        [cursor seekToOffset:startOffset fromPosition:OFDataCursorSeekFromStart];
                        rtfAppendUnprocessedCharacter(rtfGenerator, '<');
                        break;
                    }
                    [cursor skipByte];
                    closeTag = [self processTag:openTag];
                    if (closeTag)
                        return [closeTag isEqualToString:tag] ? nil : closeTag;
                }
                break;
            case '\n':
                if (!noFill)
                    [cursor skipByte];
                while ([cursor hasMoreData] && [cursor peekByte] == '\n') {
                    [cursor skipByte];
                    rtfAppendUnprocessedCharacter(rtfGenerator, '\n');
                }
                    break;
            default:
                [rtfGenerator appendString:[cursor readStringUpToByteInSet:literalTerminatorSet]];
                break;
        }
    }
    return nil;
}

- (NSString *)processNoOpTag:(NSString *)tag;
{
    NSString *endTag;

    endTag = [self processContentForTag:tag];
    return endTag;
}

- (NSString *)processTag:(NSString *)tag;
{
    OFImplementationHolder *holder;
    NSString *lowercaseTag;

    lowercaseTag = [tag lowercaseString];
    holder = [tagImplementations objectForKey:lowercaseTag];
    if (holder)
	return [holder returnObjectOnObject:self withObject:lowercaseTag];
    else
	return [self processUNKNOWNTag:tag];
}

- (NSString *)processUNKNOWNTag:(NSString *)tag;
{
    rtfAppendUnprocessedCharacter(rtfGenerator, '<');
    [rtfGenerator appendString:tag];
    rtfAppendUnprocessedCharacter(rtfGenerator, '>');
    return nil;
}

@end

@interface OFEnrichedTextReader (Tags)
- (NSString *)processCommentTag:(NSString *)tag;
- (NSString *)processNoFillTag:(NSString *)tag;
- (NSString *)processParagraphTag:(NSString *)tag;
- (NSString *)processBoldTag:(NSString *)tag;
- (NSString *)processItalicTag:(NSString *)tag;
- (NSString *)processBiggerTag:(NSString *)tag;
- (NSString *)processSmallerTag:(NSString *)tag;
- (NSString *)processLtTag:(NSString *)tag;
- (NSString *)processNlTag:(NSString *)tag;
- (NSString *)processNpTag:(NSString *)tag;
@end

@implementation OFEnrichedTextReader (Tags)

- (NSString *)processCommentTag:(NSString *)tag;
{
    NSString *endTag;
    OFRTFGenerator *suspendedRTFGenerator;

    suspendedRTFGenerator = rtfGenerator;
    rtfGenerator = [[OFRTFGenerator alloc] init];
    endTag = [self processContentForTag:tag];
    [rtfGenerator release];
    rtfGenerator = suspendedRTFGenerator;
    return endTag;
}

- (NSString *)processNoFillTag:(NSString *)tag;
{
    NSString *endTag;
    BOOL wasNoFill;

    wasNoFill = noFill;
    noFill = YES;
    endTag = [self processContentForTag:tag];
    noFill = wasNoFill;
    return endTag;
}

- (NSString *)processParagraphTag:(NSString *)tag;
{
    NSString *endTag;

    endTag = [self processContentForTag:tag];
    rtfAppendUnprocessedCharacter(rtfGenerator, '\n');
    rtfAppendUnprocessedCharacter(rtfGenerator, '\n');
    while ([cursor hasMoreData] && [cursor peekByte] == '\n')
	[cursor skipByte];
    return endTag;
}

- (NSString *)processBoldTag:(NSString *)tag;
{
    NSString *endTag;
    OFRTFState oldState;

    oldState = rtfGenerator->wantState;
    rtfGenerator->wantState.flags.bold = YES;
    rtfGenerator->hasUnemittedState = YES;
    [rtfGenerator emitStateChange];
    endTag = [self processContentForTag:tag];
    rtfGenerator->wantState = oldState;
    rtfGenerator->hasUnemittedState = YES;
    [rtfGenerator emitStateChange];
    return endTag;
}

- (NSString *)processItalicTag:(NSString *)tag;
{
    NSString *endTag;
    OFRTFState oldState;

    oldState = rtfGenerator->wantState;
    rtfGenerator->wantState.flags.italic = YES;
    rtfGenerator->hasUnemittedState = YES;
    [rtfGenerator emitStateChange];
    endTag = [self processContentForTag:tag];
    rtfGenerator->wantState = oldState;
    rtfGenerator->hasUnemittedState = YES;
    [rtfGenerator emitStateChange];
    return endTag;
}

- (NSString *)processBiggerTag:(NSString *)tag;
{
    NSString *endTag;
    OFRTFState oldState;

    oldState = rtfGenerator->wantState;
    rtfGenerator->wantState.fontSize += 2;
    rtfGenerator->hasUnemittedState = YES;
    [rtfGenerator emitStateChange];
    endTag = [self processContentForTag:tag];
    rtfGenerator->wantState = oldState;
    rtfGenerator->hasUnemittedState = YES;
    [rtfGenerator emitStateChange];
    return endTag;
}

- (NSString *)processSmallerTag:(NSString *)tag;
{
    NSString *endTag;
    OFRTFState oldState;

    oldState = rtfGenerator->wantState;
    rtfGenerator->wantState.fontSize -= 2;
    rtfGenerator->hasUnemittedState = YES;
    [rtfGenerator emitStateChange];
    endTag = [self processContentForTag:tag];
    rtfGenerator->wantState = oldState;
    rtfGenerator->hasUnemittedState = YES;
    [rtfGenerator emitStateChange];
    return endTag;
}

- (NSString *)processLtTag:(NSString *)tag;
{
    rtfAppendUnprocessedCharacter(rtfGenerator, '<');
    return nil;
}

- (NSString *)processNlTag:(NSString *)tag;
{
    rtfAppendUnprocessedCharacter(rtfGenerator, '\n');
    return nil;
}

- (NSString *)processNpTag:(NSString *)tag;
{
    [rtfGenerator appendString:NSLocalizedStringFromTableInBundle(@"\n[New Page]\n", @"OmniFoundation", [OFEnrichedTextReader bundle], @"page break placeholder for RTF scanner")];
    return nil;
}

@end
