// Copyright 2002-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAOSAScript.h"

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniFoundation/OFResourceFork.h>

#import "NSBundle-OAExtensions.h"

RCS_ID("$Id$")

NSString * const OSAScriptException = @"OSAScriptException";
NSString * const OSAScriptExceptionSourceRangeKey = @"OSAScriptExceptionSourceRangeKey";

@interface OAOSAScript (PrivateMethods)
- (void)raiseScriptException;
- (NSString *)sourceForScriptID:(long int)anOSAID;
- (BOOL)loadData:(NSData *)data;
- (void)_showUserInterface;
- (void)_hideUserInterface;

static BOOL CreateAEDescFromNSString(NSString *string, BOOL allowText, BOOL allowUtxt, BOOL allowLoss, AEDesc *descriptor);

static id aedesc_to_id(AEDesc *desc);

@end

static ComponentInstance OFAppleScriptComponent;
static BOOL userCancelled;
static OAOSAScript *runningScript = nil;
static NSDate *runStartDate = nil;

@implementation OAOSAScript

NSData * OADataForAEDescriptor(AEDesc *descriptor)
{
    NSMutableData *data;

    data = [[NSMutableData alloc] initWithLength:AEGetDescDataSize(descriptor)];
    AEGetDescData(descriptor, [data mutableBytes], [data length]);
    return [data autorelease];
}

OSErr OAOSAActiveProc(long referenceValue)
{
    id event;

    if (userCancelled)
        return userCanceledErr;
    
    if (runStartDate && [[NSDate date] timeIntervalSinceDate:runStartDate] >= 0.5) {
        [runStartDate release];
        runStartDate = nil;
        [runningScript _showUserInterface];
    }

    // post events
    while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES]))
        [NSApp sendEvent:event];
    return noErr;
}

+ (void)initialize;
{
    OBINITIALIZE;
    OFAppleScriptComponent = OpenDefaultComponent(kOSAComponentType, kOSAGenericScriptingComponentSubtype);
    // 'ascx' is the component subtype for AppleScript X
    // NSAppleScript can get us a ComponentInstance, can we change it?
    OSASetActiveProc(OFAppleScriptComponent, OAOSAActiveProc, 0);
    OSASetDefaultTarget(OFAppleScriptComponent, NULL);
    
    // load current application's script dictionary resource
    if ([[[NSBundle mainBundle] localizations] containsObject:@"English"])
        [[NSScriptSuiteRegistry sharedScriptSuiteRegistry] aeteResource:@"English"];
}

+ (NSString *)executeScriptString:(NSString *)scriptString;
{
    OAOSAScript *script;
    
    script = [[[self alloc] initWithSourceCode: scriptString] autorelease];
    return [script execute];
}

+ (OAOSAScript *)runningScript;
{
    return runningScript;
}

- init;
{
    AEDesc nullName;
    OSAError osaError;
    
    [super init];
    
    scriptID = kOSANullScript;
    scriptContextID = kOSANullScript;
    AEInitializeDescInline(&nullName);  // sets it to typeNull
    osaError = OSAMakeContext(OFAppleScriptComponent, &nullName, kOSANullScript, &scriptContextID);
    if (osaError != noErr)
        NSLog(@"%@: OSAMakeContext() returned %d", [self shortDescription], osaError);
    // TODO: Do something with that error
    
    return self;
}

- initWithPath:(NSString *)scriptPath;
{
    [self init];
    
    // load the resource fork
    NSData *data;
    NS_DURING {
        OFResourceFork *resourceFork = [[OFResourceFork alloc] initWithContentsOfFile:scriptPath];
        data = [resourceFork dataForResourceType:kOSAScriptResourceType atIndex:0];
        [resourceFork release];
    } NS_HANDLER {
        // if that doesn't work, just get the data fork
        data = [NSData dataWithContentsOfFile:scriptPath];
    } NS_ENDHANDLER

    // if that doesn't work, try compiling text
    if (![self loadData:data]) {
        NSString *source;
        
        source = [[[NSString alloc] initWithData:data encoding:[NSString defaultCStringEncoding]] autorelease];
        return [self initWithSourceCode:source];
    }    
    return self;
}

