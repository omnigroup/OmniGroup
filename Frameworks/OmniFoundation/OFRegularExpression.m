// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRegularExpression.h>

#import <OmniFoundation/OFRegularExpressionMatch.h>
#import <OmniFoundation/OFStringScanner.h>

RCS_ID("$Id$")

#define MAX_SUBEXPRESSION_NESTING 10

typedef struct {
    unichar *scanningString;
    ExpressionState *writePtr;
    unichar *stringPtr, *stringPtrBase;
    unsigned int writeLength;
    unsigned int stringLength;
    BOOL wroteArgument;
    int subexpressionNesting[MAX_SUBEXPRESSION_NESTING];
    int subexpressionNestingCount;
} CompileStatus;

static ExpressionState fakeState;

#define STRING_PARAMETER(state)		(stringBuffer + state[1].string)
#define STATE_PARAMETER(state)		(state+1)

static inline ExpressionState *nextState(ExpressionState *current)
{
    if (!current || !current->nextState)
        return NULL;
    return current->opCode == OpBack ? current - current->nextState : current + current->nextState;
}

static inline ExpressionState *writeState(CompileStatus *compile, ExpressionOpCode opCode)
{
    ExpressionState *result = compile->writePtr;

    if (result) {
        result->opCode = opCode;
        result->argumentNumber = 0;
        result->nextState = 0;
        compile->writePtr++;
    } else {
        result = &fakeState;
        compile->writeLength++;
    }
    compile->wroteArgument = NO;
    return result;
}

static inline void insertState(CompileStatus *compile, ExpressionOpCode opCode, ExpressionState *before)
{
    if (!compile->writePtr) {
        compile->writeLength++;
    } else {
        ExpressionState *ptr = compile->writePtr;
        
        while (ptr > before) {
            *ptr = *(ptr-1);
            ptr--;
        }
        
        before->opCode = opCode;
        before->nextState = 0;
        before->argumentNumber = 0;
        compile->writePtr++;
    }
}

static inline void writeCharacter(CompileStatus *compile, unichar character)
{
    if (compile->stringPtr) {
        if (!compile->wroteArgument) {
            compile->writePtr->string = compile->stringPtr - compile->stringPtrBase;
            compile->writePtr++;
            compile->wroteArgument = YES;
        }
        *compile->stringPtr++ = character;
    } else {
        compile->stringLength++;
        if (!compile->wroteArgument) {
            compile->writeLength++;
            compile->wroteArgument = YES;
        }
    }
}

static inline void writeRange(CompileStatus * status, unichar start, unichar end)
{
    while (start <= end)
        writeCharacter(status, start++);
}

static inline void unwriteCharacter(CompileStatus *compile)
{
    if (compile->stringPtr)
        compile->stringPtr--;
    else
        compile->stringLength--;
}

static inline void setNextPointer(ExpressionState *scan, const ExpressionState *value)
{
    ExpressionState *temp;
    
    if (scan == &fakeState)
        return;
    
    while ((temp = nextState(scan)))
        scan = temp;
    
    if (scan->opCode == OpBack)
        scan->nextState = scan - value;
    else
        scan->nextState = value - scan;
}

static inline void setNextPointerOnArgument(ExpressionState *scan, const ExpressionState *value)
{
    if (!scan || scan == &fakeState || (scan->opCode != OpBranch && scan->opCode != OpReverseBranch))
        return;
    setNextPointer(STATE_PARAMETER(scan), value);
}


static inline unsigned int unicodeStringLength(unichar *string)
{
    unichar *ptr = string;

    while (*ptr)
        ptr++;
    return ptr - string;
}

@interface OFRegularExpression (Compilation)
- (ExpressionState *)compile:(CompileStatus *)status parenthesized:(BOOL)parens flags:(unsigned int *)compileFlags;
- (ExpressionState *)compileBranch:(CompileStatus *)status flags:(unsigned int *)compileFlags;
- (ExpressionState *)compilePiece:(CompileStatus *)status flags:(unsigned int *)compileFlags;
- (ExpressionState *)compileAtom:(CompileStatus *)status flags:(unsigned int *)compileFlags;
- (void)findOptimizations:(unsigned int)compileFlags;
@end

