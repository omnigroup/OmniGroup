// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWFTPSession.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniNetworking/OmniNetworking.h>
#import <OmniBase/system.h>

#import <OWF/OWAddress.h>
#import <OWF/OWAuthorizationCredential.h>
#import <OWF/OWAuthorizationRequest.h>
#import <OWF/OWContent.h>
#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWContentType.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWFileInfo.h>
#import <OWF/OWNetLocation.h>
#import <OWF/OWProcessor.h>
#import <OWF/OWProxyServer.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@interface OWFTPSession (Private)

+ (void)contentCacheFlushedNotification:(NSNotification *)notification;

- (NSData *)storeData;

- (void)setAddress:(OWAddress *)anAddress;
- (void)setProcessor:(OWProcessor *)aProcessor;
- (void)cacheSession;

- (void)setCurrentTransferType:(NSString *)aTransferType;
- (NSString *)systemType;

- (BOOL)readResponse;
- (BOOL)sendCommand:(NSString *)command;
- (BOOL)sendCommand:(NSString *)command argumentString:(NSString *)arg;
- (BOOL)sendCommand:(NSString *)command argument:(NSData *)arg;

- (void)connect;
- (void)disconnect;

- (ONTCPSocket *)passiveDataSocket;
- (ONTCPSocket *)activeDataSocket;
- (ONSocketStream *)dataSocketStream;

- (void)changeAbsoluteDirectory:(NSString *)path;
- (void)getFile:(NSString *)path;
- (void)getDirectory:(NSString *)path;
- (void)storeData:(NSData *)storeData atPath:(NSString *)path;
- (void)removeFileAtPath:(NSString *)path;
- (void)makeNewDirectoryAtPath:(NSString *)path;

- (NSString *)systemTypeForSystemReply:(NSString *)systemReply;

@end

@implementation OWFTPSession
{
    NSString *sessionCacheKey;
    ONSocketStream *controlSocketStream;
    NSString *currentPath;
    NSString *currentTransferType;
    NSString *systemType;
    NSDictionary *systemFeatures;
    NSString *lastReply;
    unsigned int lastReplyIntValue;
    NSString *lastMessage;
    
    NSMutableArray *failedCredentials;
    
    OWAddress *ftpAddress;
    __weak id <OWProcessorContext> nonretainedProcessorContext;
    __weak OWProcessor *nonretainedProcessor;
    ONSocket *abortSocket;
    BOOL abortOperation;
    
    enum OWFTP_ServerFeature serverSupportsMLST;
    enum OWFTP_ServerFeature serverSupportsUTF8;
    enum OWFTP_ServerFeature serverSupportsTVFS;
}

enum {OPEN_SESSIONS, NO_SESSIONS};

#ifdef DEBUG_kc0
static BOOL OWFTPSessionDebug = YES;
#else
static BOOL OWFTPSessionDebug = NO;
#endif

static NSMutableDictionary *openSessions;
static NSLock *openSessionsLock;
static NSTimeInterval sessionTimeout;
static NSString *asciiTransferType = @"A";
static NSString *imageTransferType = @"I";
static NSData *crlf, *aSingleSpace;
static NSString *defaultPassword = nil;

+ (void)initialize;
{
    static const char crlf_bytes[2] = { 13, 10 };
    static const char space_byte[1] = { 32 };
    
    OBINITIALIZE;

    openSessions = [[NSMutableDictionary alloc] init];
    openSessionsLock = [[NSLock alloc] init];
    sessionTimeout = 120.0; // Overridden in +readDefaults
    crlf = [[NSData alloc] initWithBytesNoCopy:(void *)crlf_bytes length:2 freeWhenDone:NO];
    aSingleSpace = [[NSData alloc] initWithBytesNoCopy:(void *)space_byte length:1 freeWhenDone:NO];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contentCacheFlushedNotification:) name:OWContentCacheFlushNotification object:nil];
}

+ (void)didLoad;
{
    [[OFController sharedController] addStatusObserver:(id)self];
}

+ (void)controllerDidInitialize:(OFController *)controller;
{
    [self readDefaults];
}

+ (void)readDefaults;
{
    NSUserDefaults *userDefaults;

    userDefaults = [NSUserDefaults standardUserDefaults];
    defaultPassword = [userDefaults stringForKey:@"OWFTPAnonymousPassword"];
    if (defaultPassword == nil || [defaultPassword isEqualToString:@""])
	defaultPassword = [[NSString alloc] initWithFormat:@"%@@%@", [[NSProcessInfo processInfo] processName], [ONHost domainName]];
    sessionTimeout = [userDefaults floatForKey:@"OWFTPSessionTimeout"];
}

+ (OWFTPSession *)ftpSessionForNetLocation:(NSString *)aNetLocation;
{
    NSString *cacheKey = aNetLocation;
    OWFTPSession *session;
    [openSessionsLock lock];
    @try {
	session = [openSessions objectForKey:cacheKey];
	if (session != nil) {
	    [openSessions removeObjectForKey:cacheKey];
	}
    } @catch (NSException *localException) {
        session = nil;
	NSLog(@"%@", [localException reason]);
    }
    [openSessionsLock unlock];
    if (session == nil)
        session = [[self alloc] initWithNetLocation:aNetLocation];

    return session;
}

+ (OWFTPSession *)ftpSessionForAddress:(OWAddress *)anAddress;
{
    OWFTPSession *session = [self ftpSessionForNetLocation:[[anAddress url] netLocation]];
    [session setAddress:anAddress];
    return session;
}