- initWithData:(NSData *)compiledData;
{
    [self init];
    if (![self loadData:compiledData]) {
        [self autorelease];
        [self raiseScriptException];
    }
    return self;
}

- initWithSourceCode:(NSString *)sourceText;
{   
    [self init];
    
    NS_DURING {
        [self setSourceCode:sourceText];
    } NS_HANDLER {
        [self autorelease];
        [localException raise];
    } NS_ENDHANDLER;
    
    return self;
}

- (void)dealloc;
{
    if (scriptID != kOSANullScript)
        OSADispose(OFAppleScriptComponent, scriptID);
    OSADispose(OFAppleScriptComponent, scriptContextID);
    [super dealloc];
}

- (BOOL)isValid;
{
    return scriptID != kOSANullScript;
}

- (void)setSourceCode:(NSString *)someSource;
{
    AEDesc descriptor;
    OSErr error;

    // build an AEDesc with the source
    AECreateDesc(typeChar, [someSource cString], [someSource cStringLength], &descriptor);

    // compile
    error = OSACompile(OFAppleScriptComponent, &descriptor, kOSAModeNull, &scriptID);
    AEDisposeDesc(&descriptor); 

    if (error != noErr) 
        [self raiseScriptException];
}

- (NSString *)sourceCode;
{
    return [self sourceForScriptID:scriptID];
}

- (NSString *)execute;
{
    OSErr error;
    OSAID resultID;
    NSString *resultString;

    runningScript = self;
    error = OSAExecute(OFAppleScriptComponent, scriptID, scriptContextID, kOSAModeNull, &resultID);
    runningScript = nil;
    userCancelled = NO;
    if (error != noErr)
        [self raiseScriptException];

    if (!(resultString = [self sourceForScriptID:resultID]))
        resultString = @"(no result)";

    OSADispose(OFAppleScriptComponent, resultID);
    return resultString;
}

- (NSString *)executeWithInterfaceOnWindow:(NSWindow *)aWindow;
{
    NSString *resultString = nil;

    runStartDate = [[NSDate alloc] init];
    runAttachedWindow = aWindow;
    NS_DURING {
        resultString = [self execute];
    } NS_HANDLER {
        [self queueSelector:@selector(_hideUserInterface)];
        [localException raise];
    } NS_ENDHANDLER;

    [self queueSelector:@selector(_hideUserInterface)];
    return resultString;
}

- (NSData *)compiledData;
{
    AEDesc descriptor;
    OSErr error;
    NSData *data;
    
    error = OSAStore(OFAppleScriptComponent, scriptID, typeOSAGenericStorage, kOSAModeNull, &descriptor);
    if (error != noErr)
        return nil;
    data = OADataForAEDescriptor(&descriptor);
    AEDisposeDesc(&descriptor);
    return data;
}

- (void)stopScript:sender;
{
    userCancelled = YES;
}

- (void)setProperty:(NSString *)propName toString:(NSString *)value
{
    AEDesc propDesc, valueDesc;
    BOOL propDescOK, valueDescOK;
    OSAID valueID;
    OSAError osaErr;
    NSException *hadError;
    NSString *errorMessage;
    OSAID realScriptContextID;
    ComponentInstance realComponentInstance;

    errorMessage = nil;
    hadError = nil;
    valueID = kOSANullScript;

    /* Convert the name and value strings to AEDescs */
    propDescOK = CreateAEDescFromNSString(propName, YES, NO, NO, &propDesc);
    valueDescOK = CreateAEDescFromNSString(value, YES, YES, NO, &valueDesc);

    if (!propDescOK) {
        errorMessage = [NSString stringWithFormat:@"Cannot coerce string \"%@\" to AppleEvent property name", propName];
    } else if (!valueDescOK) {
        errorMessage = [NSString stringWithFormat:@"Cannot coerce string \"%@\" to AppleEvent text", value];
    } else {
        /* We use a generic scripting component, so we need to find the underlying real scripting component (and its OSAID for our context) */
        realScriptContextID = scriptContextID;
        realComponentInstance = NULL;
        osaErr = OSAGenericToRealID(OFAppleScriptComponent, &realScriptContextID, &realComponentInstance);
        if (osaErr != noErr)
            [NSException raise:OSAScriptException format:@"OSAGenericToRealID returns error code %d", osaErr];
        
        /* Create an OSAID in our script component for the value we want to set */
        osaErr = OSACoerceFromDesc(realComponentInstance, &valueDesc, kOSAModeNull, &valueID);
        if (osaErr != noErr) {
            errorMessage = [NSString stringWithFormat:@"Error using string in AppleScript (%d)", osaErr];
        } else {
            /* Actually set the property */
            osaErr = OSASetProperty(realComponentInstance, kOSAModeNull, realScriptContextID, &propDesc, valueID);
            if (osaErr != noErr)
                errorMessage = [NSString stringWithFormat:@"Error setting AppleScript property (%d)", osaErr];

            OSADispose(realComponentInstance, valueID);
        }
    }

    if (propDescOK)
        AEDisposeDesc(&propDesc);
    if (valueDescOK)
        AEDisposeDesc(&valueDesc);

    if (errorMessage && !hadError)
        hadError = [NSException exceptionWithName:OSAScriptException reason:errorMessage userInfo:nil];

    if (hadError)
        [hadError raise];
}