@interface OFRegularExpression (Search)
- (BOOL)findMatch:(OFRegularExpressionMatch *)match withScanner:(OFStringScanner *)scanner;
- (BOOL)tryMatch:(OFRegularExpressionMatch *)match withScanner:(OFStringScanner *)scanner atStartOfLine:(BOOL)beginningOfLine;
- (BOOL)nestedMatch:(OFRegularExpressionMatch *)match inState:(ExpressionState *)state withScanner:(OFStringScanner *)scanner atStartOfLine:(BOOL)beginningOfLine;
- (BOOL)matchNextCharacterInState:(const ExpressionState *)state withScanner:(OFStringScanner *)scanner;
- (unsigned int)repeatedlyMatchState:(const ExpressionState *)state withScanner:(OFStringScanner *)scanner;
@end

@interface OFRegularExpressionMatch (privateUsedByOFRegularExpression)
- initWithExpression:(OFRegularExpression *)expression inScanner:(OFStringScanner *)scanner;
@end

@implementation OFRegularExpression

- initWithCharacters:(unichar *)characters;
{
    unsigned int compileFlags;
    CompileStatus status;
    NSZone *myZone;

    [super init];
    if (!characters || !*characters) {
        [self release];
        return nil;
    }

    status.scanningString = characters;
    status.writePtr = NULL;
    status.stringPtr = status.stringPtrBase = NULL;
    status.writeLength = 0;
    status.stringLength = 0;
    status.wroteArgument = NO;
    status.subexpressionNestingCount = 0;
    [self compile:&status parenthesized:NO flags:&compileFlags];
    if (status.writeLength > (1<<16)) { // expression is too big
        [self release];
        return nil;
    }
    status.scanningString = characters;
    myZone = [self zone];
    program = NSZoneMalloc(myZone, sizeof(ExpressionState) * status.writeLength);
    stringBuffer = NSZoneMalloc(myZone, sizeof(unichar) * (status.stringLength+1)); // +1 because we sometimes write an extra then undo
    subExpressionCount = 0;
    status.writePtr = program;
    status.stringPtr = status.stringPtrBase = stringBuffer;
    if (![self compile:&status parenthesized:NO flags:&compileFlags]) {
        [self release];
        return nil;
    }
    [self findOptimizations:compileFlags];
    return self;
}

- initWithString:(NSString *)string;
{
    unsigned int length = [string length];
    unichar *buffer = alloca(sizeof(unichar) * (length+1));

    patternString = [string copyWithZone:[self zone]];
    
    [string getCharacters:buffer];
    buffer[length] = 0;
    return [self initWithCharacters:buffer];
}

- (void)dealloc;
{
    NSZone *myZone;
    [patternString release];
    myZone = [self zone];
    NSZoneFree(myZone, program);
    NSZoneFree(myZone, stringBuffer);
    [super dealloc];
}

- (unsigned int)subexpressionCount;
{
    return subExpressionCount;
}

- (OFRegularExpressionMatch *)matchInString:(NSString *)string;
{
    return [self matchInString:string range:NSMakeRange(0, [string length])];
}

- (OFRegularExpressionMatch *)matchInString:(NSString *)string range:(NSRange)range;
{
    OFStringScanner *scanner;
    OFRegularExpressionMatch *result;

    scanner = [[OFStringScanner allocWithZone:[self zone]] initWithString:string];
    if (range.location != 0) {
        [scanner setRewindMark]; // -matchInScanner needs to be able to peek back one character to see if the scanner is at the beginning of the line
        [scanner setScanLocation:range.location];
    }
    result = [self matchInScanner:scanner];
    [scanner release];
    
    if (NSMaxRange([result matchRange]) > NSMaxRange(range))
        return nil;
        
    return result;
}

- (OFRegularExpressionMatch *)matchInScanner:(OFStringScanner *)scanner;
{
    OFRegularExpressionMatch *result;

    result = [[OFRegularExpressionMatch allocWithZone:[self zone]] initWithExpression:self inScanner:scanner];
    return [result autorelease];
}


static inline BOOL unicodeSubstring(unichar *substring, unichar *string)
{
    unichar *substringPtr;
    
    while (*string) {
        if (*string++ == *substring) {
            unichar *stringPtr = string;

            substringPtr = substring + 1;
            while(*stringPtr && *stringPtr == *substringPtr)
                stringPtr++, substringPtr++;
            if (!*substringPtr)
                return YES;
        }
    }
    return NO;
}

#define LARGE_STRING_LENGTH 8192