+ (int)defaultPort;
{
    return 21;
}

- initWithNetLocation:(NSString *)aNetLocation;
{
    if (!(self = [super init]))
	return nil;

    sessionCacheKey = aNetLocation;
    failedCredentials = [[NSMutableArray alloc] init];
    serverSupportsMLST = OWFTP_Maybe;
    serverSupportsUTF8 = OWFTP_Maybe;
    serverSupportsTVFS = OWFTP_Maybe;
    return self;
}

- (void)dealloc;
{
    [self disconnect];
}

- (void)fetchForProcessor:(OWProcessor *)aProcessor inContext:(id <OWProcessorContext>)aPipeline;
{
    NSException *raisedException = nil;
    NSString *ftpPath, *ftpMethod;
    BOOL returnEmptyDataForSuccess = NO;
    BOOL mutating;
    enum { Fetching, Storing, Deleting, NewDirectory } action;
    
    ftpMethod = [ftpAddress methodString];
    if ([ftpMethod isEqualToString:@"GET"] || [ftpMethod isEqualToString:@"POST"]) {
        action = Fetching;
        mutating = NO;
    } else if ([ftpMethod isEqualToString:@"PUT"]) {
        action = Storing;
        mutating = YES;
    } else if ([ftpMethod isEqualToString:@"DELETE"]) {
        /* DELETE is a valid HTTP/1.1 method */
        action = Deleting;
        mutating = YES;
    } else if ([ftpMethod isEqualToString:@"MKDIR"]) {
        action = NewDirectory;
        mutating = YES;
    } else {
        [NSException raise:@"UnsupportedMethod" format:NSLocalizedStringFromTableInBundle(@"FTP does not support the \"%@\" method", @"OWF", [OWFTPSession bundle], @"ftpsession error"), ftpMethod];
        action = Fetching; mutating = NO; // Unreached, making the compiler happy
    }
    
    ftpPath = [[ftpAddress url] fetchPath];
    if (mutating) {
        [aPipeline mightAffectResource:[ftpAddress url]];
    }
    
    // special case for ftp: the fetchPath shouldn't start with / if the path begins with ~. Needs to be done here instead of in OWURL fetchPath because this rule doesn't apply to other protocols (like http).
    if ([ftpPath length] > 1 && [ftpPath characterAtIndex:1] == '~')
        ftpPath = [ftpPath substringFromIndex:1];
    
    NS_DURING {
	[self setProcessor:aProcessor];
        nonretainedProcessorContext = aPipeline;
	[self connect];
        switch (action) {
            case Fetching:
                if ([ftpPath hasSuffix:@"/"])
                    [self getDirectory:ftpPath];
                else
                    [self getFile:ftpPath];
                break;
            case Storing:
                [self storeData:[self storeData] atPath:ftpPath];
				returnEmptyDataForSuccess = YES;
                break;
            case Deleting:
                [self removeFileAtPath:ftpPath];
				returnEmptyDataForSuccess = YES;
                break;
            case NewDirectory:
                [self makeNewDirectoryAtPath:ftpPath];
				returnEmptyDataForSuccess = YES;
                break;
        }
    } NS_HANDLER {
	raisedException = localException;
    } NS_ENDHANDLER;

    if (returnEmptyDataForSuccess) {
        // Return an empty data stream so caller gets success instead of alternate or failure
        OWDataStream *outputDataStream = [[OWDataStream alloc] init];
        OWContent *emptyContent = [OWContent contentWithDataStream:outputDataStream isSource:YES];
        
        [outputDataStream dataEnd];
        [emptyContent markEndOfHeaders];
        [nonretainedProcessorContext addContent:emptyContent fromProcessor:nonretainedProcessor flags:OWProcessorContentIsSource|OWProcessorTypeRetrieval];
    }
	
    [self cacheSession];
    if (raisedException)
        [raisedException raise];
}

- (void)abortOperation;
{
    abortOperation = YES;
    [abortSocket abortSocket];
    abortSocket = nil;
    [[controlSocketStream socket] abortSocket];
}

@end

@implementation OWFTPSession (Private)

+ (void)contentCacheFlushedNotification:(NSNotification *)notification;
{
    // When the content cache is flushed, flush all the cached FTP sessions
    [openSessionsLock lock];
    NS_DURING {
        [openSessions removeAllObjects];
    } NS_HANDLER {
        NSLog(@"+[%@ %@]: caught exception %@", NSStringFromClass(self), NSStringFromSelector(_cmd), localException);
    } NS_ENDHANDLER;
    [openSessionsLock unlock];
}

- (NSData *)storeData
{
    NSData *contentData, *contentStringData;
    NSString *contentString;

    contentString = [[ftpAddress methodDictionary] objectForKey:OWAddressContentStringMethodKey];
    contentData = [[ftpAddress methodDictionary] objectForKey:OWAddressContentDataMethodKey];

    if (contentString) {
        contentStringData = [contentString dataUsingEncoding:NSISOLatin1StringEncoding];
        if (!contentStringData)
            [NSException raise:@"UnencodableString" reason:NSLocalizedStringFromTableInBundle(@"FTP data contains characters which cannot be converted to ISO Latin-1", @"OWF", [OWFTPSession bundle], @"ftpsession error")];

        /* -dataByAppendingData: handles the contentData==nil case */
        return [contentStringData dataByAppendingData:contentData];
    } else {
        return contentData;
    }
}

- (void)setAddress:(OWAddress *)anAddress;
{
    if (ftpAddress == anAddress)
	return;
    ftpAddress = anAddress;
}

