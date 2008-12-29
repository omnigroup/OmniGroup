// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Pipelines.subproj/OWWebPipeline.h 68913 2005-10-03 19:36:19Z kc $

#import <OWF/OWPipeline.h>
#import <OWF/FrameworkDefines.h>

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