- (BOOL)hasMatchInString:(NSString *)string;
{
    unsigned int length;
    BOOL isLarge;
    unichar *buffer;
    OFStringScanner *scanner;
    BOOL result;

    /* get the string characters into a buffer */
    length = [string length];
    isLarge = (length > LARGE_STRING_LENGTH);
    if (isLarge)
        buffer = NSZoneMalloc(NULL, sizeof(unichar) * (length+1));
    else
        buffer = alloca(sizeof(unichar) * (length+1));
    [string getCharacters:buffer];
    buffer[length] = 0;

    /* if this expression has a matchString and is small quickly check to see if it is in the buffer */
    if (matchString && !unicodeSubstring(matchString, buffer)) {
        if (isLarge)
            NSZoneFree(NULL, buffer);
        return NO;
    }

    /* make a string scanner and try to do a real match */
    scanner = [[OFStringScanner alloc] init];
    [scanner fetchMoreDataFromCharacters:buffer length:length offset:0 freeWhenDone:isLarge];
    result = [self findMatch:nil withScanner:scanner];
    [scanner release];
    return result;
}

- (BOOL)hasMatchInScanner:(OFStringScanner *)scanner;
{
    return [self findMatch:nil withScanner:scanner];    
}

- (NSString *)patternString;
{
    return patternString;
}

- (NSString *)prefixString;
{
    if (nextState(program) && nextState(program)->opCode == OpEnd) { /* Is there only one top level choice? */
        ExpressionState *scan = STATE_PARAMETER(program);

        if (scan->opCode == OpExactlyString) {
            unichar *uniString = STRING_PARAMETER(scan);
            return [NSString stringWithCharacters:uniString length:unicodeStringLength(uniString)];
        }
    }
    return nil;
}

- (BOOL)isPrefixOnly;
{
    NSString *prefixString = [self prefixString];
    return prefixString != nil && [patternString isEqualToString:[prefixString stringByAppendingString:@".*"]];
}

- (NSMutableDictionary *) debugDictionary;
{
    NSMutableDictionary *dict;

    dict = [super debugDictionary];
    [dict setObject: patternString forKey: @"patternString"];

    return dict;
}

@end

@implementation OFRegularExpression (Compilation)

/* compile flags - determines the complexity of the state machine so far */
#define FLAG_NONULLSTRING	1
#define FLAG_SIMPLE		2
#define FLAG_STARTSWITHSTAR	4
#define FLAG_WORSTCASE		8

#define MAX_SUBEXPRESSIONS ((1 << 12) - 1)

- (ExpressionState *)compile:(CompileStatus *)status parenthesized:(BOOL)parens flags:(unsigned int *)compileFlags;
{
    ExpressionState *result, *branch, *firstBranch, *end;
    unsigned int subFlags;
    unichar *startingLocation;
    
    startingLocation = status->scanningString;
    *compileFlags = FLAG_NONULLSTRING; /* guess to start */

    /* Make an Open state if parenthesized */
    if (parens) {
        if (subExpressionCount >= MAX_SUBEXPRESSIONS || status->subexpressionNestingCount >= MAX_SUBEXPRESSION_NESTING)
            return 0;
        result = writeState(status, OpOpen);
        result->argumentNumber = subExpressionCount++;
        status->subexpressionNesting[status->subexpressionNestingCount++] = result->argumentNumber;
    } else
        result = NULL;

    /* pick up the branches, linking them together */
    if (!(firstBranch = [self compileBranch:status flags:&subFlags]))
        return NULL;
    if (result)
        setNextPointer(result, firstBranch);
    else
        result = firstBranch;

    if (!(subFlags & FLAG_NONULLSTRING))
        *compileFlags |= ~FLAG_NONULLSTRING;
    *compileFlags |= subFlags & FLAG_STARTSWITHSTAR;

    while (*status->scanningString == '|') {
        status->scanningString++;
        if (!(branch = [self compileBranch:status flags:&subFlags]))
            return NULL;
        setNextPointer(result, branch);
        if (!(subFlags & FLAG_NONULLSTRING))
            *compileFlags |= ~FLAG_NONULLSTRING;
        *compileFlags |= subFlags & FLAG_STARTSWITHSTAR;
    }

    /* write a Close state or End state */
    if (parens) {
        end = writeState(status, OpClose);
        end->argumentNumber = status->subexpressionNesting[--status->subexpressionNestingCount];
    } else
        end = writeState(status, OpEnd);
    setNextPointer(result, end);

    /* hook the tails of the branches to the closing state */
    for (branch = firstBranch; branch; branch = nextState(branch))
        setNextPointerOnArgument(branch, end);

    /* check for proper termination */
    if (status->scanningString == startingLocation)
        return NULL; // didn't actually compile anything (happens with degenerate expressions like "()")
    else if (parens && *status->scanningString++ != ')')
        return NULL; // unmatched parens
    else if (!parens && *status->scanningString)
        return NULL; // junk on end
    return result;
}