- (void)setProcessor:(OWProcessor *)aProcessor;
{
    nonretainedProcessor = aProcessor;
}

- (void)cacheSession;
{
    nonretainedProcessorContext = nil;
    [self setProcessor:nil];
    [self setAddress:nil];
    [openSessionsLock lock];
    NS_DURING {
	[openSessions setObject:self forKey:sessionCacheKey];
    } NS_HANDLER {
	NSLog(@"%@", [localException reason]);
    } NS_ENDHANDLER;
    [openSessionsLock unlock];
}

//

- (void)setCurrentTransferType:(NSString *)aTransferType;
{
    if ([currentTransferType isEqualToString:aTransferType])
	return;

    [nonretainedProcessor setStatusFormat:NSLocalizedStringFromTableInBundle(@"Setting transfer type to %@", @"OWF", [OWFTPSession bundle], @"ftpsession status"), aTransferType];
    if (![self sendCommand:@"TYPE" argumentString:aTransferType])
	[NSException raise:@"SetTransferTypeFailed" format:NSLocalizedStringFromTableInBundle(@"Failed to change transfer type: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - TYPE command failed"), lastReply];
    currentTransferType = aTransferType;
}

- (NSString *)systemType;
{
    if (systemType)
	return systemType;
    [nonretainedProcessor setStatusString:NSLocalizedStringFromTableInBundle(@"Checking system type", @"OWF", [OWFTPSession bundle], @"ftpsession status - will send SYST command")];
    if ([self sendCommand:@"SYST"])
	systemType = [self systemTypeForSystemReply:[lastReply substringFromIndex:4]];
    else
	systemType = @"unknown";
    [nonretainedProcessor setStatusFormat:NSLocalizedStringFromTableInBundle(@"System is %@", @"OWF", [OWFTPSession bundle], @"ftpsession status - result of SYST command"), systemType];
    return systemType;
}

- (BOOL)querySystemFeatures
{
    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet *nonWhitespaceSet = [whitespaceSet invertedSet];

    [nonretainedProcessor setStatusString:NSLocalizedStringFromTableInBundle(@"Checking server features", @"OWF", [OWFTPSession bundle], @"ftpsession status - will send FEAT command")];

    if (![self sendCommand:@"FEAT"]) {
        systemFeatures = [[NSDictionary alloc] init];
        return NO;
    }

    NSMutableDictionary *receivedFeatures = [NSMutableDictionary dictionary];
    [receivedFeatures setObject:@"" forKey:@"FEAT"];
    NSEnumerator *featureEnumerator = [[lastMessage componentsSeparatedByString:@"\n"] objectEnumerator];
    for (NSString *feature in featureEnumerator) {
        NSRange spRange = [feature rangeOfCharacterFromSet:nonWhitespaceSet];
        if (spRange.location == 0 || spRange.length == 0) {
            // All feature lines must start with whitespace; other lines are status codes or terminators, which we ignore. We shouldn't see any lines consisting entirely of whitespace, but if we do, we should ignore them also.
            continue;
        }

        NSUInteger nameStarts = spRange.location;
        NSUInteger lineLength = [feature length];
        spRange = [feature rangeOfCharacterFromSet:whitespaceSet options:0 range:NSMakeRange(nameStarts, lineLength - nameStarts)];

        NSString *featureName, *featureOptions;
        if (spRange.length == 0) {
            featureName = [feature substringFromIndex:nameStarts];
            featureOptions = @"";
        } else {
            featureName = [feature substringWithRange:NSMakeRange(nameStarts, spRange.location - nameStarts)];
            featureOptions = [feature substringFromIndex:NSMaxRange(spRange)];
            featureOptions = [featureOptions stringByRemovingSurroundingWhitespace];
        }

        [receivedFeatures setObject:featureOptions forKey:[featureName uppercaseString]];
    }

    systemFeatures = [receivedFeatures copy];
    return YES;
}

//

- (BOOL)readResponse;
{
    if (abortOperation)
	[NSException raise:@"FetchAborted" reason:NSLocalizedStringFromTableInBundle(@"Fetch stopped", @"OWF", [OWFTPSession bundle], @"ftpsession error")];

    NSString *reply = [controlSocketStream readLine];
    if (OWFTPSessionDebug)
	NSLog(@"FTP Rx...%@", reply);

    if (reply == nil || [reply length] < 4)
	[NSException raise:@"ResponseInvalid" format:NSLocalizedStringFromTableInBundle(@"Invalid response from FTP server: %@", @"OWF", [OWFTPSession bundle], "ftpsession error"), reply];

    NSMutableString *message = nil;
    
    if ([reply characterAtIndex:3] == '-') {
	message = [reply mutableCopy];
	[message appendString:@"\n"];
	NSString *endPrefix = [NSString stringWithFormat:@"%@ ", [reply substringToIndex:3]];
        NSString *messageLine;
	do {
	    messageLine = [controlSocketStream readLine];
	    if (OWFTPSessionDebug)
		NSLog(@"FTP Rx...%@", messageLine);
            if (messageLine == nil)
                [NSException raise:@"ResponseInvalid" format:NSLocalizedStringFromTableInBundle(@"Invalid response from FTP server: %@", @"OWF", [OWFTPSession bundle], "ftpsession error"), messageLine];
	    [message appendString:messageLine];
	    [message appendString:@"\n"];
	} while (![messageLine hasPrefix:endPrefix]);
	reply = messageLine;
    }
    lastReply = reply;
    lastReplyIntValue = [reply intValue];
    lastMessage = message != nil ? message : reply;
    return lastReplyIntValue < 400;
}

