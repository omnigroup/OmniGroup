// Copyright 1997-2005, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniFoundation/OFObject.h>

#import <OmniFoundation/OFSimpleLock.h>
#import <OmniFoundation/OFMessageQueuePriorityProtocol.h>
#import <OmniFoundation/OFWeakRetainProtocol.h>
#import <OWF/OWTargetProtocol.h>

@class NSArray, NSDate, NSException, NSNumber;
@class OFMessageQueue, OFPreference;
@class OWAddress, OWHeaderDictionary, OWProcessor, OWPipeline, OWFileInfo, OWURL;

typedef enum _OWProcessorStatus {
    OWProcessorNotStarted, OWProcessorStarting, OWProcessorQueued, OWProcessorRunning, OWProcessorAborting, OWProcessorRetired
} OWProcessorStatus;

#if 0

typedef enum {
    OWProcessor_YES = 'y',
    OWProcessor_NO = 'n',
    OWProcessor_Unknown = 0
} OWProcessorAgnosticBOOL;

#define OWProcessorAgnosticBOOLAssign(oldValue, newValue) do{ if((newValue) != OWProcessor_Unknown) { (oldValue)=(newValue); } }while(0)

#endif

@class OWCacheControlSettings;

@protocol OWProcessorContext <NSObject>

// These are used to provide scheduling information to the OFMessageQueue from which processors are dispatched.
- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;

- (void)processedBytes:(NSUInteger)bytes ofBytes:(NSUInteger)newTotalBytes;
- (NSDate *)firstBytesDate;
- (NSUInteger)bytesProcessed;
- (NSUInteger)totalBytes;

- (NSArray *)tasks;  // All OWTasks (OWPipelines, presumably) which are using this processor
- (id)promptView;  // Returns an NSView for the target, if the target has one. May be a superview, controlView, or the like
- (NSArray *)outerContentInfos;  // A list of OWContentInfos referring to resources which are using this processor, or which are using this processor themselves; these are the uppermost non-header contentInfos (e.g. the outermost frameset, or the containing HTML doc or bookmark file, or whatever)
// - (NSArray *)sisterArcs;

// Supposedly returns a string useful for log messages
- (NSString *)logDescription;

// Processors call these methods to inform the rest of the app of their status
- (void)processorStatusChanged:(OWProcessor *)aProcessor;
- (void)processorDidRetire:(OWProcessor *)aProcessor;

- (BOOL)hadError;
- (void)noteErrorName:(NSString *)nonLocalizedErrorName reason:(NSString *)localizedErrorDescription;
// - (void)contentError;  // marks pipeline as containing an error result

- (void)mightAffectResource:(OWURL *)aResource;

// These are used by a processor to deliver any content it's generated. -addContent:fromProcessor:flags: is the real method; all the others call that one.
// The "fromProcessor:(OWProcessor *)aProcessor" argument is actually redundant and is not used for anything right now except error checking. It'll probably go away eventually.
- (void)addContent:(OWContent *)someContent fromProcessor:(OWProcessor *)aProcessor;
- (void)extraContent:(OWContent *)someContent fromProcessor:(OWProcessor *)aProcessor forAddress:(OWAddress *)anAddress;
- (void)cacheControl:(OWCacheControlSettings *)control;

- (void)addContent:(OWContent *)someContent fromProcessor:(OWProcessor *)aProcessor flags:(unsigned)contentFlags;
- (void)addRedirectionContent:(OWAddress *)newLocation sameURI:(BOOL)sameObject;
- (void)addUnknownContent:(OWContent *)someContent fromProcessor:(OWProcessor *)aProcessor;

// The following are flags for -addContent:fromProcessor:flags:

#define OWProcessorContentIsSource   	   	(1 << 0)
#define OWProcessorContentIsError    	   	(1 << 1)
#define OWProcessorContentNoDiskCache      	(1 << 2)	// Inhibit disk cache for this arc (eg for file: URLs)

#define OWProcessorRedirectIsPermanent     	(1 << 4)
#define OWProcessorRedirectIsSame          	(1 << 5)

#define OWProcessorTypeRetrieval           	(1 << 6)	// this arc represents us retrieving something from somewhere
#define OWProcessorTypeAction           	(1 << 7)	// Implies that traversing the arc caused an operation to occur (e.g. a POST request)
#define OWProcessorTypeDerived			(1 << 8) 	// this arc is just a transformation or derivation of the source/subject
#define OWProcessorTypeAuxiliary     		(1 << 9)	// miscellaneous information generated as a side effect of something else