- (ExpressionState *)compileBranch:(CompileStatus *)status flags:(unsigned int *)compileFlags;
{
    ExpressionState *result, *chain, *latest;
    unsigned int subFlags;

    *compileFlags = FLAG_WORSTCASE;

    result = writeState(status, OpBranch);
    chain = NULL;
    while (*status->scanningString && *status->scanningString != '|' && *status->scanningString != ')') {
        if (!(latest = [self compilePiece:status flags:&subFlags]))
            return NULL;
        *compileFlags |= subFlags & FLAG_NONULLSTRING;
        if (chain) {
            setNextPointer(chain, latest);
        } else {
            *compileFlags |= subFlags & FLAG_STARTSWITHSTAR;
        }
        chain = latest;
    }
    if (!chain)
        writeState(status, OpNothing);
    return result;
}

- (ExpressionState *)compilePiece:(CompileStatus *)status flags:(unsigned int *)compileFlags;
{
    ExpressionState *result, *next;
    unsigned int subFlags;
    unichar operator;
    ExpressionOpCode branchOpCode;
    BOOL isGreedy;
    
    if (!(result = [self compileAtom:status flags:&subFlags]))
        return NULL;
    operator = *status->scanningString;
    if (operator != '*' && operator != '?' && operator != '+') {
        *compileFlags = subFlags;
        return result;
    }

    if (!(subFlags & FLAG_NONULLSTRING) && operator != '?') // *+ operand empty
        return NULL;
    *compileFlags = (operator == '+') ? (FLAG_WORSTCASE|FLAG_NONULLSTRING) : (FLAG_WORSTCASE|FLAG_STARTSWITHSTAR);
    isGreedy = status->scanningString[1] != '?';
    if (!isGreedy)
        status->scanningString++;
    branchOpCode = isGreedy ? OpBranch : OpReverseBranch;

    if (operator == '*' && subFlags & FLAG_SIMPLE) {
        insertState(status, isGreedy ? OpZeroOrMoreGreedy : OpZeroOrMore, result);
    } else if (operator == '*') {
        /* write x* as (x&|) where & means self */
        insertState(status, branchOpCode, result);
        setNextPointerOnArgument(result, writeState(status, OpBack));
        setNextPointerOnArgument(result, result);
        setNextPointer(result, writeState(status, branchOpCode));
        setNextPointer(result, writeState(status, OpNothing));
    } else if (operator == '+' && subFlags & FLAG_SIMPLE) {
        insertState(status, isGreedy ? OpOneOrMoreGreedy : OpOneOrMore, result);
    } else if (operator == '+') {
        /* write x+ as x(&|) where & means self */
        next = writeState(status, branchOpCode);
        setNextPointer(result, next);
        setNextPointer(writeState(status, OpBack), result);
        setNextPointer(next, writeState(status, branchOpCode));
        setNextPointer(result, writeState(status, OpNothing));
    } else if (operator == '?') {
        /* write x? as (x|) */
        insertState(status, branchOpCode, result);
        setNextPointer(result, writeState(status, branchOpCode));
        next = writeState(status, OpNothing);
        setNextPointer(result, next);
        setNextPointerOnArgument(result, next);
    }
    status->scanningString++;
    switch(*status->scanningString) {
        case '?': case '+': case '*': // doesn't support nested
            return NULL;
        default:
            break;
    }
    return result;
}