- (BOOL)sendCommand:(NSString *)command;
{
    return [self sendCommand:command argument:nil];
}

- (BOOL)sendCommand:(NSString *)command argumentString:(NSString *)arg;
{
    NSData *argData = [arg dataUsingEncoding:[controlSocketStream stringEncoding] allowLossyConversion:NO];
    if (argData == nil) {
        [NSException raise:NSInvalidArgumentException
                    reason:NSLocalizedStringFromTableInBundle(@"FTP parameter contains invalid characters", @"OWF", [OWFTPSession bundle], "ftpsession error - unexpected or unencodable characters in a command argument")];
    }

    return [self sendCommand:command argument:argData];
}

- (BOOL)sendCommand:(NSString *)command argument:(NSData *)arg;
{
    if (abortOperation)
        [NSException raise:@"FetchAborted" reason:NSLocalizedStringFromTableInBundle(@"Fetch stopped", @"OWF", [OWFTPSession bundle], @"ftpsession error")];

    BOOL plainASCII = YES;
    if (arg != nil) {
        // Scan through the arg to make sure it doesn't have any metacharacters in it which could cause protocol violations, security holes, etc.
        // While we're at it, check to see whether the arg looks like it's 100% plain ASCII, so we can decide how to log it.
        NSUInteger octetCount = [arg length];
        unsigned const char *octetPointer = [arg bytes];
        for (NSUInteger octetIndex = 0; octetIndex < octetCount; octetIndex ++) {
            int ch = octetPointer[octetIndex];

            if (ch < 16) {
                [NSException raise:NSInvalidArgumentException
                            reason:NSLocalizedStringFromTableInBundle(@"FTP parameter contains invalid characters", @"OWF", [OWFTPSession bundle], "ftpsession error - dangerous metacharacters in a command argument")];
            } else if (!isascii(ch) || !isprint(ch)) {
                plainASCII = NO;
            }
        }
    }

    if (OWFTPSessionDebug) {
        NSString *argDescription = @"";
        if (arg != nil) {
            if ([command hasPrefix:@"PASS"])
                argDescription = @"********";
            else if (plainASCII)
                argDescription = [NSString stringWithData:arg encoding:NSASCIIStringEncoding];
            else
                argDescription = [arg description];
        }
        NSLog(@"FTP Tx...%@ %@", command, argDescription);
    }

    [controlSocketStream beginBuffering];
    [controlSocketStream writeString:command];
    if (arg != nil) {
        if(![command hasSuffix:@" "])
            [controlSocketStream writeData:aSingleSpace];
        [controlSocketStream writeData:arg];
    }
    [controlSocketStream writeData:crlf];
    [controlSocketStream endBuffering];
    return [self readResponse];
}

//

- (void)connect;
{
    abortOperation = NO;
    if (controlSocketStream) {
	BOOL connectionStillValid;

	@try {
	    connectionStillValid = [self sendCommand:@"NOOP"];
        } @catch (NSException *exc) {
            OB_UNUSED_VALUE(exc);
	    connectionStillValid = NO;
	}

	if (connectionStillValid)
	    return;
    }

    controlSocketStream = nil;
    currentPath = nil;
    currentTransferType = nil;
    systemType = nil;
    lastReply = nil;

    OWNetLocation *netLocation = [[ftpAddress url] parsedNetLocation];
    [nonretainedProcessor setStatusFormat:NSLocalizedStringFromTableInBundle(@"Finding %@", @"OWF", [OWFTPSession bundle], @"ftp session status"), [netLocation shortDisplayString]];
    ONHost *serviceHost = [ONHost hostForHostname:[netLocation hostname]];
    [nonretainedProcessor setStatusFormat:NSLocalizedStringFromTableInBundle(@"Contacting %@", @"OWF", [OWFTPSession bundle], @"ftp session status"), [netLocation shortDisplayString]];
    ONTCPSocket *tcpSocket = [ONTCPSocket tcpSocket];
    [tcpSocket setReadBufferSize:32*1024];
    controlSocketStream = [[ONSocketStream alloc] initWithSocket:tcpSocket];
    NSString *port = [netLocation port];
    [tcpSocket connectToHost:serviceHost port:port ? [port intValue] : [[self class] defaultPort]];
    [nonretainedProcessor setStatusFormat:NSLocalizedStringFromTableInBundle(@"Contacted %@", @"OWF", [OWFTPSession bundle], ftp session status), [netLocation shortDisplayString]];
    if (OWFTPSessionDebug)
        NSLog(@"%@: Connected to %@ (%@)", [[self class] description], [netLocation displayString], [tcpSocket remoteAddress]);

    if (![self readResponse]) { // "220 ftp.omnigroup.com ready"
        NSString *errorReply = lastReply;
        [self disconnect];
        [NSException raise:@"ConnectFailed" format:NSLocalizedStringFromTableInBundle(@"Connection to %@ failed: %@", @"OWF", [OWFTPSession bundle], "ftpsession error - connection rejected"), [netLocation shortDisplayString], errorReply];
    }

    NSString *username = [netLocation username];
    NSString *password = nil;
    if (username == nil) {
	username = @"anonymous";
    	if (!(password = [netLocation password]))
            password = defaultPassword;
    }
    
    if (![self sendCommand:@"USER" argumentString:username]) {
	NSString *errorReply = lastReply;
	[self disconnect];
        [NSException raise:@"LoginFailed" format:NSLocalizedStringFromTableInBundle(@"Login to %@ failed: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - USER command rejected"), [netLocation shortDisplayString], errorReply];
    }
    
    if (lastReplyIntValue == 331) { // Need password
        OWAuthorizationCredential *tryThis = nil;
        if (username != nil && password == nil) {
            OWAuthorizationRequest *getPassword = [[[OWAuthorizationRequest authorizationRequestClass] alloc] initForType:OWAuth_FTP netLocation:netLocation defaultPort:[[self class] defaultPort] context:[nonretainedProcessor pipeline] challenge:nil promptForMoreThan:failedCredentials];
            NSArray *moreCredentials = [getPassword credentials];
            if (moreCredentials == nil) {
                NSString *errorString = [getPassword errorString];
                [self disconnect];
                [NSException raise:@"LoginFailed" format:NSLocalizedStringFromTableInBundle(@"Login to %@ failed: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - PASS required but no password available to us"), [netLocation displayString], errorString];
            }
            
            // set tryThis to the first credential returned that's not in failedCredentials.
            int credentialIndex = 0;
            while ([failedCredentials indexOfObjectIdenticalTo:(tryThis = [moreCredentials objectAtIndex:credentialIndex])] != NSNotFound)
                credentialIndex ++;
            // we don't need to check against [moreCredentials count], above, because OWAuthorizationRequest will never return an array containing only objects that are also in failedCredentials.
        }
        
        if (tryThis != nil)
            password = [tryThis valueForKey:@"password"]; // -[OWAuthorizationPassword password]
            
	if (![self sendCommand:@"PASS" argumentString:password]) {
            if (tryThis) {
                [failedCredentials addObject:tryThis];
            }
	    NSString *errorReply = lastReply;
	    // UNDONE: ask for a new password
	    [self disconnect];
            NSString *locationDescription = [NSString stringWithStrings:username, @"@", [netLocation hostnameWithPort], nil];
            [NSException raise:@"LoginFailed" format:NSLocalizedStringFromTableInBundle(@"Login to %@ failed: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - PASS command failed"), locationDescription, errorReply];
	}
    }
    
    if (failedCredentials) {
        // We logged in successfully. Clear out the list of failed passwords.
        [failedCredentials removeAllObjects];
    }
    
    [nonretainedProcessor setStatusString:NSLocalizedStringFromTableInBundle(@"Logged in", @"OWF", [OWFTPSession bundle], @"ftpsession status")];
    currentTransferType = asciiTransferType;
}

