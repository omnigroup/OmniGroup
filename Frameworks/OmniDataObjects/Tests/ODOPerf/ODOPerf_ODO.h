// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/Tests/ODOPerf/ODOPerf_ODO.h 104583 2008-09-06 21:23:18Z kc $

#import "ODOPerf.h"

@class ODODatabase, ODOEditingContext;

@interface ODOPerf_ODO : ODOPerf
{
    ODODatabase *_database;
    NSUndoManager *_undoManager;
    ODOEditingContext *_editingContext;
}

@end