- (ExpressionState *)compileAtom:(CompileStatus *)status flags:(unsigned int *)compileFlags;
{
    ExpressionState *result;
    unichar *startPtr, ch;
    unsigned int subFlags;

    *compileFlags = FLAG_WORSTCASE;

    switch (*status->scanningString++) {
        case '^':
            result = writeState(status, OpStartOfLine);
            break;
        case '$':
            result = writeState(status, OpEndOfLine);
            break;
        case '.':
            result = writeState(status, OpAnyCharacter);
            *compileFlags |= FLAG_NONULLSTRING | FLAG_SIMPLE;
            break;
        case '[':
            if (*status->scanningString == '^') {
                result = writeState(status, OpAnyButString);
                status->scanningString++;
            } else {
                result = writeState(status, OpAnyOfString);
            }
            if (*status->scanningString == ']' || *status->scanningString == '-') {
                writeCharacter(status, *status->scanningString++);
            }
            while (*status->scanningString && *status->scanningString != ']') {
                if (*status->scanningString == '-') {
                    status->scanningString++;
                    if (!*status->scanningString || *status->scanningString == ']') {
                        writeCharacter(status, '-');
                        status->scanningString--;
                    } else {
                        unichar start = status->scanningString[-2] + 1;
                        unichar end = *status->scanningString;
                        
                        if (start > end+1) // bad range
                            return NULL;
                        writeRange(status, start, end);
                    }
                } else
                    writeCharacter(status, *status->scanningString);
                status->scanningString++;
            }
            writeCharacter(status, 0);
            if (*status->scanningString++ != ']') // unmatched square brackets
                return NULL;
            *compileFlags |= FLAG_NONULLSTRING | FLAG_SIMPLE;
            break;
        case '(':
            result = [self compile:status parenthesized:YES flags:&subFlags];
            *compileFlags |= subFlags & (FLAG_NONULLSTRING | FLAG_STARTSWITHSTAR);
            break;
        case '\0': case '|': case ')':
            return NULL; // should be caught earlier
        case '?': case '+': case '*':
            return NULL; // these need to follow something else
        case '\\':
            if (*status->scanningString == '\0')
                return NULL; // bad trailing backslash
			ch = *status->scanningString;
            switch (ch) {
                case 'n':
                    result = writeState(status, OpExactlyString);
                    writeCharacter(status, '\n');
                    break;
                case 'r':
                    result = writeState(status, OpExactlyString);
                    writeCharacter(status, '\r');
                    break;
                case 'd': // any number character
                case 'D': // any NON-number character
                    result = writeState(status, ch == 'd' ? OpAnyOfString : OpAnyButString);
                    writeRange(status, '0', '9');
                    break;
                case 'w': // any word character
                case 'W': // any NON-word character
                    result = writeState(status, ch == 'w' ? OpAnyOfString : OpAnyButString);
                    writeRange(status, 'a', 'z');
                    writeRange(status, 'A', 'Z');
                    writeRange(status, '0', '9');
                    writeCharacter(status, '_');
                    break;
                case 's': // any whitespace character
                case 'S': // any NON-whitespace character
                    result = writeState(status, ch == 's' ? OpAnyOfString : OpAnyButString);
                    writeCharacter(status, ' ');
                    writeCharacter(status, '\t');
                    writeCharacter(status, '\n');
                    writeCharacter(status, '\r');
                    break;
                case 't':
                    result = writeState(status, OpExactlyString);
                    writeCharacter(status, '\t');
                    break;
                default:
                    result = writeState(status, OpExactlyString);
                    writeCharacter(status, *status->scanningString);
                    break;
            }
            writeCharacter(status, '\0');
            status->scanningString++;
            *compileFlags |= FLAG_NONULLSTRING | FLAG_SIMPLE;
            break;
        default:
            startPtr = --status->scanningString;
            result = writeState(status, OpExactlyString);
            while (*status->scanningString) {
                BOOL done = NO;
                
                switch (*status->scanningString) {
                    case '^': case '$': case '.': case '[': case '(':
                    case ')': case '|': case '\\':
                        done = YES;
                        break;
                    case '?': case '*': case '+':
                        if (status->scanningString - startPtr  != 1)
                            status->scanningString--;
                        done = YES;
                        break;
                    default:
                        break;
                }
                if (done)
                    break;
                status->scanningString++;
            }
            *compileFlags |= FLAG_NONULLSTRING;
            if ((status->scanningString - startPtr) == 1)
                *compileFlags |= FLAG_SIMPLE;
            while (startPtr < status->scanningString)
                writeCharacter(status, *startPtr++);
            writeCharacter(status, 0);
            break;
    }
    return result;
}

- (void)findOptimizations:(unsigned int)compileFlags;
{
    ExpressionState *scan = program;

    startCharacter = 0;
    matchStartsLine = NO;
    matchString = NULL;

    if (nextState(scan) && nextState(scan)->opCode == OpEnd) { /* Is there only one top level choice? */
        scan = STATE_PARAMETER(scan);
        if (scan->opCode == OpExactlyString) {
            startCharacter = *STRING_PARAMETER(scan);
        } else if (scan->opCode == OpStartOfLine) {
            startCharacter = '\n';
            matchStartsLine = YES;            
        }

        /* If this is an expensive state machine, it is worth it to find a matchString */
        if (compileFlags & FLAG_STARTSWITHSTAR) {
            unsigned int matchLength = 0;
            
            while (scan) {
                if (scan->opCode == OpExactlyString) {
                    unichar *string = STRING_PARAMETER(scan);
                    unsigned int length = unicodeStringLength(string);
                    
                    if (length >= matchLength) {
                        matchLength = length;
                        matchString = string;
                    }
                }
                scan = nextState(scan);
            }
        }
    }
}