- (void)disconnect;
{
    if (controlSocketStream == nil)
	return;
    @try {
	[self sendCommand:@"QUIT"];
    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
        // Well, we're closing the connection anyway...
    }
    controlSocketStream = nil;
}

//

- (ONTCPSocket *)passiveDataSocket;
{
    // Note: To support IPv6 we will need to know when to send PASV and when to send LPSV or EPSV.

    if (![self sendCommand:@"PASV"])
	return nil;

    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:lastReply];
    int returnCode;
    [scanner scanInt:(int *)&returnCode];
    if (returnCode != 227)
	return nil;

    unsigned int ip = 0;
    int byteCount = 4;
    while (byteCount--) {
	[scanner scanUpToCharactersFromSet:digits intoString:NULL];
        int byte;
	[scanner scanInt:(int *)&byte];
	ip <<= 8;
	ip |= byte;
    }

    unsigned int port = 0;
    byteCount = 2;
    while (byteCount--) {
	[scanner scanUpToCharactersFromSet:digits intoString:NULL];
        int byte;
	[scanner scanInt:(int *)&byte];
	port <<= 8;
	port |= byte;
    }

    struct in_addr ipAddress;
    ipAddress.s_addr = htonl(ip);
    ONTCPSocket *dataSocket = [ONTCPSocket tcpSocket];
    [dataSocket setReadBufferSize:32 * 1024];
    @try {
	abortSocket = dataSocket;
        [dataSocket connectToAddress:
            [ONHostAddress hostAddressWithInternetAddress:&ipAddress family:AF_INET] port:port];
	abortSocket = nil;
    } @catch (NSException *localException) {
	abortSocket = nil;
	if (abortOperation)
	    [localException raise];
	dataSocket = nil;
    }
    return dataSocket;
}

- (ONTCPSocket *)activeDataSocket;
{
    ONTCPSocket *dataSocket = [ONTCPSocket tcpSocket];
    [dataSocket setReadBufferSize:32*1024];
    [dataSocket startListeningOnAnyLocalPort];
    ONPortAddress *controlSocketLocalAddress = [(ONTCPSocket *)[controlSocketStream socket] localAddress];
    unsigned short port = [dataSocket localAddressPort];

    NSString *portString = nil;
    if ([controlSocketLocalAddress addressFamily] == AF_INET) {
        struct in_addr hostip = ((struct sockaddr_in *)[controlSocketLocalAddress portAddress])->sin_addr;
        portString = [NSString stringWithFormat:@"%d,%d,%d,%d,%d,%d",
            (int)*((unsigned char *)(&hostip) + 0),
            (int)*((unsigned char *)(&hostip) + 1),
            (int)*((unsigned char *)(&hostip) + 2),
            (int)*((unsigned char *)(&hostip) + 3),
            ( port & 0xFF00 ) >> 8,
            ( port & 0x00FF )];
    } else {
        [NSException raise:@"UnsupportedAddressType" format:@"%@ does not support non-IPv4 address families (local socket is bound to [%@], af=%d)", [self class], [[controlSocketLocalAddress hostAddress] description], [controlSocketLocalAddress addressFamily]];

        // See <bug:///9935> (Frameworks-Mac Feature: Support FTP over IPv6 (RFC1545/RFC1639)):
        // To implement support for FTP over IPv6 we would presumably need to implement the LPRT and LPSV (long-address variants of PORT and PASV) as documented in RFC 1639. Before doing so we should verify that RFC 1639 hasn't been superseded by something else.
        // RFC 1639 ("Experimental") has been superseded by RFC 2428 ("Standards Track").
        // We may also need to do something to ensure that 'dataSocket' is listening on an address in the appropriate address family.

        return nil; // pacify the compiler
    }
    
    if (![self sendCommand:@"PORT" argumentString:portString])
	return nil;
    return dataSocket;
}

