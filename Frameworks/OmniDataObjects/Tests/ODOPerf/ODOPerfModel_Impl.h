// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/Tests/ODOPerf/ODOPerfModel_Impl.h 104583 2008-09-06 21:23:18Z kc $

#if ODO_PERF_MODEL_ODO
    #define ODO_PERF_MODEL_CLASS_NAME(x) ODO_ ## x
    #define ODO_PERF_MODEL_SUPERCLASS ODOObject
    #import <OmniDataObjects/OmniDataObjects.h>
#elif ODO_PERF_MODEL_CD
    #define ODO_PERF_MODEL_CLASS_NAME(x) CD_ ## x
    #define ODO_PERF_MODEL_SUPERCLASS NSManagedObject
    #import <CoreData/CoreData.h>
#else
    #error No model type defined
#endif
#import "ODOPerfModel.h"

#define Bug ODO_PERF_MODEL_CLASS_NAME(Bug)
#define Note ODO_PERF_MODEL_CLASS_NAME(Note)
#define Tag ODO_PERF_MODEL_CLASS_NAME(Tag)
#define State ODO_PERF_MODEL_CLASS_NAME(State)
#define BugTag ODO_PERF_MODEL_CLASS_NAME(BugTag)

@interface Bug : ODO_PERF_MODEL_SUPERCLASS
@end
@interface Note : ODO_PERF_MODEL_SUPERCLASS
@end
@interface Tag : ODO_PERF_MODEL_SUPERCLASS
@end
@interface State : ODO_PERF_MODEL_SUPERCLASS
@end
@interface BugTag : ODO_PERF_MODEL_SUPERCLASS
@end

@implementation Bug
@end
@implementation Note
@end
@implementation Tag
@end
@implementation State
@end
@implementation BugTag
@end