- (NSString *)descriptionOfState:(ExpressionState *)state;
{
    switch(state->opCode) {
        case OpEnd: return @"End";
        case OpStartOfLine: return @"StartOfLine";
        case OpEndOfLine: return @"EndOfLine";
        case OpAnyCharacter: return @"AnyCharacter";
        case OpAnyOfString: return @"AnyOfString";
        case OpAnyButString: return @"AnyButString";
        case OpBranch: return @"Branch";
        case OpReverseBranch: return @"ReverseBranch";
        case OpBack: return @"Back";
        case OpExactlyString: return @"ExactlyString";
        case OpNothing: return @"Nothing";
        case OpZeroOrMore: return @"ZeroOrMore";
        case OpOneOrMore: return @"OneOrMore";
        case OpZeroOrMoreGreedy: return @"ZeroOrMore(Greedy)";
        case OpOneOrMoreGreedy: return @"OneOrMore(Greedy)";
        case OpOpen: return [NSString stringWithFormat:@"Open#%d", state->argumentNumber];
        case OpClose: return [NSString stringWithFormat:@"Close#%d", state->argumentNumber];
        default: return @"***Corrupted***";
    }
}

- (NSString *)description;
{
    ExpressionOpCode operator = OpStartOfLine; // arbitrary non End op
    ExpressionState *next, *state = program;
    NSMutableString *result = [NSMutableString string];
    
    while (operator != OpEnd) {
        [result appendFormat:@"%2d:%@", state - program, [self descriptionOfState:state]];
        next = nextState(state);
        if (next)
            [result appendFormat:@"(%d)", next - program];
        else
            [result appendString:@"(0)"];
        operator = state->opCode;
        if (operator == OpAnyOfString || operator == OpAnyButString || operator == OpExactlyString) {
            unichar *string = STRING_PARAMETER(state);
            unsigned int length = unicodeStringLength(string);
            
            [result appendString:[NSString stringWithCharacters:string length:length]];
            state++;
        }
        [result appendString:@"\n"];
        state++;
    } 
    if (startCharacter)
        [result appendFormat:@"Starts with '%c' ", startCharacter];
    if (matchStartsLine)
        [result appendString:@"anchored "];
    if (matchString)
        [result appendFormat:@"must have \"%@\"", [NSString stringWithCharacters:matchString length:unicodeStringLength(matchString)]];
    [result appendString:@"\n"];
    return result;
}

@end

@implementation OFRegularExpression (Search)

static inline BOOL characterInUnicodeString(unichar character, unichar *string)
{
    while (*string) {
        if (*string++ == character)
            return YES;
    }
    return NO;
}

#define CHECK_START_OF_LINE(character)				\
	if (character == '\r') {				\
            if (scannerPeekCharacter(scanner) == '\n')		\
                scannerSkipPeekedCharacter(scanner);		\
            beginningOfLine = YES;				\
        } else if (character == '\n') {				\
            beginningOfLine = YES;				\
        } else {						\
            beginningOfLine = NO;				\
        }

- (BOOL)findMatch:(OFRegularExpressionMatch *)match withScanner:(OFStringScanner *)scanner;
{
    BOOL beginningOfLine;
    if (scannerScanLocation(scanner)) {
	[scanner setScanLocation:scannerScanLocation(scanner)-1];
	beginningOfLine = (scannerReadCharacter(scanner) == '\n');
    } else 
	beginningOfLine = YES;
    
    if (matchStartsLine) {
        if (beginningOfLine && [self tryMatch:match withScanner:scanner atStartOfLine:YES])
            return YES;
        
        while (scannerScanUpToCharacter(scanner, '\n')) {
            scannerSkipPeekedCharacter(scanner);
            if ([self tryMatch:match withScanner:scanner atStartOfLine:YES])
                return YES;
        }
    } else if (startCharacter) {
        while (scannerScanUpToCharacter(scanner, startCharacter)) {
            if ([self tryMatch:match withScanner:scanner atStartOfLine:(startCharacter == '\n')])
                return YES;
            scannerReadCharacter(scanner);
        }
    } else {
        while (scannerHasData(scanner)) {
            if ([self tryMatch:match withScanner:scanner atStartOfLine:beginningOfLine])
                return YES;
            unichar c = scannerReadCharacter(scanner);
	    CHECK_START_OF_LINE(c);
        }
    }
    return NO;
}