- (ONSocketStream *)dataSocketStream;
{
    [nonretainedProcessor setStatusString:NSLocalizedStringFromTableInBundle(@"Opening data stream", @"OWF", [OWFTPSession bundle], @"ftpsession status")];

    ONTCPSocket *dataSocket = nil;

    if ([OWProxyServer usePassiveFTP]) {
        /* try passive mode first */
        dataSocket = [self passiveDataSocket];
        
        if (dataSocket == nil)
            dataSocket = [self activeDataSocket];
    } else {
        /* try active mode first */
        dataSocket = [self activeDataSocket];

        if (dataSocket == nil)
            dataSocket = [self passiveDataSocket];
    }

    if (dataSocket == nil) {
        /* failure, nothing else to try */
        return nil;
    }

    return [[ONSocketStream alloc] initWithSocket:dataSocket];
}

//

- (void)changeAbsoluteDirectory:(NSString *)path;
{
    if ([path length] == 0)
	path = @"/";
    if (currentPath == path || [currentPath isEqualToString:path])
	return;
    [nonretainedProcessor setStatusFormat:NSLocalizedStringFromTableInBundle(@"Changing directory to %@", @"OWF", [OWFTPSession bundle], @"ftpsession status"), path];
    if (![self sendCommand:@"CWD" argument:[NSData dataWithDecodedURLString:path]]) {
	// UNDONE: Try breaking the path into individual components, and CD'ing through each level
	[NSException raise:@"CannotChangeDirectory" format:NSLocalizedStringFromTableInBundle(@"Changing directory to %@ failed: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - CWD failed"), path, lastReply];
    }
    currentPath = path;
}