// Retrieve a given context object. Unless "depends" is NO, the context value is added to the list of parameters that must be checked to see if a given processor's result can be re-used by another pipeline.
- (id)contextObjectForKey:(NSString *)contextInformationKey;
- (id)contextObjectForKey:(NSString *)contextInformationKey isDependency:(BOOL)depends;

// For retrieving (possibly site- or target-dependent) preferences. Note that these do not go through the context dictionary and therefore do not create context-dependencies; -contextObjectForKey: will fall back to retrieving a preference if there's no context object, so in most cases you should use that.
- (OFPreference *)preferenceForKey:(NSString *)preferenceKey;

// Note that metadata (below) is distinct from context data (above). Metadata lives on an OWContent object. Context data is retrieved from the OWProcessorContext, which gets it from a pipeline, target, or (possibly site-specific) preferences entry.
// Metadata which is not just an HTTP header has a leading colon. HTTP header values are always strings; other metadata may be other classes of object. 
#define OWContentSourceEncodingMetadataKey (@":DominantCharacterEncoding")
#define OWContentEncodingProvenanceMetadataKey (@":CharacterEncodingProvenance")
#define OWContentDoctypeMetadataKey (@":DOCTYPE")  // No longer used, so no longer generated by OWHTMLTOSGMLObjectsProcessor
#define OWContentRedirectionTypeMetadataKey (@":RedirectionType")
#define OWContentInterimContentMetadataKey (@":RedirectionBody")
#define OWContentIsSourceMetadataKey (@":isSource")
#define OWContentValidatorMetadataKey (@":validator")
#define OWContentHTTPStatusMetadataKey (@":HTTPStatus")

@end


@interface OWProcessor : OFObject <OFMessageQueuePriority>
{
    id <OWProcessorContext> pipeline;
    OWContent *originalContent;

    // For display purposes
    OFSimpleLockType displayablesSimpleLock;
    OWProcessorStatus status;
    NSString *statusString;
}

+ (NSString *)readableClassName;
+ (BOOL)processorUsesNetwork;

+ (OFMessageQueue *)processorQueue;
    // Returns the message queue in which -processInThread should be invoked.  Subclasses may override this to return a different queue, or nil (in which case processing happens immediately in the current thread).
    
+ (void)registerProcessorClass:(Class)aClass fromContentType:(OWContentType *)sourceContentType toContentType:(OWContentType *)targetContentType cost:(float)aCost producingSource:(BOOL)producingSource;
+ (void)registerProcessorClass:(Class)aClass fromContentTypeString:(NSString *)sourceContentTypeString toContentTypeString:(NSString *)targetContentTypeString cost:(float)aCost producingSource:(BOOL)producingSource;

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;

- (id <OWProcessorContext>)pipeline;

// Processing
- (void)startProcessingInQueue:(OFMessageQueue *)aQueue;
- (void)startProcessing;
- (void)abortProcessing;

// Status
- (void)setStatus:(OWProcessorStatus)newStatus;
- (OWProcessorStatus)status;
- (void)setStatusString:(NSString *)newStatusString;
- (void)setStatusFormat:(NSString *)aFormat, ...;
- (void)setStatusStringWithClassName:(NSString *)newStatus;
- (NSString *)statusString;

- (void)processedBytes:(NSUInteger)bytes;
    // Use NSNotFound to indicate an unknown amount.
- (void)processedBytes:(NSUInteger)bytes ofBytes:(NSUInteger)newTotalBytes;
- (NSDate *)firstBytesDate;
- (NSUInteger)bytesProcessed;
- (NSUInteger)totalBytes;

@end

extern NSString *OWProcessorExceptionExtraMessageObjectsKey;

@interface OWProcessor (SubclassesOnly)
- (void)processBegin;
- (void)process;
- (void)processEnd;
- (void)processAbort;

// These are useful to processors which do not want to start a new thread, and which therefore subclass -startProcessing
- (void)processInThread;
- (void)retire;
- (void)handleProcessingException:(NSException *)processingException;

// These are useful for processors which generate auxiliary data
- (OWFileInfo *)cacheDate:(NSDate *)aDate forAddress:(OWAddress *)anAddress;

@end
