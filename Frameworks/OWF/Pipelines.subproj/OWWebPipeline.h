// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWPipeline.h>

typedef enum {
    OWWebPipelineForwardHistoryAction,
    OWWebPipelineBackwardHistoryAction,
    OWWebPipelineReloadHistoryAction
} OWWebPipelineHistoryAction;

@class OFScheduledEvent;

@interface OWWebPipeline : OWPipeline
{
    OWWebPipelineHistoryAction historyAction;
}

- (OWWebPipelineHistoryAction)historyAction;
- (void)setHistoryAction:(OWWebPipelineHistoryAction)newHistoryAction;

- (BOOL)proxyCacheDisabled;
- (void)setProxyCacheDisabled:(BOOL)newDisabled;

@end