- (void)getFile:(NSString *)path;
{
    NSString *file;
    NSData *decodedFileName;
    ONSocketStream *inputSocketStream;
    OWDataStream *outputDataStream;
    OWContent *fileContent;
    unsigned int contentLength = 0;
    NSString *sourceRange;
    NSString *lastModifiedTime;
    BOOL usingRestartCommand = NO;
    long long startPositionInFile = 0LL;

    file = [OWURL lastPathComponentForPath:path];
    [self changeAbsoluteDirectory:[OWURL stringByDeletingLastPathComponentFromPath:path]];
    [self setCurrentTransferType:imageTransferType];
    inputSocketStream = [self dataSocketStream];
    abortSocket = [inputSocketStream socket];
    decodedFileName = [NSData dataWithDecodedURLString:file];
    
    if ([self sendCommand:@"MDTM" argument:decodedFileName] && lastReplyIntValue == 213) {
        lastModifiedTime = [[lastReply substringFromIndex:4] stringByRemovingSurroundingWhitespace];
    } else
        lastModifiedTime = nil;

    NSArray *conditional = [nonretainedProcessorContext contextObjectForKey:OWCacheArcConditionalKey isDependency:NO];
    if (conditional != nil) {
        NSString *validatorType, *validatorValue;
        BOOL validatorMatches;
        NSNumber *conditionalSense;

        validatorType = [conditional objectAtIndex:0];
        validatorValue = [conditional objectAtIndex:1];
        conditionalSense = [conditional objectAtIndex:2];

        if ([validatorType caseInsensitiveCompare:@"Last-Modified"] == NSOrderedSame) {
            validatorMatches = [validatorValue isEqualToString:lastModifiedTime];
        } else
            validatorMatches = NO;

        if ([conditionalSense boolValue] == validatorMatches)
            return;
    }

    if ([self sendCommand:@"SIZE" argument:decodedFileName] && lastReplyIntValue == 213) {
        NSString *expectedSize = [[lastReply substringFromIndex:4] stringByRemovingSurroundingWhitespace];
        contentLength = [expectedSize unsignedIntValue];
    }

    if ((sourceRange = [nonretainedProcessorContext contextObjectForKey:OWAddressSourceRangeContextKey])) {
        NSRange dashRange = [sourceRange rangeOfString:@"-"];
        if (dashRange.length != 0) {
            NSScanner *scanner = [NSScanner scannerWithString:sourceRange];
            if ([scanner scanLongLong:&startPositionInFile] && startPositionInFile >= 0LL) {
                [self sendCommand:@"REST" argumentString:[[NSNumber numberWithLongLong:startPositionInFile] stringValue]];
                usingRestartCommand = (lastReplyIntValue == 350);
            }
        }                
    }
    
    if (![self sendCommand:@"RETR" argument:decodedFileName]) {
        NSString *oldLastReply = lastReply;
        int lastReplyMajor, lastReplyMiddle;
        
	abortSocket = nil;
        
        lastReplyMajor = lastReplyIntValue / 100;
        lastReplyMiddle = ( lastReplyIntValue / 10 ) - ( lastReplyMajor * 10 );
	if ((lastReplyMajor == 5 && lastReplyMiddle != 0 && lastReplyMiddle != 2 && lastReplyMiddle != 3) ||
                [lastReply containsString:@"not a plain file"] ||
                [lastReply containsString:@"not a regular file"] ||
                [lastReply containsString:@"Not a regular file"]) {
            /* If we can't retrieve a file try chdir'ing into it; if that succeeds, try to retrieve a directory listing */
            if ([self sendCommand:@"CWD" argument:decodedFileName]) {
                NSString *newPath = [path stringByAppendingString:@"/"];
                currentPath = newPath;
                [nonretainedProcessor setStatusString:NSLocalizedStringFromTableInBundle(@"Not a plain file; retrying as directory", @"OWF", [OWFTPSession bundle], @"ftpsession status")];
                [nonretainedProcessorContext addRedirectionContent:[ftpAddress addressForRelativeString:newPath] sameURI:NO];
                return;
            }
        }
        [NSException raise:@"RetrieveFailed"  format:NSLocalizedStringFromTableInBundle(@"Retrieve of %@ failed: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error"), file, oldLastReply];
    }

#warning TODO - Retrieve file type hints from the cache
    // The MLST and MLSD commands can return the MIME-type of the file; using that would be better than inferring it from the filename
    
    outputDataStream = [[OWDataStream alloc] init];
    fileContent = [OWContent contentWithDataStream:outputDataStream isSource:YES];
    [fileContent addHeaders:[OWContentType contentTypeAndEncodingForFilename:path isLocalFile:NO]];
    if (lastModifiedTime != nil) {
        [fileContent addHeader:@"Last-Modified" value:lastModifiedTime];
        [fileContent addHeader:OWContentValidatorMetadataKey value:@"Last-Modified"];
    }
    if (usingRestartCommand)
        [outputDataStream setStartPositionInFile:startPositionInFile];
    [fileContent markEndOfHeaders];
    [nonretainedProcessorContext addContent:fileContent fromProcessor:nonretainedProcessor flags:OWProcessorContentIsSource|OWProcessorTypeRetrieval];

    [nonretainedProcessor setStatusString:NSLocalizedStringFromTableInBundle(@"Reading data", @"OWF", [OWFTPSession bundle], @"ftpsession status")];

    if (contentLength == 0 && [lastReply hasSuffix:@" bytes)."]) {
	NSRange sizeHintRange;

	sizeHintRange = [lastReply rangeOfString:@" (" options:NSLiteralSearch | NSBackwardsSearch];
	if (sizeHintRange.length > 0)
	    contentLength = [[lastReply substringFromIndex:NSMaxRange(sizeHintRange)]
	       intValue];
    }
#warning Retrieve file size hints from the cache
#if 0
    if (contentLength == 0) {
	OWFileInfo *fileInfo;

        fileInfo = (id)[[nonretainedProcessorContext contentCacheForLastAddress] contentOfType:[OWFileInfo contentType]];
        if ([fileInfo size] != nil)
            contentLength = [[fileInfo size] intValue];
    }
#endif

    @try {
	unsigned int dataBytesRead = 0;
	[nonretainedProcessor processedBytes:dataBytesRead ofBytes:contentLength];

	while (YES) {
            @autoreleasepool {
                NSData *data = [inputSocketStream readData];
                if (data == nil)
                    break;

                NSUInteger dataLength = [data length];
                dataBytesRead += dataLength;
                [nonretainedProcessor processedBytes:dataBytesRead ofBytes:contentLength];
                [outputDataStream writeData:data];
            }
	}
    } @catch (NSException *localException) {
	abortSocket = nil;
	[outputDataStream dataAbort];
	[localException raise];
    }

    [outputDataStream dataEnd];
    abortSocket = nil;

    if (![self readResponse]) // "226 Transfer complete"
	[NSException raise:@"RetrieveStopped" format:NSLocalizedStringFromTableInBundle(@"Retrieve of %@ stopped: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error"), file, lastReply];
}    
	
