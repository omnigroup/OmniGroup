OmniGroup
===========

Checking out the source
-----------------------

    git clone git://github.com/omnigroup/OmniGroup
    git submodule update --init

Xcode
-------------------

- We currently use Xcode 6.1 for iOS and Mac OS X. You'll probably have the best results if you do too.
- Add the projects you want to your workspace.
- If building for iOS, you need to edit your scheme to turn off implicit dependencies and parallel builds. Xcode doesn't understand implicit dependencies with static libraries, so you'll need to add the dependencies to your scheme in the right order. We're in the process of converting to iOS frameworks, which should help avoid this Xcode problem.
- Take a look in the Workspaces directory for a sample workspace for the TextEditor iPad example app.

Supported Targets
----------------------

- We require iOS 8.0 and Mac OS X 10.10.

Configuring the Source
----------------------

We place our project-wide configuration options in xcconfig files, under `OmniGroup/Configurations`. The naming scheme of the files is fairly straightforward, hopefully. Each project has `Omni-Global-{Debug,Release,...}.xcconfig` as the basis for the corresponding configuration. Each Mac target has `Omni-{Bundle,Application,Tool,...}-{Debug,Release,...}.xcconfig` and each iOS target has `Touch-{Application,Library}-{Debug,Release,...}.xcconfig`. Each of these end point configurations when `#include`s 'superclass' configurations (with "Common" in the name).

 
Building
--------

The Workspaces directory contains a couple sample workspace that can be built from Xcode.

Enjoy!