#define BAD_LOCATION ((unsigned int)-1)

- (BOOL)tryMatch:(OFRegularExpressionMatch *)match withScanner:(OFStringScanner *)scanner atStartOfLine:(BOOL)beginningOfLine;
{
    NSRange *start, *end;
    unsigned int startLocation;
    
    /* initialize match's subexpression ranges */
    if (match) {
        start = match->subExpressionMatches;
        end = start + subExpressionCount;
        while (start < end) {
            start->location = INVALID_SUBEXPRESSION_LOCATION;
            start->length = INVALID_SUBEXPRESSION_LOCATION;
            start++;
        }
    }
    
    /* save current location */
    [scanner setRewindMark];
    startLocation = scannerScanLocation(scanner);
    
    if ([self nestedMatch:match inState:program withScanner:scanner atStartOfLine:beginningOfLine]) {
        if (match) {
            match->matchRange.location = startLocation;
            match->matchRange.length = scannerScanLocation(scanner) - startLocation;            
        } else
            [scanner discardRewindMark];
        return YES;
    } else {
        [scanner rewindToMark];
        return NO;        
    }
}

- (BOOL)nestedMatch:(OFRegularExpressionMatch *)match inState:(ExpressionState *)state withScanner:(OFStringScanner *)scanner atStartOfLine:(BOOL)beginningOfLine;
{
    unichar character, *ptr;
    ExpressionState *next;
    unsigned int minimumMatches, matchCount;
    unsigned int currentLocation;

    while (state) {
        next = nextState(state);
        
        switch(state->opCode) {
            case OpEnd:
                return YES;
            case OpStartOfLine:
                if (!beginningOfLine)
                    return NO;
                break;
            case OpEndOfLine:
                if ((character = scannerReadCharacter(scanner))) {
                    CHECK_START_OF_LINE(character);
                    if (!beginningOfLine)
                        return NO;
                } 
                break;
            case OpAnyCharacter:
                if (!(character = scannerReadCharacter(scanner)))
                    return NO;
                CHECK_START_OF_LINE(character);
                break;
            case OpAnyOfString:
                if (!(character = scannerReadCharacter(scanner)) || !characterInUnicodeString(character, STRING_PARAMETER(state)))
                    return NO;
                CHECK_START_OF_LINE(character);
                break;
            case OpAnyButString:
                if (!(character = scannerReadCharacter(scanner)) || characterInUnicodeString(character, STRING_PARAMETER(state)))
                    return NO;
                CHECK_START_OF_LINE(character);
                break;
            case OpBranch:
                if (nextState(state) && nextState(state)->opCode != OpBranch) // avoid recursion if possible
                    next = STATE_PARAMETER(state);
                else {
                    currentLocation = scannerScanLocation(scanner);
                    
                    do {
                        if ([self nestedMatch:match inState:STATE_PARAMETER(state) withScanner:scanner atStartOfLine:beginningOfLine])
                            return YES;
                        [scanner setScanLocation:currentLocation];
                        state = nextState(state);
                    } while (state && state->opCode == OpBranch);
                    return NO;
                }
                break;
            case OpReverseBranch:
                if (nextState(state) && nextState(state)->opCode == OpReverseBranch) {
                    currentLocation = scannerScanLocation(scanner);
                    if ([self nestedMatch:match inState:nextState(state) withScanner:scanner atStartOfLine:beginningOfLine])
                        return YES;
                    [scanner setScanLocation:currentLocation];
                }
                next = STATE_PARAMETER(state);
                break;
            case OpBack:
                break;
            case OpExactlyString:
                ptr = STRING_PARAMETER(state);
                while (*ptr) {
                    if (*ptr++ != scannerReadCharacter(scanner))
                        return NO;
                }
                break;
            case OpNothing:
                break;
            case OpZeroOrMoreGreedy:
            case OpOneOrMoreGreedy:
                /* lookahead to avoid useless match attempts if we know what character comes next */
                if (next->opCode == OpExactlyString)
                    character = *STRING_PARAMETER(next);
                else
                    character = 0;
                minimumMatches = state->opCode == OpZeroOrMoreGreedy ? 0 : 1;
                currentLocation = scannerScanLocation(scanner);
                matchCount = [self repeatedlyMatchState:STATE_PARAMETER(state) withScanner:scanner];
                while (matchCount >= minimumMatches) {
                    /* if it could work, try it */
                    if (!character || scannerPeekCharacter(scanner) == character)
                        if ([self nestedMatch:match inState:next withScanner:scanner atStartOfLine:beginningOfLine])
                            return YES;
                    /* didn't work, so back up */
                    if (matchCount == 0)
                        return NO;
                    matchCount--;
                    [scanner setScanLocation:currentLocation + matchCount];
                }
                return NO;
            case OpZeroOrMore:
            case OpOneOrMore:
                /* lookahead to avoid useless match attempts if we know what character comes next */
                if (next->opCode == OpExactlyString)
                    character = *STRING_PARAMETER(next);
                else
                    character = 0;
                minimumMatches = state->opCode == OpZeroOrMoreGreedy ? 0 : 1;
                matchCount = 0;
                while (matchCount < minimumMatches) {
                    if (![self matchNextCharacterInState:STATE_PARAMETER(state) withScanner:scanner])
                        return NO;
                    matchCount++;
                }
                do {
                    if (!character || scannerPeekCharacter(scanner) == character) {
                        currentLocation = scannerScanLocation(scanner);
                        if ([self nestedMatch:match inState:next withScanner:scanner atStartOfLine:beginningOfLine])
                            return YES;
                        [scanner setScanLocation:currentLocation];
                    }
                } while ([self matchNextCharacterInState:STATE_PARAMETER(state) withScanner:scanner]);
                return NO;
            case OpOpen:
                if (match)
                    match->subExpressionMatches[state->argumentNumber].location = scannerScanLocation(scanner);
                break;
            case OpClose:
                if (match)
                    match->subExpressionMatches[state->argumentNumber].length = scannerScanLocation(scanner) - match->subExpressionMatches[state->argumentNumber].location;
                break;
            default:
                // oops, this is bad
                break;
        }
        state = next;
    }
    // should never get here
    return NO;
}