- (void)getDirectory:(NSString *)path;
{
    [self changeAbsoluteDirectory:path];
    
    /* Check whether we can use MLST / MLSD. */
    if (serverSupportsMLST == OWFTP_Maybe) {
        if (systemFeatures == nil && ![self querySystemFeatures]) {
            serverSupportsMLST = OWFTP_No;  // actually we don't know if it does; perhaps we should just try and see. But servers that support MLST are generally featureful enough to support FEAT, and it's always good to avoid confusing the older servers.
        } else {
            serverSupportsMLST = ( [systemFeatures objectForKey:@"MLST"] ? OWFTP_Yes : OWFTP_No );
        }
    }

    /* Issue either an MLST or a LIST command, as appropriate */
    ONSocketStream *inputSocketStream;
    NSString *directoryListingType;
    if (serverSupportsMLST == OWFTP_Yes) {
        inputSocketStream = [self dataSocketStream];
        directoryListingType = @"OWFTPDirectory/MLST";
        if (![self sendCommand:@"MLSD"]) {
            [NSException raise:@"ListAborted" format:NSLocalizedStringFromTableInBundle(@"List stopped: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - MLSD command failed"), lastReply];
        }
    } else {
        directoryListingType = [@"OWFTPDirectory/" stringByAppendingString:[self systemType]];
        [self setCurrentTransferType:asciiTransferType];
        inputSocketStream = [self dataSocketStream];
        if (![self sendCommand:@"LIST"]) {
            [NSException raise:@"ListAborted" format:NSLocalizedStringFromTableInBundle(@"List stopped: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - LIST command failed"), lastReply];
        }
    }

    OWDataStream *outputDataStream = [[OWDataStream alloc] init];
    OWContent *directoryContent = [OWContent contentWithDataStream:outputDataStream isSource:YES];
    [directoryContent setContentTypeString:directoryListingType];
    [directoryContent markEndOfHeaders];
    [nonretainedProcessorContext addContent:directoryContent fromProcessor:nonretainedProcessor flags:OWProcessorContentIsSource|OWProcessorTypeRetrieval];

    [nonretainedProcessor setStatusString:NSLocalizedStringFromTableInBundle(@"Reading directory", @"OWF", [OWFTPSession bundle], @"ftpsession status")];
    @try {
        unsigned int dataBytesRead = 0;
        [nonretainedProcessor processedBytes:dataBytesRead];
        while (YES) {
            @autoreleasepool {
                NSData *data = [inputSocketStream readData];
                if (data == nil)
                    break;
                dataBytesRead += [data length];
                [nonretainedProcessor processedBytes:dataBytesRead];
                [outputDataStream writeData:data];
                if (abortOperation)
                    [NSException raise:@"FetchAborted" reason:NSLocalizedStringFromTableInBundle(@"Fetch stopped", @"OWF", [OWFTPSession bundle], @"ftpsession error")];
            }
        }
    } @catch (NSException *localException) {
	abortSocket = nil;
	[outputDataStream dataAbort];
	[localException raise];
    }
    
    [outputDataStream dataEnd];
    if (![self readResponse]) // "226 Transfer complete"
	[NSException raise:@"ListAborted" format:NSLocalizedStringFromTableInBundle(@"List stopped: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error"), lastReply];
}

#define BLOCK_SIZE (4096)

- (void)storeData:(NSData *)storeData atPath:(NSString *)path;
{
    ONSocketStream *outputSocketStream = nil;

    NSString *file = [OWURL lastPathComponentForPath:path];

    [self changeAbsoluteDirectory:[OWURL stringByDeletingLastPathComponentFromPath:path]];
    [self setCurrentTransferType:imageTransferType];
    @autoreleasepool {
        outputSocketStream = [self dataSocketStream];
    }
    abortSocket = [outputSocketStream socket];
    if (![self sendCommand:@"STOR" argument:[NSData dataWithDecodedURLString:file]]) {
        abortSocket = nil;
        [NSException raise:@"StoreFailed" format:NSLocalizedStringFromTableInBundle(@"Store of %@ failed: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - STOR command failed"), file, lastReply];
    }

    [nonretainedProcessor setStatusString:NSLocalizedStringFromTableInBundle(@"Storing data", @"OWF", [OWFTPSession bundle], @"ftpsession status")];
    NSUInteger contentLength = [storeData length];

    @try {
        unsigned int dataBytesWritten = 0;
        [nonretainedProcessor processedBytes:dataBytesWritten ofBytes:contentLength];

        while (dataBytesWritten < contentLength) {
            @autoreleasepool {
                NSRange subdataRange = {.location = dataBytesWritten, .length = BLOCK_SIZE};
                if (NSMaxRange(subdataRange) > contentLength)
                    subdataRange.length = contentLength - dataBytesWritten;
                NSData *data = [storeData subdataWithRange:subdataRange];
                dataBytesWritten += subdataRange.length;
                [nonretainedProcessor processedBytes:dataBytesWritten ofBytes:contentLength];
                [outputSocketStream writeData:data];
            }
        }
    } @finally {
        abortSocket = nil;
    }

    if (![self readResponse]) // "226 Transfer complete"
        [NSException raise:@"StoreAborted" format:NSLocalizedStringFromTableInBundle(@"Store of %@ stopped: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error"), file, lastReply];
}    

- (void)removeFileAtPath:(NSString *)path;
{
    NSString *file;

    file = [OWURL lastPathComponentForPath:path];
    [self changeAbsoluteDirectory:[OWURL stringByDeletingLastPathComponentFromPath:path]];
    if (![self sendCommand:@"DELE" argument:[NSData dataWithDecodedURLString:file]])
        [NSException raise:@"RemoveFailed" format:NSLocalizedStringFromTableInBundle(@"Delete of %@ failed: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - DELE command failed"), file, lastReply];
}

- (void)makeNewDirectoryAtPath:(NSString *)path;
{
    NSString *dirName = [OWURL lastPathComponentForPath:path];
    
    [self changeAbsoluteDirectory:[OWURL stringByDeletingLastPathComponentFromPath:path]];
    if (![self sendCommand:@"MKD" argument:[NSData dataWithDecodedURLString:dirName]])
        [NSException raise:@"MakeDirectoryFailed" format:NSLocalizedStringFromTableInBundle(@"Creation of directory %@ failed: %@", @"OWF", [OWFTPSession bundle], @"ftpsession error - MKD command failed"), dirName, lastReply];
}

//

- (NSString *)systemTypeForSystemReply:(NSString *)systemReply;
{
    NSRange whitespaceRange;

    if ([systemReply hasPrefix:@"UNIX Type: L8MAC-OSMachTen"])
	return @"MacOS-MachTen";
    if ([systemReply hasPrefix:@"MACOS Peter's Server"])
	return @"MacOS-PeterLewis";
    if ([systemReply containsString:@"MAC-OS TCP/ConnectII"])
	return @"MacOS-TCPConnectII";

    // Return first word
    whitespaceRange = [systemReply rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
    if (whitespaceRange.length > 0)
	return [systemReply substringToIndex:whitespaceRange.location];

    return systemReply;
}

@end
