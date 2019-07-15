// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSNotification, NSSet;
@class OWContent, OWContentCacheGroup, OWContentInfo, OWContentType, OWPipeline, OWSitePreference;

// WARNING: Methods in this protocol may be called from any thread

typedef enum {
    OWTargetContentDisposition_ContentAccepted,
        // Accept this content, cancel earlier pipelines
    OWTargetContentDisposition_ContentRejectedAbortAndSavePipeline,
        // Reject this content and abort the pipeline, but keep this pipeline associated with its target so that we can get its status
    OWTargetContentDisposition_ContentRejectedCancelPipeline,
        // Reject this content, cancel this pipeline (default for optional methods)
    OWTargetContentDisposition_ContentUpdatedOrTargetChanged,
        // The content or target has changed, do more processing
    OWTargetContentDisposition_ContentRejectedContinueProcessing
        // Reject this content, but try to transform it into something else
} OWTargetContentDisposition;

typedef enum {
    OWContentOfferDesired,     // The pipeline has produced content of the targetContentType
    OWContentOfferAlternate,   // The pipeline has produced content of one of the targetAlternateContentTypes
    OWContentOfferError,       // The pipeline has encountered an error, and produced descriptive content
    OWContentOfferFailure      // The pipeline did not encounter a processing error but was unable to produce anything the target wanted; perhaps an unknown protocol, perhaps an unexpected content type returned from a server
} OWTargetContentOffer;


@protocol OWTarget
// Targets must call +[OWPipeline invalidatePipelinesForTarget:self] in order to be released, so they should do it in their -invalidate methods (or some such) which is called by their owning classes when the owning class is going away.

- (OWContentType *)targetContentType;
    // This returns the eventual ("target") content type desired by the target.

- (OWTargetContentDisposition)pipeline:(OWPipeline *)aPipeline hasContent:(OWContent *)someContent flags:(OWTargetContentOffer)contentFlags;
    // Pipelines deliver content to their targets using this method.  If the target accepts this content, it should return OWTargetContentAccepted.

// TODO: Make the remaining methods optional.

- (OWContentInfo *)parentContentInfo;
    // This links the target into the app's pipeline hierarchy.  Return your parent's content info (e.g., an inline image would return its html page's content info) or a header content info (+[OWContentInfo headerContentInfoWithName:]).

- (NSString *)targetTypeFormatString;
    // The targetTypeFormatString is used to give the user some notion of what a pipeline is doing (e.g., loading a document).  A %@ in the string will be replaced with the content type string (e.g. @"%@ Document" -> "HTML Document").

@end

@protocol OWOptionalTarget <OWTarget>

- (void)pipelineDidBegin:(OWPipeline *)aPipeline;
    // Called when the pipeline first starts processing content.

- (NSDictionary *)targetAlternateContentTypes;
    // Indicates whether the target is likely to do something useful if -pipeline:hasAlternateContent: is called. This won't force the pipeline to call (or not call) hasAlternateContent:, but can provide a hint as to the most useful behavior.

- (void)pipelineDidEnd:(OWPipeline *)aPipeline;
    // Called when the pipeline deactivates.
    // NB:  -pipelineDidEnd: is *not* always called on a given target. For example: if the target implictly or explicitly returns OWTargetContentDisposition_ContentRejectedCancelPipeline, because the pipeline will invalidate itself (setting its target to nil) before it gets around to sending the -pipelineDidEnd: message. There are other cases.

- (void)pipelineTreeDidActivate:(NSNotification *)aPipeline;
    // Called when the pipeline or one of its children becomes active.

- (void)pipelineTreeDidDeactivate:(NSNotification *)aPipeline;
    // Called when the pipeline and all its children become inactive.

- (void)parentContentInfoLostContent;

- (NSString *)expectedContentDescriptionString;
    // If we have some idea what sort of content we'll be getting, we can implement this method to give this hint to the pipeline. It returns a localized string which will be presented to the user, possibly as part of a longer message.

- (void)updateStatusForPipeline:(OWPipeline *)pipeline;

- (void)pipeline:(OWPipeline *)aPipeline hasNewMetadata:(NSSet *)changedHeaders;

- (OWContentCacheGroup *)defaultCacheGroup;

- (id)promptViewForPipeline:(OWPipeline *)aPipeline;  // Returns an NSView for the target, if the target has one. May be a superview, controlView, or the like

- (OWSitePreference *)preferenceForKey:(NSString *)key; // Returns an OWSitePreference for the given key. If this is unimplemented, or returns nil, the pipeline will look up the content itself.

@end