- valueOfProperty:(NSString *)propName
{
    AEDesc propDesc, valueDesc;
    OSAID valueID;
    OSAError osaErr;
    NSString *errorMessage;
    OSAID realScriptID;
    id result;
    ComponentInstance realComponentInstance;

    realScriptID = scriptContextID;
    realComponentInstance = NULL;
    osaErr = OSAGenericToRealID(OFAppleScriptComponent, &realScriptID, &realComponentInstance);
    if (osaErr != noErr)
        [NSException raise:OSAScriptException format:@"OSAGenericToRealID returns error code %d", osaErr];

    errorMessage = nil;
    valueID = kOSANullScript;
    result = nil;

    if (!CreateAEDescFromNSString(propName, YES, NO, NO, &propDesc)) {
        errorMessage = [NSString stringWithFormat:@"Cannot coerce string \"%@\" to AppleEvent property name", propName];
    } else {
        AEInitializeDescInline(&valueDesc);

        // Get an OSA ID for the variable's value
        osaErr = OSAGetProperty(realComponentInstance, kOSAModeNull, realScriptID, &propDesc, &valueID);
        AEDisposeDesc(&propDesc);

        if (osaErr == noErr) {
            // Extract the data from the script component
            osaErr = OSACoerceToDesc(realComponentInstance, valueID, typeWildCard, kOSAModeNull, &valueDesc);
            OSADispose(realComponentInstance, valueID);

            // Convert it to a Foundation type
            if (osaErr == noErr) {
                result = aedesc_to_id(&valueDesc);
                AEDisposeDesc(&valueDesc);
            }
        }

        if (osaErr != noErr) {
            errorMessage = [NSString stringWithFormat:@"Error retrieving script property (%d)", osaErr];
            if (osaErr == errOSAScriptError) { [self raiseScriptException]; }
        }
    }

    if (errorMessage)
        [[NSException exceptionWithName:OSAScriptException reason:errorMessage userInfo:nil] raise];

    return result;
}

@end

@implementation OAOSAScript (PrivateMethods)

- (void)raiseScriptException;
{
    AEDesc descriptor, recordDescriptor;
    NSString *errorMessage;
    NSData *errorData;
    NSDictionary *userInfo;
    short startPosition, endPosition;
    Size actualSize;
    DescType actualType;
    
    // get the error message
    OSAScriptError(OFAppleScriptComponent, kOSAErrorMessage, typeChar, &descriptor);
    errorData = OADataForAEDescriptor(&descriptor);
    errorMessage = [NSString stringWithCString:[errorData bytes] length:[errorData length]];
    AEDisposeDesc(&descriptor);
    
    // get the source code range
    OSAScriptError(OFAppleScriptComponent, kOSAErrorRange, typeOSAErrorRange, &descriptor);
    AECoerceDesc(&descriptor, typeAERecord, &recordDescriptor);
    AEDisposeDesc(&descriptor);
    AEGetKeyPtr(&recordDescriptor, keyOSASourceStart, typeShortInteger, &actualType, &startPosition, sizeof(startPosition), &actualSize);
    AEGetKeyPtr(&recordDescriptor, keyOSASourceEnd, typeShortInteger, &actualType, &endPosition, sizeof(endPosition), &actualSize);
    AEDisposeDesc(&recordDescriptor);

    // generate the exception
    userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSValue valueWithRange:NSMakeRange(startPosition, endPosition - startPosition)], OSAScriptExceptionSourceRangeKey, nil];
    [[NSException exceptionWithName:OSAScriptException reason:errorMessage userInfo:userInfo] raise];
}