- (BOOL)matchNextCharacterInState:(const ExpressionState *)state withScanner:(OFStringScanner *)scanner;
{
    unichar character;

    switch(state->opCode) {
        case OpAnyCharacter:
            return (scannerReadCharacter(scanner) != OFCharacterScannerEndOfDataCharacter);
        case OpAnyOfString:
            if (((character = scannerPeekCharacter(scanner)) != OFCharacterScannerEndOfDataCharacter) && characterInUnicodeString(character, STRING_PARAMETER(state))) {
                scannerSkipPeekedCharacter(scanner);
                return YES;
            }
            break;
        case OpAnyButString:
            if (((character = scannerPeekCharacter(scanner)) != OFCharacterScannerEndOfDataCharacter) && !characterInUnicodeString(character, STRING_PARAMETER(state))) {
                scannerSkipPeekedCharacter(scanner);
                return YES;
            }
            break;
        case OpExactlyString:
            if (scannerPeekCharacter(scanner) == *STRING_PARAMETER(state)) {
                scannerSkipPeekedCharacter(scanner);
                return YES;
            }
            break;
        default:
            OBASSERT_NOT_REACHED("Unexpected opcode in OFRegularExpressionMatch");
            // oops, this is bad
            break;
    }
    
    return NO;
}

- (unsigned int)repeatedlyMatchState:(const ExpressionState *)state withScanner:(OFStringScanner *)scanner;
{
    unsigned int count = 0;
    unichar character;

    switch(state->opCode) {
        case OpAnyCharacter:
            count = scannerScanLocation(scanner);
            while ([scanner fetchMoreData])
                ;
            scanner->scanLocation = scanner->scanEnd;
            count = scannerScanLocation(scanner) - count;
            break;
        case OpAnyOfString:
            while (((character = scannerPeekCharacter(scanner)) != OFCharacterScannerEndOfDataCharacter) && characterInUnicodeString(character, STRING_PARAMETER(state))) {
                scannerSkipPeekedCharacter(scanner);
                count++;
            }
            break;
        case OpAnyButString:
            while (((character = scannerPeekCharacter(scanner)) != OFCharacterScannerEndOfDataCharacter) && !characterInUnicodeString(character, STRING_PARAMETER(state))) {
                scannerSkipPeekedCharacter(scanner);
                count++;
            }
            break;
        case OpExactlyString:
            while (scannerPeekCharacter(scanner) == *STRING_PARAMETER(state)) {
                scannerSkipPeekedCharacter(scanner);
                count++;
            }
            break;
        default:
            // oops, this is bad
            OBASSERT_NOT_REACHED("Unexpected opcode in OFRegularExpressionMatch");
            break;
    }
    return count;
}

@end