- (NSString *)sourceForScriptID:(long int)anOSAID;
{
    AEDesc result;
    NSData *data;
        
    if (anOSAID == kOSANullScript)
        return nil;
    OSAGetSource(OFAppleScriptComponent, anOSAID, typeChar, &result);
    data = OADataForAEDescriptor(&result);
    AEDisposeDesc(&result);
    return [[[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding] autorelease];
}

- (BOOL)loadData:(NSData *)data;
{
    AEDesc scriptData;
    OSErr error;

    // stuff the compiled script into the scripting component
    AECreateDesc(typeOSAGenericStorage, [data bytes], [data length], &scriptData);    
    error = OSALoad(OFAppleScriptComponent, &scriptData, kOSAModeNull, &scriptID);
    AEDisposeDesc(&scriptData);
    return error == noErr;
}


static BOOL CreateAEDescFromNSString(NSString *string, BOOL allowText, BOOL allowUtxt, BOOL allowLoss, AEDesc *descriptor)
{
    DescType descriptorType;
    NSData *stringData;
    OSErr err;

    stringData = nil;
    descriptorType = typeNull;

    if (allowText) {
        stringData = [string dataUsingEncoding:NSMacOSRomanStringEncoding allowLossyConversion:(allowLoss && !allowUtxt)];
        if (stringData)
            descriptorType = typeChar;
    }

    if (!stringData && allowUtxt) {
        stringData = [string dataUsingEncoding:NSUnicodeStringEncoding allowLossyConversion:allowLoss];
        if (stringData)
            descriptorType = typeUnicodeText;
    }
    
    if (!stringData)
        return NO;

    err = AECreateDesc(descriptorType, [stringData bytes], [stringData length], descriptor);
    if (err != noErr)
        return NO;

    return YES;
}

//
// Potentially very useful code that isn't actually used right now
//

//
// Cool except that all of these exceptions are picked up by the OSAError routine in a much cleaner way
//
static NSException *make_AE_err(OSErr errCode)
{
    NSString *name, *msg, *display;
    NSMutableDictionary *dict;
    
    switch (errCode) {

//Generated by the following perl script from a few selected enums in MacErrors.h:
//while(<>) {
//    next unless /^\s*(\S+)\s*\=\s*[-\d,]+\s*(.*)$/;
//    ($tok, $msg) = ($1, $2);
//
//    $name = $tok;
//    $name =~ s/^(errAE|errOSA|err)//;
//
//    $msg =~ s-^\s*(/\*)?\s*--;
//    $msg =~ s-\s*(\*/)?\s*$--;
//
//    print "        case $tok: name = \@\"$name\"; ";
//    if ($msg ne '') {
//        print "msg = \@\"$msg\";";
//    } else {
//        print "msg = nil;";
//    }
//
//    print " break;\n";
//}
    
        case errAECoercionFail: name = @"CoercionFail"; msg = @"bad parameter data or unable to coerce the data supplied"; break;
        case errAEDescNotFound: name = @"DescNotFound"; msg = nil; break;
        case errAECorruptData: name = @"CorruptData"; msg = nil; break;
        case errAEWrongDataType: name = @"WrongDataType"; msg = nil; break;
        case errAENotAEDesc: name = @"NotAEDesc"; msg = nil; break;
        case errAEBadListItem: name = @"BadListItem"; msg = @"the specified list item does not exist"; break;
        case errAENewerVersion: name = @"NewerVersion"; msg = @"need newer version of the AppleEvent manager"; break;
        case errAENotAppleEvent: name = @"NotAppleEvent"; msg = @"the event is not in AppleEvent format"; break;
        case errAEEventNotHandled: name = @"EventNotHandled"; msg = @"the AppleEvent was not handled by any handler"; break;
        case errAEReplyNotValid: name = @"ReplyNotValid"; msg = @"AEResetTimer was passed an invalid reply parameter"; break;
        case errAEUnknownSendMode: name = @"UnknownSendMode"; msg = @"mode wasn't NoReply, WaitReply, or QueueReply or Interaction level is unknown"; break;
        case errAEWaitCanceled: name = @"WaitCanceled"; msg = @"in AESend, the user cancelled out of wait loop for reply or receipt"; break;
        case errAETimeout: name = @"Timeout"; msg = @"the AppleEvent timed out"; break;
        case errAENoUserInteraction: name = @"NoUserInteraction"; msg = @"no user interaction is allowed"; break;
        case errAENotASpecialFunction: name = @"NotASpecialFunction"; msg = @"there is no special function for/with this keyword"; break;
        case errAEParamMissed: name = @"ParamMissed"; msg = @"a required parameter was not accessed"; break;
        case errAEUnknownAddressType: name = @"UnknownAddressType"; msg = @"the target address type is not known"; break;
        case errAEHandlerNotFound: name = @"HandlerNotFound"; msg = @"no handler in the dispatch tables fits the parameters to AEGetEventHandler or AEGetCoercionHandler"; break;
        case errAEReplyNotArrived: name = @"ReplyNotArrived"; msg = @"the contents of the reply you are accessing have not arrived yet"; break;
        case errAEIllegalIndex: name = @"IllegalIndex"; msg = @"index is out of range in a put operation"; break;
        case errAEImpossibleRange: name = @"ImpossibleRange"; msg = @"A range like 3rd to 2nd, or 1st to all."; break;
        case errAEWrongNumberArgs: name = @"WrongNumberArgs"; msg = @"Logical op kAENOT used with other than 1 term"; break;
        case errAEAccessorNotFound: name = @"AccessorNotFound"; msg = @"Accessor proc matching wantClass and containerType or wildcards not found"; break;
        case errAENoSuchLogical: name = @"NoSuchLogical"; msg = @"Something other than AND, OR, or NOT"; break;
        case errAEBadTestKey: name = @"BadTestKey"; msg = @"Test is neither typeLogicalDescriptor nor typeCompDescriptor"; break;
        case errAENotAnObjSpec: name = @"NotAnObjSpec"; msg = @"Param to AEResolve not of type 'obj '"; break;
        case errAENoSuchObject: name = @"NoSuchObject"; msg = @"e.g.,: specifier asked for the 3rd, but there are only 2. Basically, this indicates a run-time resolution error."; break;
        case errAENegativeCount: name = @"NegativeCount"; msg = @"CountProc returned negative value"; break;
        case errAEEmptyListContainer: name = @"EmptyListContainer"; msg = @"Attempt to pass empty list as container to accessor"; break;
        case errAEUnknownObjectType: name = @"UnknownObjectType"; msg = @"available only in version 1.0.1 or greater"; break;
        case errAERecordingIsAlreadyOn: name = @"RecordingIsAlreadyOn"; msg = @"available only in version 1.0.1 or greater"; break;
        case errAEReceiveTerminate: name = @"ReceiveTerminate"; msg = @"break out of all levels of AEReceive to the topmost (1.1 or greater)"; break;
        case errAEReceiveEscapeCurrent: name = @"ReceiveEscapeCurrent"; msg = @"break out of only lowest level of AEReceive (1.1 or greater)"; break;
        case errAEEventFiltered: name = @"EventFiltered"; msg = @"event has been filtered, and should not be propogated (1.1 or greater)"; break;
        case errAEDuplicateHandler: name = @"DuplicateHandler"; msg = @"attempt to install handler in table for identical class and id (1.1 or greater)"; break;
        case errAEStreamBadNesting: name = @"StreamBadNesting"; msg = @"nesting violation while streaming"; break;
        case errAEStreamAlreadyConverted: name = @"StreamAlreadyConverted"; msg = @"attempt to convert a stream that has already been converted"; break;
        case errAEDescIsNull: name = @"DescIsNull"; msg = @"attempting to perform an invalid operation on a null descriptor"; break;
        case errAEBuildSyntaxError: name = @"BuildSyntaxError"; msg = @"AEBuildDesc and friends detected a syntax error"; break;
        case errAEBufferTooSmall: name = @"BufferTooSmall"; msg = @"buffer for AEFlattenDesc too small"; break;
        case errOSASystemError: name = @"SystemError"; msg = nil; break;
        case errOSAInvalidID: name = @"InvalidID"; msg = nil; break;
        case errOSABadStorageType: name = @"BadStorageType"; msg = nil; break;
        case errOSAScriptError: name = @"ScriptError"; msg = nil; break;
        case errOSABadSelector: name = @"BadSelector"; msg = nil; break;
        case errOSASourceNotAvailable: name = @"SourceNotAvailable"; msg = nil; break;
        case errOSANoSuchDialect: name = @"NoSuchDialect"; msg = nil; break;
        case errOSADataFormatObsolete: name = @"DataFormatObsolete"; msg = nil; break;
        case errOSADataFormatTooNew: name = @"DataFormatTooNew"; msg = nil; break;
        case errOSAComponentMismatch: name = @"ComponentMismatch"; msg = @"Parameters are from 2 different components"; break;
        case errOSACantOpenComponent: name = @"CantOpenComponent"; msg = @"Can't connect to scripting system with that ID"; break;
        case errOffsetInvalid: name = @"OffsetInvalid"; msg = nil; break;
        case errOffsetIsOutsideOfView: name = @"OffsetIsOutsideOfView"; msg = nil; break;
        case errTopOfDocument: name = @"TopOfDocument"; msg = nil; break;
        case errTopOfBody: name = @"TopOfBody"; msg = nil; break;
        case errEndOfDocument: name = @"EndOfDocument"; msg = nil; break;
        case errEndOfBody: name = @"EndOfBody"; msg = nil; break;
            
            default: name = nil; msg = nil;
    }
    
    if (!name)
        display = [NSString stringWithFormat:@"MacOS error code %d", errCode];
    else if (!msg)
        display = [NSString stringWithFormat:@"%@ error", name];
    else
        display = [NSString stringWithFormat:@"%@ error: %@", name, msg];
    
    dict = [NSMutableDictionary dictionary];
    [dict setObject:[NSNumber numberWithInt:errCode] forKey:@"OSErr"];
    if (name) [dict setObject:name forKey:@"name"];
    if (msg) [dict setObject:msg forKey:@"description"];
    
    return [NSException exceptionWithName:OSAScriptException reason:display userInfo:dict];
}

//
// Cool except that we always ask for typeChar to let the AE stuff do coercions for us instead of asking for typeWildcard and going to all this work.
//
static id aedesc_to_id(AEDesc *desc)
{
    OSErr err;
    
    // NSLog(@"Converting type '%c%c%c%c' to id", ((char *)&(desc->descriptorType))[0], ((char *)&(desc->descriptorType))[1], ((char *)&(desc->descriptorType))[2], ((char *)&(desc->descriptorType))[3]);
    
#define FETCH_NUMERIC(ctype, nsmethod) { ctype buf; err = AEGetDescData(desc, &buf, sizeof(buf)); if (err == noErr) return [NSNumber nsmethod buf]; else [make_AE_err(err) raise]; } break

    switch(desc->descriptorType) {
        // The string type
        case typeChar:
        case typeUnicodeText:
        {
            NSMutableData *outBytes;
        
            outBytes = [[NSMutableData alloc] initWithLength:AEGetDescDataSize(desc)];
            err = AEGetDescData(desc, [outBytes mutableBytes], [outBytes length]);
            if (err) {
                [outBytes release];
                [make_AE_err(err) raise];
            } else {
                NSString *txt;
                NSStringEncoding encoding;

                encoding = (desc->descriptorType == typeUnicodeText)? NSUnicodeStringEncoding : NSMacOSRomanStringEncoding;

                txt = [[NSString alloc] initWithData:outBytes encoding:encoding];
                [outBytes release];
                [txt autorelease];
        
                return txt;
            }
        }
        
        // Numeric types
        case typeSInt16:			FETCH_NUMERIC(SInt16, numberWithShort:);
        case typeSInt32:			FETCH_NUMERIC(SInt32, numberWithInt:);
        case typeUInt32:			FETCH_NUMERIC(UInt16, numberWithUnsignedInt:);
        case typeSInt64:			FETCH_NUMERIC(SInt64, numberWithLong:);
        case typeIEEE32BitFloatingPoint:	FETCH_NUMERIC(Float32, numberWithFloat:);
        case typeIEEE64BitFloatingPoint:	FETCH_NUMERIC(Float64, numberWithDouble:);
        /* Unsupported: type128BitFloatingPoint, typeDecimalStruct. What C type are these? */
        
        // Boolean types
        case typeBoolean:
        {
            Boolean bool8    = FALSE;    // MacOS boolean type
            bool    bool32   = false;    // C++ boolean type
            BOOL    result;              // Objective-C boolean type
            
            if (AEGetDescDataSize(desc) == 1) {
                err = AEGetDescData(desc, &bool8, sizeof(bool8));
                if (!err) result = (bool8 ? YES : NO);
            } else {
                err = AEGetDescData(desc, &bool32, sizeof(bool32));
                if (!err) result = (bool32 ? YES : NO);
            }
            if (err)
                [make_AE_err(err) raise];
            else
                return [NSNumber numberWithBool:result];
        }
        case typeTrue:				return [NSNumber numberWithBool:YES];
        case typeFalse:				return [NSNumber numberWithBool:NO];
        
        // the null type is all on its lonesome, shunned by the other, more complex types (even bool, normally ridiculed for its paucity of values, tries to ingratiate itself with the integers and floats by mocking null! how sad! the enumerated types ought to stick together.)
        case typeNull:				return nil;

        /* Unimplemented types: I don't encounter most of these, so I haven't implemented them because I can't test them: */
        /* typeAEList, typeAERecord, typeAppleEvent, typeEventRecord, typeAlias, typeEnumerated, typeType, typeAppParameters, typeProperty, typeFSS, typeFSRef, typeFileURL, typeKeyword, typeSectionH, typeWildCard, typeApplSignature, typeQDRectangle, typeFixed, typeProcessSerialNumber, typeApplicationURL */
        
        /* We should at least implement list --> NSArray and record --> NSDictionary, possibly also other types --> NSURL */
    }
    
    [NSException raise:OSAScriptException format:@"[unconverted AEDesc, type=\"%c%c%c%c\"]", ((char *)&(desc->descriptorType))[0], ((char *)&(desc->descriptorType))[1], ((char *)&(desc->descriptorType))[2], ((char *)&(desc->descriptorType))[3]];
    return nil;  // compiler appeasement
}

#if 0

static void dump_osaid(long int anOSAID, ComponentInstance realComponentInstance)
{
    AEDesc valueDesc;
    OSAError osaErr;
    OSAID realScriptID;

    realScriptID = anOSAID;
    if (realComponentInstance == NULL) {
        osaErr = OSAGenericToRealID(OFAppleScriptComponent, &realScriptID, &realComponentInstance);
        if (osaErr != noErr)
            [NSException raise:OSAScriptException format:@"OSAGenericToRealID returns error code %d", osaErr];
    }

    osaErr = OSACoerceToDesc(realComponentInstance, realScriptID, typeWildCard, kOSAModeNull, &valueDesc);
    if (osaErr) {
        NSLog(@"OSACoerceToDesc --> %d", osaErr);
    } else {
        OSStatus err;
        Handle outHandle = NULL;

        err = AEPrintDescToHandle(&valueDesc, &outHandle);
        if (err) {
            NSLog(@"AEPrintDescToHandle -> %d", err);
        } else {
            NSLog(@"result: %@", [NSString stringWithCString:*outHandle length:GetHandleSize(outHandle)]);
            DisposeHandle(outHandle);
        }

        AEDisposeDesc(&valueDesc);
    }
}
#endif

//
// Cool except that we always want NSString's right now, and getting the source of a script or the string value of a result is the exact same code, so we use that.
//
static id osaid_to_id_and_dispose(ComponentInstance component, OSAID osaid)
{
    OSAError osaErr;
    AEDesc appleEvent;
    id result = nil;
    
    if (osaid == kOSANullScript)  // OSAIDs can be 0, indicating null
        return nil;
    
    // Ideally, we want to extract the value in the OSAID and convert it to the corresponding Foundation Kit value. To do that, we need to coerce it to an AEDesc, then create an NSObject based on the AEDesc's type. However, sometimes it coerces the OSAID to a type we don't understand (such as STXT, 'styled text'), or fails to coerce at all. In that case, we use OSADisplay to get something vaguely representable.
    
    osaErr = OSACoerceToDesc(component, osaid, typeWildCard, 0, &appleEvent);
    if (osaErr == noErr) {
        NS_DURING {
            result = aedesc_to_id(&appleEvent);
            OSADispose(component, osaid);
            osaid = kOSANullScript;
        } NS_HANDLER {
            // Ignore the exception, since we will try again.
        } NS_ENDHANDLER;
        AEDisposeDesc(&appleEvent);
    }
    if (osaid != kOSANullScript) {
        // NSLog(@"Coercion failed; attempting display.", osaErr);
        osaErr = OSADisplay(component, osaid, typeChar, kOSAModeNull, &appleEvent);
        OSADispose(component, osaid);
        if (osaErr)
            [make_AE_err(osaErr) raise];
        NS_DURING {
            result = aedesc_to_id(&appleEvent);
        } NS_HANDLER {
            AEDisposeDesc(&appleEvent);
            [localException raise];	// Raise the exception this time, since we don't have any other tricks up our sleeve
        } NS_ENDHANDLER;
        AEDisposeDesc(&appleEvent);
    }
    
    return result;
}

//
// Done in another way in the main source which avoids the need for all the functions
//
- executeAndRaise:(BOOL)shouldRaise;
{
    OSAID resultId;
    OSErr err;
    id result;
        
    resultId = 0;
    err = OSAExecute(OFAppleScriptComponent, scriptID, kOSANullScript, kOSAModeNull, &resultId);
    
    if (err == noErr) {
        // If no error, extract the result, and convert it to an NS type for display
        
        if (resultId != 0) { // apple doesn't mention that this can be 0?
            result = osaid_to_id_and_dispose(OFAppleScriptComponent, resultId);
        } else {
            result = nil;
        }
        
    } else if (err == errOSAScriptError) {
        AEDesc ernum, erstr;
        id ernumobj, erstrobj;
        
        // Extract the error number and error message from our scripting component.
        err = OSAScriptError(OFAppleScriptComponent, kOSAErrorNumber, typeShortInteger, &ernum);
        if (err) [make_AE_err(err) raise];
        err = OSAScriptError(OFAppleScriptComponent, kOSAErrorMessage, typeChar, &erstr);
        if (err) [make_AE_err(err) raise];
        
        // Convert them to ObjC types.
        ernumobj = aedesc_to_id(&ernum);
        AEDisposeDesc(&ernum);
        erstrobj = aedesc_to_id(&erstr);
        AEDisposeDesc(&erstr);
        
        result = [NSException exceptionWithName:OSAScriptException reason:[NSString stringWithFormat:@"Error %@: %@", ernumobj, erstrobj] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:ernumobj, @"number", erstrobj, @"string", nil]];
        
        if (shouldRaise)
            [result raise];
    } else {
        [make_AE_err(err) raise];
        result = nil; // make the compiler happy.
    }
    
    return result;
}

- (void)_showUserInterface;
{
    [[OAOSAScript bundle] loadNibNamed:@"OAScriptSheet.nib" owner:runningScript];
    if (runAttachedWindow) {
        [NSApp beginSheet:scriptSheet modalForWindow:runAttachedWindow modalDelegate:self didEndSelector:NULL contextInfo:nil];
    } else {
        [scriptSheet center];
        [scriptSheet makeKeyAndOrderFront:self];
    }
    [progressIndicator startAnimation:self];
}

- (void)_hideUserInterface;
{
    [runStartDate release];
    runStartDate = nil;

    if (!scriptSheet)
        return;
        
    [progressIndicator stopAnimation:self];
    if (runAttachedWindow)
        [NSApp endSheet:scriptSheet];
    [scriptSheet orderOut:self];
    [scriptSheet release];
    scriptSheet = nil;
    progressIndicator = nil;
}

@end

#endif
